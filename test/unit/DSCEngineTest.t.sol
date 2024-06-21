// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Test} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {Script} from "forge-std/Script.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";

contract DSCEngineTest is Script, Test {
    DSCEngine dscengine;
    DecentralizedStableCoin dsc;
    DeployDSC deployer;
    HelperConfig config;
    address wethUsdPriceFeed;
    address weth;

    address public USER = makeAddr("USER");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCES = 10 ether;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dscengine, config) = deployer.run();
        (wethUsdPriceFeed,, weth,,) = config.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCES);
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
}
