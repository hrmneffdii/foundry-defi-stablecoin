// SPDX-License-Identifier: SEE LICENSE IN LICENSE

// Contract elements should be laid out in the following order:
//     Pragma statements
//     Import statements
//     Events
//     Errors
//     Interfaces
//     Libraries
//     Contracts

// Inside each contract, library or interface, use the following order:
//     Type declarations
//     State variables
//     Events
//     Errors
//     Modifiers
//     Functions

pragma solidity ^0.8.20;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/*
 * @title DSCEngine
 * @author Herman effendi
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg at all times.
 * This is a stablecoin with the properties:
 * - Exogenously Collateralized
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees, and was backed by only WETH and WBTC.
 *
 * Our DSC system should always be "overcollateralized". At no point, should the value of
 * all collateral < the $ backed value of all the DSC.
 *
 * @notice This contract is the core of the Decentralized Stablecoin system. It handles all the logic
 * for minting and redeeming DSC, as well as depositing and withdrawing collateral.
 * @notice This contract is based on the MakerDAO DSS system
 */

contract DSCEngine is ReentrancyGuard {
    ////////////////////
    //// Events      ///
    ///////////////////
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );

    ///////////////////
    //// Errors      ///
    ///////////////////
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAndPriceFeedMustBeSameLength();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferFailed();
    error DSCEngine__HealthFactorIsBroken(address _user);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();

    ///////////////////////////////
    //// State Variables      /////
    ///////////////////////////////
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;

    mapping(address token => address priceFeed) private s_priceFeeds; // token to price feed
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited; // user => token addresses to amount of deposit
    mapping(address user => uint256 amountDscMinted) private s_DscMinted; // user => total amount of dsc minted

    address[] private s_collateralTokens; // array of address collateral
    DecentralizedStableCoin private immutable i_dsc; // ERC20 standard DSC

    ///////////////////
    //// Modifiers ////
    ///////////////////

    modifier MoreThanZero(uint256 _amount) {
        if (_amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address _tokenAddress) {
        if (s_priceFeeds[_tokenAddress] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }

    ///////////////////
    //// Functions ////
    ///////////////////

    constructor(address[] memory _tokenAddresses, address[] memory _priceFeeds, address dscAddress) {
        if (_tokenAddresses.length != _priceFeeds.length) {
            revert DSCEngine__TokenAndPriceFeedMustBeSameLength();
        }

        for (uint256 i = 0; i < _tokenAddresses.length; i++) {
            s_priceFeeds[_tokenAddresses[i]] = _priceFeeds[i];
            s_collateralTokens.push(_tokenAddresses[i]);
        }

        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    ////////////////////////////
    //// External Functions ////
    ////////////////////////////

    /**
     * @notice this function will deposit collateral and mint DSC in the one transaction
     * @param _tokenCollateralAddress address of the collateral token
     * @param _amountCollateral amount of collateral
     * @param _amountDscToMint amount of DSC to mint
     */
    function depositCollateralAndMintDsc(
        address _tokenCollateralAddress,
        uint256 _amountCollateral,
        uint256 _amountDscToMint
    ) external {
        depositCollateral(_tokenCollateralAddress, _amountCollateral);
        mintDsc(_amountDscToMint);
    }

    /**
     * @notice Just deposit collateral and don't have an ability to mint DSC
     * @notice follows CEI (Check Effect Interaction)
     * @param _tokenCollateralAddress The address of the collateral token
     * @param _amountCollateral The amount of collateral
     */
    function depositCollateral(address _tokenCollateralAddress, uint256 _amountCollateral)
        public
        MoreThanZero(_amountCollateral)
        isAllowedToken(_tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][_tokenCollateralAddress] += _amountCollateral;
        emit CollateralDeposited(msg.sender, _tokenCollateralAddress, _amountCollateral);
        bool success = IERC20(_tokenCollateralAddress).transferFrom(msg.sender, address(this), _amountCollateral);

        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     * @notice this function will redeem DSC and burn collateral in the one transaction
     * @param _tokenCollateralAddress address of the collateral token to redeem
     * @param _amountCollateral amount of collateral to redeem
     * @param _amountDscToBurn amount dsc to burn
     */
    function redeemCollateralForDsc(
        address _tokenCollateralAddress,
        uint256 _amountCollateral,
        uint256 _amountDscToBurn
    ) external {
        burnDsc(_amountDscToBurn);
        redeemCollateral(_tokenCollateralAddress, _amountCollateral);
    }

    function redeemCollateral(address _tokenCollateralAddress, uint256 _amountCollateral)
        public
        MoreThanZero(_amountCollateral)
        nonReentrant
    {
        _redeemCollateral(msg.sender, msg.sender, _tokenCollateralAddress, _amountCollateral);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice follows CEI (Check Effect Interaction)
     * @param _amountDscToMint The amount of DSC to mint
     * @notice they must have more collateral value than the minimum threshold
     */
    function mintDsc(uint256 _amountDscToMint) public MoreThanZero(_amountDscToMint) nonReentrant {
        s_DscMinted[msg.sender] += _amountDscToMint;

        // they minted too much ($150 DSC, $100 ETH)
        _revertIfHealthFactorIsBroken(msg.sender);
        bool success = i_dsc.mint(msg.sender, _amountDscToMint);
        if (!success) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnDsc(uint256 _amountDscToBurn) public MoreThanZero(_amountDscToBurn) {
        _burnDsc(_amountDscToBurn, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice you can partiallly liquidate your DSC
     * @notice you will get a liquidation bonus for taking the users funds.
     * @notice this function working assumes the protocol will be roughly 200% overcollateralized in order for this work
     * @notice a known bug would be if the protocol 100% or less collateralized, then we would not be able to incentive he liquidator
     * @param _collateralAddress The ERC20 collateral address to liquidate from the user
     * @param _user the user who has broken the health factor, the health factor should be below MIN_HEALTH_FACTOR
     * @param _amountToDebt The amount of DSC tou want to burn to improve the users health factor
     */
    function liquidate(address _collateralAddress, address _user, uint256 _amountToDebt)
        external
        MoreThanZero(_amountToDebt)
        nonReentrant
    {
        uint256 startingHealthFactor = _healthFactor(_user);
        if (startingHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }

        uint256 tokenAmountFromDebt = getTokenAmountFromUsd(_collateralAddress, _amountToDebt);
        uint256 bonusCollateral = (tokenAmountFromDebt * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebt + bonusCollateral;
        _redeemCollateral(_user, msg.sender, _collateralAddress, totalCollateralToRedeem);
        _burnDsc(_amountToDebt, _user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(_user);
        if (endingUserHealthFactor <= startingHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }

        _revertIfHealthFactorIsBroken(_user);
    }

    function getHealthFactor() external {}

    /////////////////////////////
    //// Internal Functions  ////
    /////////////////////////////

    function _burnDsc(uint256 _amountDscToBurn, address onBehalfOf, address dscFrom) private {
        s_DscMinted[onBehalfOf] -= _amountDscToBurn;
        bool success = i_dsc.transferFrom(dscFrom, address(this), _amountDscToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(_amountDscToBurn);
    }

    function _getAccountInformation(address _user)
        internal
        view
        returns (uint256 _totalDscMinted, uint256 _totalCollateralValueInUsd)
    {
        _totalDscMinted = s_DscMinted[_user];
        _totalCollateralValueInUsd = getAccountCollateralValueInUsd(_user);
    }

    function _redeemCollateral(address _from, address _to, address _tokenCollateralAddress, uint256 _amountCollateral)
        private
    {
        s_collateralDeposited[_from][_tokenCollateralAddress] -= _amountCollateral;
        emit CollateralRedeemed(_from, _to, _tokenCollateralAddress, _amountCollateral);
        bool success = IERC20(_tokenCollateralAddress).transfer(_to, _amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     * Returns how close to liquidation a user is
     * if a user goes bellow 1, then can get liquidated
     */
    function _healthFactor(address _user) private view returns (uint256) {
        // 100 DSC / 150 ETH
        (uint256 _totalDscMinted, uint256 _totalCollateralValue) = _getAccountInformation(_user);

        // 150 DSC * 50 / 100 = 75
        uint256 collateralAdjusted = (_totalCollateralValue * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        // $150 ETH / $100 DSC = 1.5
        // 150 * 50 = 7500 / 100 = (75/100) < 1

        // 1000 ETH / 100 DSC
        // 1000 * 50 = 50000 / 100 = (500/100) > 1
        return (collateralAdjusted * PRECISION) / _totalDscMinted;
        // 75 * 1e18 / 100 < 1e18
    }

    function _revertIfHealthFactorIsBroken(address _user) internal view {
        uint256 healthFactor = _healthFactor(_user);
        if (healthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorIsBroken(_user);
        }
    }

    /////////////////////////////
    //// Public  Functions  ////
    /////////////////////////////

    function getTokenAmountFromUsd(address _tokenCollateralAddress, uint256 _usdAmountInWei)
        public
        view
        returns (uint256)
    {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[_tokenCollateralAddress]);
        (, int256 price,,,) = priceFeed.latestRoundData();

        return (_usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function getAccountCollateralValueInUsd(address _user) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[_user][token];
            totalCollateralValueInUsd += getValueInUSD(token, amount);
        }
    }

    function getValueInUSD(address _token, uint256 _amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[_token]);
        (, int256 price,,,) = priceFeed.latestRoundData();

        // $ 1 ETH = $ 1000
        // the returned from CL will be 1000 * 1e8

        return (uint256(price) * ADDITIONAL_FEED_PRECISION) * _amount / PRECISION;
        // ((1000 * 1e8 * 1e10 ) * amount) / 1e18 -> $USD / ETH
    }
}
