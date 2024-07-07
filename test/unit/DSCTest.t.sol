// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Test} from "forge-std/Test.sol";
import {Script} from "forge-std/Script.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {console} from "forge-std/console.sol";

contract DSCTest is Test, Script {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    address public OWNER = makeAddr('OWNER');
    address ownerBefore = 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512;
    address public USER = makeAddr('USER');

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, , ) = deployer.run();

        vm.prank(ownerBefore);
        dsc.transferOwnership(address(OWNER));
    }

    function testConstructor() public {
        new DecentralizedStableCoin();
    }

    function testCek() public view {
        console.log(dsc.owner());
    }

    function testMintingRevertNotZeroAddress() public {
        vm.startPrank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(DecentralizedStableCoin.DecentralizedStableCoin__NotZeroAddress.selector));
        dsc.mint(address(0), 10);
        vm.stopPrank();
    }

    function testMintingRevertMustBeMoreThanZero() public {
        vm.startPrank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(DecentralizedStableCoin.DecentralizedStableCoin__MustBeMoreThanZero.selector));
        dsc.mint(address(OWNER), 0);
        vm.stopPrank();
    }

    function testBurnRevertMustBeMoreThanZero() public {
        vm.startPrank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(DecentralizedStableCoin.DecentralizedStableCoin__MustBeMoreThanZero.selector));
        dsc.burn(0);
        vm.stopPrank();        
    }

    function testBurnRevertDontHaveBalance() public {
        vm.startPrank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(DecentralizedStableCoin.DecentralizedStableCoin__BurnAmountExceedsBalance.selector));
        dsc.burn(10);
        vm.stopPrank();
    }
}