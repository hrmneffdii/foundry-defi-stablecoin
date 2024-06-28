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

contract DSCEngineTest is Script, Test {
    DSCEngine dscengine;
    DecentralizedStableCoin dsc;
    DeployDSC deployer;
    HelperConfig config;
    address wethUsdPriceFeed;
    address weth;
    address wbtc;

    address public USER = makeAddr("USER");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCES = 10 ether;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dscengine, config) = deployer.run();
        (wethUsdPriceFeed,, weth, wbtc,) = config.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCES);
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

        // i initialize the price feed with 1 eth = 3500 usd
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
        ERC20Mock(weth).approve(address(dscengine), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscengine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertWithUnapprovedCollateral() public {
        // because the token collateral address doesn't exist, we can't approve it
        ERC20Mock randomToken = new ERC20Mock("RAN", "RAN", USER, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dscengine.depositCollateral(address(randomToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    /**
     * @notice here, we initialize the deposit token with 10 token of eth, and approve it.
     * if we wanna check the deposite, it will be return 10 eth
     * if we wanna get the usd value, it must be times with price feed of eth/usd
     */
    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscengine), AMOUNT_COLLATERAL);
        dscengine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetInfoAccount() public depositedCollateral {
        ( uint256 actualDscMinted, uint256 actualUsd) = dscengine.getAccountInformation(USER);
        uint256 actualToken = dscengine.getTokenAmountFromUsd(weth, actualUsd );
        console.log(actualDscMinted, actualUsd, actualToken);
        uint256 expectedToken = AMOUNT_COLLATERAL;

        uint256 expectedUsd = dscengine.getValueInUSD(weth, AMOUNT_COLLATERAL);
        uint256 expectedDscMinted = 0;

        assertEq(expectedUsd, actualUsd);
        assertEq(expectedDscMinted, actualDscMinted);
        assertEq(expectedToken, actualToken);
    }    

    ///////////////////////////////////
    ///// Mint Test ///////////////////
    ///////////////////////////////////

    function testMintDsc() public {}
}
