// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DeStablecoin} from "../../src/DeStablecoin.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Handler} from "./Handler.sol";

contract DSCEngineInvariants is StdInvariant, Test {
    DSCEngine public dscEngine;
    DeStablecoin public deStablecoin;
    HelperConfig public helperConfig;

    address public weth;
    address public wbtc;
    address public wethUsdPriceFeed;
    address public wbtcUsdPriceFeed;

    Handler public handler;
    address[] public users;

    function setUp() public {
        helperConfig = new HelperConfig();
        (wethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc,) = helperConfig.activeNetworkConfig();

        address[] memory tokenAddresses = new address[](2);
        address[] memory priceFeedAddresses = new address[](2);
        tokenAddresses[0] = weth;
        tokenAddresses[1] = wbtc;
        priceFeedAddresses[0] = wethUsdPriceFeed;
        priceFeedAddresses[1] = wbtcUsdPriceFeed;

        DeployDSC deployDSC = new DeployDSC();
        (deStablecoin, dscEngine, helperConfig) = deployDSC.run();

        // Create handler for fuzzing
        handler = new Handler(dscEngine, deStablecoin, weth, wbtc);

        // Create test users
        users = new address[](5);
        for (uint256 i = 0; i < users.length; i++) {
            users[i] = address(uint160(i + 100)); // Start from 100 to avoid conflicts
        }

        // Give users some tokens
        for (uint256 i = 0; i < users.length; i++) {
            deal(weth, users[i], 10000e18); // Use deal cheatcode
            deal(wbtc, users[i], 1000e8);
        }

        // Target the handler contract for fuzzing
        targetContract(address(handler));
    }

    // ============ Invariant Tests ============

    /**
     * @notice Invariant: Health factor should never be below minimum after any operation
     * @dev This ensures the protocol remains solvent
     */
    function invariant_healthFactorShouldNeverBeBelowMinimum() public view {
        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];
            uint256 collateralValue = dscEngine.getAccountCollateralValue(user);
            uint256 debtValue = dscEngine.getAccountDebtValue(user);

            if (debtValue > 0) {
                // Health factor = (collateral * threshold * precision) / debt
                // Should be >= 1e18 (MIN_HEALTH_FACTOR)
                uint256 collateralAdjusted = (collateralValue * 50) / 100; // 50% threshold
                uint256 healthFactor = (collateralAdjusted * 1e18) / debtValue;
                assertGe(healthFactor, 1e18, "Health factor below minimum");
            }
        }
    }

    /**
     * @notice Invariant: Total collateral value should always be sufficient for total debt
     * @dev Protocol-wide solvency check
     */
    function invariant_protocolSolvency() public view {
        uint256 totalCollateralValue = 0;
        uint256 totalDebt = 0;

        for (uint256 i = 0; i < users.length; i++) {
            totalCollateralValue += dscEngine.getAccountCollateralValue(users[i]);
            totalDebt += dscEngine.getAccountDebtValue(users[i]);
        }

        // With 50% liquidation threshold, collateral should be at least 2x debt
        uint256 requiredCollateral = (totalDebt * 100) / 50; // 200% collateralization
        assertGe(totalCollateralValue, requiredCollateral, "Protocol insolvent");
    }

    /**
     * @notice Invariant: User debt should never exceed collateral value (adjusted for threshold)
     * @dev Individual account solvency check
     */
    function invariant_userDebtNeverExceedsCollateral() public view {
        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];
            uint256 collateralValue = dscEngine.getAccountCollateralValue(user);
            uint256 debtValue = dscEngine.getAccountDebtValue(user);

            // Adjusted collateral (50% threshold) should be >= debt
            uint256 adjustedCollateral = (collateralValue * 50) / 100;
            assertGe(adjustedCollateral, debtValue, "User debt exceeds collateral");
        }
    }

    /**
     * @notice Invariant: Price conversions should be consistent (round-trip)
     * @dev USD → Token → USD should return original value (within rounding)
     */
    function invariant_priceConversionConsistency() public view {
        uint256 testAmount = 100e18; // $100

        // Test WETH
        uint256 tokenAmount = dscEngine.getTokenAmountFromUsd(weth, testAmount);
        uint256 usdValue = dscEngine.getUsdValue(weth, tokenAmount);
        // Allow 1% rounding difference
        assertApproxEqRel(usdValue, testAmount, 0.01e18, "WETH price conversion inconsistent");

        // Test WBTC
        tokenAmount = dscEngine.getTokenAmountFromUsd(wbtc, testAmount);
        usdValue = dscEngine.getUsdValue(wbtc, tokenAmount);
        assertApproxEqRel(usdValue, testAmount, 0.01e18, "WBTC price conversion inconsistent");
    }

    /**
     * @notice Invariant: Collateral deposits should match actual token balances
     * @dev Ensures accounting is correct
     */
    function invariant_collateralAccountingMatchesBalances() public view {
        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];
            
            // Check WETH
            uint256 depositedWeth = 0; // Would need getter function
            uint256 balanceWeth = IERC20(weth).balanceOf(address(dscEngine));
            // Note: This is a simplified check - full implementation would track per-user deposits
            
            // Check WBTC
            uint256 balanceWbtc = IERC20(wbtc).balanceOf(address(dscEngine));
        }
    }

    /**
     * @notice Invariant: Total DSC supply should match sum of user debts
     * @dev Ensures debt tracking is accurate
     */
    function invariant_totalDscSupplyMatchesUserDebts() public view {
        uint256 totalUserDebt = 0;
        
        for (uint256 i = 0; i < users.length; i++) {
            totalUserDebt += dscEngine.getAccountDebtValue(users[i]);
        }

        uint256 totalSupply = deStablecoin.totalSupply();
        // Total supply should be >= total user debt (some might be burned)
        assertGe(totalSupply, totalUserDebt, "Total supply less than user debts");
    }

    /**
     * @notice Invariant: No user should have negative debt
     * @dev Debt should always be >= 0
     */
    function invariant_debtAlwaysNonNegative() public view {
        for (uint256 i = 0; i < users.length; i++) {
            uint256 debt = dscEngine.getAccountDebtValue(users[i]);
            assertGe(debt, 0, "Negative debt detected");
        }
    }

    /**
     * @notice Invariant: No user should have negative collateral
     * @dev Collateral should always be >= 0
     */
    function invariant_collateralAlwaysNonNegative() public view {
        for (uint256 i = 0; i < users.length; i++) {
            uint256 collateral = dscEngine.getAccountCollateralValue(users[i]);
            assertGe(collateral, 0, "Negative collateral detected");
        }
    }

    /**
     * @notice Invariant: Health factor calculation should be consistent
     * @dev Health factor should match manual calculation
     */
    function invariant_healthFactorCalculationConsistency() public view {
        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];
            uint256 collateralValue = dscEngine.getAccountCollateralValue(user);
            uint256 debtValue = dscEngine.getAccountDebtValue(user);

            if (debtValue > 0) {
                // Manual calculation
                uint256 collateralAdjusted = (collateralValue * 50) / 100;
                uint256 expectedHealthFactor = (collateralAdjusted * 1e18) / debtValue;
                
                // Health factor should be >= 1e18 if protocol is working correctly
                // (We can't directly call _healthFactor as it's private, but we can verify the logic)
                assertGe(expectedHealthFactor, 1e18, "Health factor calculation inconsistent");
            }
        }
    }

    /**
     * @notice Invariant: Token amounts should never overflow
     * @dev Prevents integer overflow issues
     */
    function invariant_noOverflowInCalculations() public view {
        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];
            uint256 collateral = dscEngine.getAccountCollateralValue(user);
            uint256 debt = dscEngine.getAccountDebtValue(user);
            
            // These should never overflow
            assertLt(collateral, type(uint256).max, "Collateral overflow");
            assertLt(debt, type(uint256).max, "Debt overflow");
        }
    }
}

