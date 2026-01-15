// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {DeStablecoin} from "../../src/DeStablecoin.sol";

contract DeStablecoinTest is Test {
    DeStablecoin public deStablecoin;

    function setUp() public {
        deStablecoin = new DeStablecoin();
    }

    address public user = makeAddr("user");

    function test_MustMintMoreThanZero() public {
        vm.startPrank(deStablecoin.owner());
        vm.expectRevert(DeStablecoin.DeStablecoin__AmountMustBeGreaterThanZero.selector);
        deStablecoin.mint(user, 0);
    }

    function test_MustBurnMoreThanZero() public {
        vm.startPrank(deStablecoin.owner());
        deStablecoin.mint(user, 100);
        vm.expectRevert(DeStablecoin.DeStablecoin__AmountMustBeGreaterThanZero.selector);
        deStablecoin.burn(0);
        vm.stopPrank();
    }

    function test_CannotBurnMoreThanBalance() public {
        vm.startPrank(deStablecoin.owner());
        deStablecoin.mint(user, 100);
        vm.expectRevert();
        deStablecoin.burn(101);
        vm.stopPrank();
    }

    function test_CantMintToZeroAddress() public {
        vm.startPrank(deStablecoin.owner());
        vm.expectRevert(DeStablecoin.DeStablecoin__InvalidAddress.selector);
        deStablecoin.mint(address(0), 100);
        vm.stopPrank();
    }
}
