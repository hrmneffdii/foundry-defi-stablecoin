// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Test} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {Script} from "forge-std/Script.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {console} from "forge-std/console.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import {MockFailedTransferFrom} from "../mocks/MockFailedTransferFrom.sol";
import {MockFailedMint} from "../mocks/MockFailedMint.sol";

contract DSCEngineTest is Script, Test {
    DSCEngine dscengine;
    DecentralizedStableCoin dsc;
    DeployDSC deployer;
    HelperConfig config;
    address wethUsdPriceFeed;
    address weth;
    address wbtc;

    address public USER = makeAddr("USER");
    uint256 public constant AMOUNT_COLLATERAL_ETH = 10 ; // means 10 ETH 
    uint256 public constant AMOUNT_TO_MINT_DSC = 10_000 ; // means 10000 DSC
    uint256 public constant AMOUNT_TO_MINT_REVERT_DSC = 40_000; // from 10 ETH * 3500 USD/ETH
    uint256 public constant STARTING_ERC20_BALANCES_WETH = 1000 ; // for minting weth in setUp (total supply)

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dscengine, config) = deployer.run();
        (wethUsdPriceFeed,, weth, wbtc,) = config.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCES_WETH);
    }

    /////////////////////////////
    ///// Constructor Tests /////
    /////////////////////////////
    address[] public tokenAddresess;
    address[] public priceFeedAddresses;

    function testRevertIfTokenLengthDoesntMatch() public {
        tokenAddresess.push(weth);
        tokenAddresess.push(wbtc);
        priceFeedAddresses.push(wethUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAndPriceFeedMustBeSameLength.selector);
        new DSCEngine(tokenAddresess,priceFeedAddresses , address(dsc));
    }

    ///////////////////////
    ///// Price Tests /////
    ///////////////////////

    function testUsdGetValue() public view {
        uint256 ethAmount = 20;
        uint256 expected = 70000;
        uint256 actualUsd = dscengine.getValueInUSD(weth, ethAmount);

        assertEq(expected, actualUsd);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 3500;
        uint256 actualAmount = dscengine.getTokenAmountFromUsd(weth, usdAmount);
        uint256 expected = 1;

        assertEq(expected, actualAmount);
    }

    ///////////////////////////////////
    ///// DepositCollateral Tests /////
    ///////////////////////////////////

    function testRevertIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscengine), AMOUNT_COLLATERAL_ETH);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscengine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertWithUnapprovedCollateral() public {
        // because the token collateral address doesn't exist, we can't approve it
        ERC20Mock randomToken = new ERC20Mock("RAN", "RAN", USER, AMOUNT_COLLATERAL_ETH);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dscengine.depositCollateral(address(randomToken), AMOUNT_COLLATERAL_ETH);
        vm.stopPrank();
    }

    function testDepositTransferFailed() public {
        address owner = msg.sender;

        vm.startPrank(owner);
        MockFailedTransferFrom mockDsc = new MockFailedTransferFrom();

        tokenAddresess = [address(mockDsc)];
        priceFeedAddresses = [wethUsdPriceFeed];

        DSCEngine mockDsce = new DSCEngine(tokenAddresess, priceFeedAddresses, address(mockDsc));
        mockDsc.mint(USER, AMOUNT_COLLATERAL_ETH);
        mockDsc.transferOwnership(address(mockDsce));
        vm.stopPrank();

        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(mockDsce), AMOUNT_COLLATERAL_ETH);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__TransferFailed.selector));
        mockDsce.depositCollateral(address(mockDsc), AMOUNT_COLLATERAL_ETH);
        vm.stopPrank();
    }


    /**
     * @notice here, we initialize the deposit token with 10 token of eth, and approve it.
     * if we wanna check the deposite, it will be return 10 eth
     * if we wanna get the usd value, it must be times with price feed of eth/usd
     */
    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscengine), AMOUNT_COLLATERAL_ETH);
        dscengine.depositCollateral(weth, AMOUNT_COLLATERAL_ETH); // we deposited 10 ETH -> 35_000 USD
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetInfoAccount() public depositedCollateral {
        ( uint256 actualDscMinted, uint256 actualUsd) = dscengine.getAccountInformation(USER);

        uint256 expectedUsd = dscengine.getValueInUSD(weth, AMOUNT_COLLATERAL_ETH);
        uint256 expectedDscMinted = 0;

        assertEq(expectedUsd, actualUsd);
        assertEq(expectedDscMinted, actualDscMinted);
    }    

    function testCanDepositCollateralWithoutMinting() public depositedCollateral {
        uint256 balanceActual = dsc.balanceOf(USER);
        uint256 balanceExpected = 0;

        assertEq(balanceActual, balanceExpected);
    }

    ///////////////////////////////////
    ///// Minting Tests ///////////////
    ///////////////////////////////////

    function testMintFailed() public {
        address owner = msg.sender;
        
        vm.startPrank(owner);
        MockFailedMint mockDsc = new MockFailedMint();
        tokenAddresess = [weth];
        priceFeedAddresses = [wethUsdPriceFeed];

        DSCEngine mockDsce = new DSCEngine(tokenAddresess, priceFeedAddresses, address(mockDsc));
        mockDsc.transferOwnership(address(mockDsce));

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCES_WETH);
        vm.stopPrank();

        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(mockDsce), AMOUNT_COLLATERAL_ETH);
        mockDsce.depositCollateral(weth, AMOUNT_COLLATERAL_ETH);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__MintFailed.selector));
        mockDsce.mintDsc(AMOUNT_TO_MINT_DSC);
        vm.stopPrank();
    }


     /**
     * @notice we expect that the process won't revert because the rule minting accepted
     * that is the collateral must be overcollateralized
     * example collateral 35000 (actual collateral usd) / 10000 dsc will be minted -> 3,5 (overcollateralized) 
     */
    function testMintingDscAfterDeposit() public depositedCollateral {
        vm.startPrank(USER);
        dscengine.mintDsc(AMOUNT_TO_MINT_DSC); 
        vm.stopPrank();

        uint256 balanceActual = dsc.balanceOf(USER);
        uint256 balanceExpected = AMOUNT_TO_MINT_DSC; // 100 DSC or 100 USD

        assertEq(balanceActual, balanceExpected);
    }

   /**
     * @notice we expect that the process will revert because the rule minting rejected
     * example collateral 35000 (actual collateral) / 40000 dsc will be minted ->  under 1, undercollateralized
     */
    function testMintingDscAfterDepositAndRevert() public depositedCollateral {
        vm.startPrank(USER);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__HealthFactorIsBroken.selector, address(USER)));
        dscengine.mintDsc(AMOUNT_TO_MINT_REVERT_DSC);
        vm.stopPrank();
    }

    //////////////////////////////////////////
    ///// Deposited collateral and Mint dsc //
    //////////////////////////////////////////

    /**
     * this modifier act for depositing and then keep overcollatoralized to avoid revert 
     * we know that the revert is appear when the collateral under 200% from dsc
     * we have 10 eth -> 35_000 USD
     */
    modifier depositedCollateralAndMintedDsc() {
        vm.startPrank(USER);
        // -> 10 ETH for borrowing collateral
        ERC20Mock(weth).approve(address(dscengine), AMOUNT_COLLATERAL_ETH); 
        // -> 10 ETH for collateral deposited and 1000 for minting DSC
        dscengine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL_ETH, AMOUNT_TO_MINT_DSC); 
        vm.stopPrank();
        _;
    }

    function testCanMintWithDepositedCollateral() public depositedCollateralAndMintedDsc {
        ( uint256 actualDscMinted, uint256 actualUsdCollateral) = dscengine.getAccountInformation(USER);
        
        uint256 expectedDscMinted = AMOUNT_TO_MINT_DSC;
        uint256 expectedUsdCollateral = 35_000; // 10 ETH * 3500 USD/ETH -> 35000

        assertEq(actualDscMinted, expectedDscMinted);
        assertEq(actualUsdCollateral, expectedUsdCollateral);
    }

    function testCanMintWithDepositedCollateralandRevert() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscengine), AMOUNT_COLLATERAL_ETH); // -> 10 ETH for borrowing collateral
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__HealthFactorIsBroken.selector, address(USER)));
        dscengine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL_ETH, AMOUNT_TO_MINT_REVERT_DSC); // -> 10 ETH for collateral deposited and 1000 for minting DSC
        vm.stopPrank();
    }

    //////////////////////
    ///// Burn DSC ///////
    //////////////////////

    function testBurnRevertMoreThanZero() depositedCollateralAndMintedDsc public {
        uint256 dscToBurn = 100;

        vm.startPrank(USER);
        dsc.approve(address(dscengine), dscToBurn);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__NeedsMoreThanZero.selector));
        dscengine.burnDsc(0);
        vm.stopPrank();
    }

    function testBurnRevertWhenHaveNotDsc() depositedCollateral public {
        vm.startPrank(USER);
        vm.expectRevert();
        dscengine.burnDsc(1);
        vm.stopPrank();
    }

    function testCanBurnDsc() public depositedCollateralAndMintedDsc {
        uint256 dscToBurn = 100;
        
        vm.startPrank(USER);
        dsc.approve(address(dscengine), dscToBurn);
        dscengine.burnDsc(dscToBurn);
        vm.stopPrank();

        uint256 expectedDsc = AMOUNT_TO_MINT_DSC - dscToBurn;
        uint256 actualDsc = dsc.balanceOf(USER);

        assertEq(expectedDsc, actualDsc);
    }

    ////////////////////////////////////
    ///// Redeem Collateral test ///////
    ////////////////////////////////////

    function testCanRedeemCollateral() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);
        vm.expectRevert();
        dscengine.redeemCollateral(weth, 0);
        vm.stopPrank();

        (, uint256 startBalance) = dscengine.getAccountInformation(USER);

        vm.startPrank(USER);
        dscengine.redeemCollateral(weth, 1);
        vm.stopPrank();

        (, uint256 lastBalance) = dscengine.getAccountInformation(USER);

        assertEq(startBalance - 3500, lastBalance);
    }

    function testCanRedeemCollateralAndBurnDsc() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);
        vm.expectRevert();
        dscengine.redeemCollateralForDsc(weth, 1, 0);
        vm.stopPrank();

        (, uint256 startBalance) = dscengine.getAccountInformation(USER);

        vm.startPrank(USER);
        dsc.approve(address(dscengine), 100);
        dscengine.redeemCollateralForDsc(weth, 1, 100); // we use 1 eth, equal to 3500 USD 
        vm.stopPrank();

        (, uint256 lastBalance) = dscengine.getAccountInformation(USER);

        assertEq(startBalance - 3500, lastBalance);
    }

    ////////////////////////////////
    ///// liquidation test  ////////
    ////////////////////////////////

    function testLiquidationRevertNeedMoreThanZero() public depositedCollateralAndMintedDsc {
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__NeedsMoreThanZero.selector));
        dscengine.liquidate(weth, USER, 0);
    }

    function testLiquidationRevertIfHealthFactorOk() public depositedCollateralAndMintedDsc {
        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(2000e8);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__HealthFactorOk.selector));
        dscengine.liquidate(weth, USER, 1);
    }

    function testLiquidateSucsess() public depositedCollateralAndMintedDsc {
        uint256 usdForLiquidation = 5000;
        (uint256 dscMintedearly, ) = dscengine.getAccountInformation(USER);

        vm.startPrank(USER);
        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(1500e8);
        dsc.approve(address(dscengine), usdForLiquidation);
        dscengine.liquidate(weth, USER, usdForLiquidation);
        vm.stopPrank();

        (uint256 dscMintedeAkhir, uint256 actualUsdAkhir) = dscengine.getAccountInformation(USER);
        
        assertEq(dscMintedearly - usdForLiquidation, dscMintedeAkhir);
        assertEq(actualUsdAkhir, (15000 - 5000) + (5000/10));
    }

    ////////////////////////////////////
    ///// public function test   ///////
    ////////////////////////////////////

    function testgetAccountCollateralValueInUsd() public depositedCollateralAndMintedDsc {
        uint256 actualCollateral = dscengine.getAccountCollateralValueInUsd(USER);
        uint256 expectedCollateral = AMOUNT_COLLATERAL_ETH * 3500;

        assertEq(actualCollateral, expectedCollateral);
    }

    function testGetHealthFactor() public depositedCollateralAndMintedDsc {
        uint256 actualHealthFactor = dscengine.getHealthFactor(USER);
        uint256 expectedHealthFactor = (AMOUNT_COLLATERAL_ETH * 3500 * 1e18) / (AMOUNT_TO_MINT_DSC * 2) ;

        assertEq(actualHealthFactor, expectedHealthFactor);
    }

    function testGetHealthFactorWhenDscMintedZero() public depositedCollateral {
        uint256 actualHealthFactor = dscengine.getHealthFactor(USER);
        uint256 expectedHealthFactor = type(uint256).max;

        assertEq(actualHealthFactor, expectedHealthFactor);        
    }

    function testGetAccountCollateralValueInUsd() public depositedCollateral {
        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(1000e8);

        uint256 actualUsd = dscengine.getAccountCollateralValueInUsd(USER);
        uint256 expectedUsd = AMOUNT_COLLATERAL_ETH * 1000;

        assertEq(actualUsd, expectedUsd);
    }
    
}
