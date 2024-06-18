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

    ///////////////////
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

    ///////////////////////////////
    //// State Variables      /////
    ///////////////////////////////

    mapping(address token => address priceFeed) private s_priceFeeds; // token to price feed
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;

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

        emit  CollateralDeposited(msg.sender, _tokenCollateralAddress, _amountCollateral);

        bool success = IERC20(_tokenCollateralAddress).transferFrom(msg.sender, address(this), _amountCollateral); 

        if(!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function redeemCollateralForDsc() external {}

    function redeemCollateral() external {}

    function mintDsc() external {}

    function burnDsc() external {}

    function liquidate() external {}

    function getHealthFactor() external {}
}
