// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DeStablecoin} from "../../src/DeStablecoin.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/**
 * @title Handler
 * @notice Handler contract for invariant fuzzing - performs random operations
 * @dev This contract is used by Foundry's invariant testing to perform random operations
 */
contract Handler is Test {
    DSCEngine public dscEngine;
    DeStablecoin public deStablecoin;
    address public weth;
    address public wbtc;

    constructor(DSCEngine _dscEngine, DeStablecoin _deStablecoin, address _weth, address _wbtc) {
        dscEngine = _dscEngine;
        deStablecoin = _deStablecoin;
        weth = _weth;
        wbtc = _wbtc;
    }

    function depositCollateralWeth(uint256 amount) public {
        amount = bound(amount, 1e18, 1000e18);
        // Contract needs to have tokens to transfer to user (based on current implementation)
        uint256 contractBalance = IERC20(weth).balanceOf(address(dscEngine));
        if (contractBalance < amount) {
            // Give contract tokens if needed
            deal(weth, address(dscEngine), amount);
        }

        vm.startPrank(msg.sender);
        try dscEngine.depositCollateral(weth, amount) {} catch {}
        vm.stopPrank();
    }

    function depositCollateralWbtc(uint256 amount) public {
        amount = bound(amount, 1e8, 100e8);
        uint256 contractBalance = IERC20(wbtc).balanceOf(address(dscEngine));
        if (contractBalance < amount) {
            deal(wbtc, address(dscEngine), amount);
        }

        vm.startPrank(msg.sender);
        try dscEngine.depositCollateral(wbtc, amount) {} catch {}
        vm.stopPrank();
    }

    function mintDsc(uint256 amount) public {
        amount = bound(amount, 1e18, 10000e18);
        vm.startPrank(msg.sender);
        try dscEngine.mintDsc(amount) {} catch {}
        vm.stopPrank();
    }

    function redeemCollateralWeth(uint256 amount) public {
        vm.startPrank(msg.sender);
        try dscEngine.redeemCollateral(weth, amount) {} catch {}
        vm.stopPrank();
    }

    function redeemCollateralWbtc(uint256 amount) public {
        vm.startPrank(msg.sender);
        try dscEngine.redeemCollateral(wbtc, amount) {} catch {}
        vm.stopPrank();
    }

    function burnDsc(uint256 amount) public {
        uint256 balance = deStablecoin.balanceOf(msg.sender);
        if (balance < amount) return;

        vm.startPrank(msg.sender);
        IERC20(address(deStablecoin)).approve(address(dscEngine), amount);
        try dscEngine.burnDsc(amount) {} catch {}
        vm.stopPrank();
    }
}

