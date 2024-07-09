/**
 * Have our invariant aka properties
 * 
 * what our invariant or properties?
 * 
 * 1. The total of DSC should be less than the total value of collateral 
 * 2. Getter view functions should never revert
 */

// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.20;
import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract Handler is Test {

    DSCEngine dsce;
    DecentralizedStableCoin dsc;
    ERC20Mock weth;
    ERC20Mock wbtc;

    constructor(DSCEngine _engine, DecentralizedStableCoin _dsc) {
        dsce = _engine;
        _dsc = dsc;

        address[] memory collateralTokens = dsce.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);
    }

    function depositCollateral (uint256 collateralSeed, uint256 amountCollateral) public {
        uint256 MAX_DEPOSIT_SIZE = type(uint96).max;
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(dsce), amountCollateral);
        dsce.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
    }

    

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateralRedeemed = dsce.getCollateralBalanceOfUser(msg.sender, address(collateral));
        amountCollateral = bound(amountCollateral, 0, maxCollateralRedeemed);

        if(amountCollateral == 0) return ;

        dsce.redeemCollateral(address(collateral), amountCollateral);
    }

    function mintDsc(uint256 amount) public {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(msg.sender);

        uint256 maxDscToMint = (collateralValueInUsd / 2) - totalDscMinted;

        if(maxDscToMint < 0){
            return;
        }

        amount = bound(amount, 0, maxDscToMint);
        if(amount < 0){
            return;
        }

        vm.startPrank(msg.sender);
        dsce.mintDsc(amount);
        vm.stopPrank();
    }

    // Helper Functions
    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock){
        if(collateralSeed % 2 == 0){
            return weth;
        }
        return wbtc;
    }
}