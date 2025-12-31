// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {DeStablecoin} from "../src/DeStablecoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployDSC is Script {
    function run() external returns (DeStablecoin, DSCEngine) {
        HelperConfig helperConfig = new HelperConfig();
        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc, address deployerKey) =
            helperConfig.activeNetworkConfig();

        address[] memory tokenAddresses = [weth, wbtc];
        address[] memory priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed];

        vm.startBroadcast();
        DeStablecoin deStablecoin = new DeStablecoin();
        DSCEngine dscEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(deStablecoin));

        deStablecoin.transferOwnership(address(dscEngine));

        return (deStablecoin, dscEngine);
    }
}
