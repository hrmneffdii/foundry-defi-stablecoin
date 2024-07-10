// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.20;

import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import { MockV3Aggregator } from "../mocks/MockV3Aggregator.sol";
import {Test, console} from "forge-std/Test.sol";

contract Handler is Test {

    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    ERC20Mock weth;
    ERC20Mock wbtc;
    MockV3Aggregator ethUsdPriceFeed;
    MockV3Aggregator btcUsdPriceFeed;

    mapping(address => uint256) senderWHoDepositedInUsd;

    constructor(DecentralizedStableCoin _dsc, DSCEngine _dsce){
        dsce = _dsce;
        dsc = _dsc;

        address[] memory collateralTokens = dsce.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);

        ethUsdPriceFeed = MockV3Aggregator(dsce.getCollateralTokenPriceFeed(address(weth)));
        btcUsdPriceFeed = MockV3Aggregator(dsce.getCollateralTokenPriceFeed(address(wbtc)));
    }

    function depositCollateral(uint256 collateralSeed, uint24 amount) external {
        ERC20Mock collateral = _getCollateralToken(collateralSeed);

        if(amount == 0) return;

        vm.startPrank(msg.sender);
        ERC20Mock(collateral).mint(msg.sender, amount);
        ERC20Mock(collateral).approve(address(dsce), amount);
        dsce.depositCollateral(address(collateral), amount);
        vm.stopPrank();

        senderWHoDepositedInUsd[msg.sender] += dsce.getValueInUSD(address(collateral), amount);
    }

    function mintDsc(uint96 amount) external {

        if(amount >= senderWHoDepositedInUsd[msg.sender]){
            return ;
        }
        
        if(amount == 0){
            return;
        }

        vm.startPrank(msg.sender);
        dsce.mintDsc(amount);
        vm.stopPrank();
    }

    function redeemCollateral(uint256 collateralSeed, uint24 amount) external {
        vm.startPrank(msg.sender);

        ERC20Mock collateral = _getCollateralToken(collateralSeed);
        (uint256 _totalDscMinted, uint256 _totalCollateralValueInUsd) = dsce.getAccountInformation(msg.sender);
        uint256 usdToRedeem = dsce.getValueInUSD(address(collateral), amount);

        if(usdToRedeem == 0) return ;
        if(_totalCollateralValueInUsd < usdToRedeem) return ;

        uint256 differential = _totalCollateralValueInUsd - usdToRedeem;

        if(differential * 2 < _totalDscMinted) return ;

        dsce.redeemCollateral(address(collateral), amount);
        vm.stopPrank();
    }

    function _getCollateralToken(uint256 seed) internal view returns (ERC20Mock) {
        if(seed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }
}