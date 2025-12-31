// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {DeStablecoin} from "../src/DeStablecoin.sol";

contract DeStablecoinScript is Script {
    DeStablecoin public deStablecoin;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        deStablecoin = new DeStablecoin();

        vm.stopBroadcast();
    }
}
