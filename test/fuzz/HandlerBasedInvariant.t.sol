// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {Handler} from "./Handler.sol";

contract HandlerBasedInvariant is StdInvariant, Test{

    DSCEngine dsce;
    DecentralizedStableCoin dsc;
    HelperConfig helperConfig;
    DeployDSC deployer;
    address weth;
    address wbtc;
    address public ethUsdPriceFeed;
    address public btcUsdPriceFeed;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, dsce, helperConfig) = deployer.run();
        (ethUsdPriceFeed,btcUsdPriceFeed,weth,wbtc,) = helperConfig.activeNetworkConfig();
        Handler handler = new Handler(dsc, dsce);
        targetContract(address(handler));
    }

     function invariant_protocolHandlerBasedInvariants() public view {
        uint256 totalSupply = dsc.totalSupply();
        uint256 wethDeposted = ERC20Mock(weth).balanceOf(address(dsce));
        uint256 wbtcDeposited = ERC20Mock(wbtc).balanceOf(address(dsce));

        uint256 wethValue = dsce.getValueInUSD(weth, wethDeposted);
        uint256 wbtcValue = dsce.getValueInUSD(wbtc, wbtcDeposited);

        console.log("wethValue: %s", wethValue);
        console.log("wbtcValue: %s", wbtcValue);
        console.log("total supply: %s", totalSupply);

        assert(wethValue + wbtcValue >= totalSupply);
    }
 
}