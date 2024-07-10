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
import {OracleLib} from "./libraries/OracleLib.sol";

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

    // collateral address with the price feed itself, for example token collateral address => price feed chainlink 
    mapping(address tokenCollateral => address priceFeedChainlink) private s_priceFeeds; 

    // user who has collateral will be stored as a token , for example 10e18 token in wei
    mapping(address user => mapping(address tokenCollateral => uint256 amountOfToken)) private s_collateralDeposited; 
  
    // user who has minted will be stored as a token , for example 10e18 dsc in wei
    mapping(address user => uint256 amountDscMinted) private s_DscMinted; 

    // array of address collateral
    address[] private s_collateralTokens; 

    // ERC20 standard for DSC
    DecentralizedStableCoin private immutable i_dsc; 

    using OracleLib for AggregatorV3Interface;

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
     * @notice this function receive the amount of collateral through token and token collateral address itself
     * for example if the token is ETH and the collateral is WETH and it will be deposited / saved as WETH
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
        //          1e18                   7000e18 usd in wei
        (uint256 _totalDscMinted, uint256 _totalCollateralValueInUsd) = _getAccountInformation(_user);

        if(_totalDscMinted == 0) return type(uint256).max;

        //                              7000e18                 *   50                  / 100   -> 3500e18
        uint256 collateralAdjusted = (_totalCollateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
      
      //        3500e18 * 1e18  / 1e18 -> 3500e18
        return (collateralAdjusted * PRECISION) / _totalDscMinted;
      // MIN_HEALTH_FACTOR = 1e18 --> perbandingan yang sama
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

    /**
     * @notice this function receive address of token collateral and usd in wei 1e18
     * additionally, this function will return amount of token in wei
     */
    function getTokenAmountFromUsd(address _tokenCollateralAddress, uint256 _usdAmountInWei)
        public
        view
        returns (uint256)
    {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[_tokenCollateralAddress]);
        (, int256 price,,,) = priceFeed.latestRoundData();

            // (    7000e18     *   1e18  )  / (    3500e8     *        1e10        ) -> 2e18 of token in wei 
        return (_usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    /**
     * @notice this function receive address of token collateral and token amount in wei
     * additionally, this function will return usd in wei 
     */
    function getValueInUSD(address _tokenCollateral, uint256 _tokenAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[_tokenCollateral]);
        (, int256 price,,,) = priceFeed.latestRoundData();

        // price             -> 3500 usd / eth
        // _tokenAmountInWei -> amount of token in wei

        //     (3500e8         *        1e10                *           2e18    /   1e18    -> 7000e18 usd (in wei)
        return (uint256(price) * ADDITIONAL_FEED_PRECISION) * _tokenAmountInWei / PRECISION ;
    }

    /**
     * @notice this function will calculate the total of collateral in usd
     */
    function getAccountCollateralValueInUsd(address _user) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[_user][token];
            totalCollateralValueInUsd += getValueInUSD(token, amount);
        }

        return totalCollateralValueInUsd;
    }

    function getAccountInformation(address _user) public view returns (uint256 _totalDscMinted, uint256 _totalCollateralValueInUsd) {
        (_totalDscMinted, _totalCollateralValueInUsd) = _getAccountInformation(_user);
    }

    function getHealthFactor(address _user) public view returns (uint256){
        return _healthFactor(_user);
    }

    function getCollateralBalanceOfUser(address _user, address _token) public view returns(uint256) {
        return s_collateralDeposited[_user][_token];
    }

    function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return s_priceFeeds[token];
    }

    function getDsc() external view returns (address) {
        return address(i_dsc);
    }

    function getCollateralTokens() external view returns(address[] memory){
        return s_collateralTokens;
    }

    function getMinHealthFactor() external pure returns(uint256){
        return MIN_HEALTH_FACTOR;
    }

}
