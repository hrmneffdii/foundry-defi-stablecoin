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

pragma solidity ^0.8.19;

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

    ///////////////////
    //// Errors      ///
    ///////////////////
    error DSCEngine__NeedsMoreThanZero(uint256 _amount);
    error DSCEngine__TokenAndPriceFeedMustBeSameLength();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferFailed();
    error DSCEngine__HealthFactorIsBroken(address _user);
    error DSCEngine__MintFailed();

    ///////////////////////////////
    //// State Variables      /////
    ///////////////////////////////
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;

    mapping(address token => address priceFeed) private s_priceFeeds; // token to price feed
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DscMinted;

    address[] private s_collateralTokens;
    DecentralizedStableCoin private immutable i_dsc;

    ///////////////////
    //// Modifiers ////
    ///////////////////

    modifier MoreThanZero(uint256 _amount) {
        if (_amount == 0) {
            revert DSCEngine__NeedsMoreThanZero(_amount);
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

    function depositCollateralAndMintDsc() external {}

    /**
     * @notice Just deposit collateral and don't have an ability to mint DSC
     * @notice follows CEI (Check Effect Interaction)
     * @param _tokenCollateralAddress The address of the collateral token
     * @param _amountCollateral The amount of collateral
     */
    function depositCollateral(address _tokenCollateralAddress, uint256 _amountCollateral)
        external
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

    function redeemCollateralForDsc() external {}

    function redeemCollateral() external {}

    /**
     * @notice follows CEI (Check Effect Interaction)
     * @param _amountDscToMint The amount of DSC to mint
     * @notice they must have more collateral value than the minimum threshold
     */
    function mintDsc(uint256 _amountDscToMint) external MoreThanZero(_amountDscToMint) nonReentrant {
        s_DscMinted[msg.sender] += _amountDscToMint;

        // they minted too much ($150 DSC, $100 ETH)

        _revertIfHealthFactorIsBroken(msg.sender);

        bool success = i_dsc.mint(msg.sender, _amountDscToMint);

        if (!success) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnDsc() external {}

    function liquidate() external {}

    function getHealthFactor() external {}

    /////////////////////////////
    //// Internal Functions  ////
    /////////////////////////////

    function _getAccountInformation(address _user)
        internal
        view
        returns (uint256 _totalDscMinted, uint256 _totalCollateralValueInUsd)
    {
        _totalDscMinted = s_DscMinted[_user];
        _totalCollateralValueInUsd = getAccountCollateralValueInUsd(_user);
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
