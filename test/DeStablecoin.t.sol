// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {DeStablecoin} from "../src/DeStablecoin.sol";

contract DeStablecoinTest is Test {
    DeStablecoin public deStablecoin;

    function setUp() public {
        deStablecoin = new DeStablecoin();
    }

    function test_Mint() public {
        vm.prank(owner);
        deStablecoin.mint(address(this), 1000);
        assertEq(deStablecoin.balanceOf(address(this)), 1000);
        assertEq(deStablecoin.totalSupply(), 1000);
    }
}
