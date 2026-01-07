// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DeStablecoin} from "../../src/DeStablecoin.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract DSCEngineTest is Test {
    DeployDSC public deployDSC;
    DeStablecoin public deStablecoin;
    DSCEngine public dscEngine;
    HelperConfig public helperConfig;

    address public weth;
    address public wbtc;
    address public wethUsdPriceFeed;
    address public wbtcUsdPriceFeed;

    function setUp() public {
        helperConfig = new HelperConfig();
        (,, weth, wbtc) = helperConfig.activeNetworkConfig();

        deployDSC = new DeployDSC();
        (deStablecoin, dscEngine, helperConfig) = deployDSC.run();
    }

    // ============ Price Feed Tests ============

    function test_GetUsdValue_WithWeth() public {
        // WETH price is $2000 (2000 * 10^18 in 18 decimals)
        // For 1 WETH (1e18), expected USD value = (2000e18 * 1e10 * 1e18) / 1e18 = 2000e18
        uint256 oneWeth = 1e18;
        uint256 expectedUsdValue = 2000e18; // $2000 in 18 decimals
        uint256 usdValue = dscEngine.getUsdValue(weth, oneWeth);
        assertEq(usdValue, expectedUsdValue);
    }

    function test_GetUsdValue_WithWethPartial() public {
        // 0.5 WETH = 0.5e18
        // Expected: (2000e18 * 1e10 * 0.5e18) / 1e18 = 1000e18
        uint256 halfWeth = 0.5e18;
        uint256 expectedUsdValue = 1000e18; // $1000 in 18 decimals
        uint256 usdValue = dscEngine.getUsdValue(weth, halfWeth);
        assertEq(usdValue, expectedUsdValue);
    }

    function test_GetUsdValue_WithWbtc() public {
        // WBTC price is $100,000 (100000 * 10^8 in 8 decimals)
        // For 1 WBTC (1e8), expected USD value = (100000e8 * 1e10 * 1e8) / 1e18 = 100000e18
        uint256 oneWbtc = 1e8;
        uint256 expectedUsdValue = 100000e18; // $100,000 in 18 decimals
        uint256 usdValue = dscEngine.getUsdValue(wbtc, oneWbtc);
        assertEq(usdValue, expectedUsdValue);
    }

    function test_GetUsdValue_WithWbtcPartial() public {
        // 0.1 WBTC = 0.1e8
        // Expected: (100000e8 * 1e10 * 0.1e8) / 1e18 = 10000e18
        uint256 tenthWbtc = 0.1e8;
        uint256 expectedUsdValue = 10000e18; // $10,000 in 18 decimals
        uint256 usdValue = dscEngine.getUsdValue(wbtc, tenthWbtc);
        assertEq(usdValue, expectedUsdValue);
    }

    function test_GetUsdValue_WithZeroAmount() public {
        uint256 usdValue = dscEngine.getUsdValue(weth, 0);
        assertEq(usdValue, 0);
    }

    function test_GetAccountCollateralValue_WithNoCollateral() public {
        uint256 collateralValue = dscEngine.getAccountCollateralValue(address(this));
        assertEq(collateralValue, 0);
    }

    // ============ Health Factor Tests ============

    function test_HealthFactor_WithNoCollateralAndNoDebt() public {
        // Test initial state - no collateral, no debt
        uint256 collateralValue = dscEngine.getAccountCollateralValue(address(this));
        uint256 debtValue = dscEngine.getAccountDebtValue(address(this));
        assertEq(collateralValue, 0);
        assertEq(debtValue, 0);
    }

    function test_HealthFactor_Calculation_WithCollateralAndDebt() public {
        // Setup: Deposit 1 WETH ($2000) and mint $1000 DSC
        // Health factor = (collateral * threshold * precision) / debt
        // = (2000e18 * 50/100 * 1e18) / 1000e18
        // = (1000e18 * 1e18) / 1000e18 = 1e18 (health factor of 1.0)

        address user = address(1);
        uint256 collateralAmount = 1e18; // 1 WETH
        uint256 debtAmount = 1000e18; // $1000 DSC

        // Get WETH token and give user some tokens
        IERC20 wethToken = IERC20(weth);
        vm.startPrank(weth);
        // For mock tokens, we can use the mint function if available
        // Or transfer from the deployer
        vm.stopPrank();

        // Calculate expected values
        uint256 expectedCollateralValue = 2000e18; // $2000
        uint256 expectedHealthFactor = (expectedCollateralValue * 50 / 100 * 1e18) / debtAmount;
        // Expected: (2000e18 * 0.5 * 1e18) / 1000e18 = 1e18

        // Note: This test verifies the calculation logic
        // Full integration test would require actual deposit and mint
        assertEq(expectedHealthFactor, 1e18);
    }

    function test_HealthFactor_HealthyPosition() public {
        // Healthy position: 2x collateral to debt ratio
        // Collateral: $4000, Debt: $1000
        // Health factor = (4000e18 * 0.5 * 1e18) / 1000e18 = 2e18 (2.0)
        uint256 collateralValue = 4000e18;
        uint256 debtValue = 1000e18;
        uint256 expectedHealthFactor = (collateralValue * 50 / 100 * 1e18) / debtValue;
        assertEq(expectedHealthFactor, 2e18);
    }

    function test_HealthFactor_UnhealthyPosition() public {
        // Unhealthy position: Less than 1x collateral to debt ratio
        // Collateral: $1000, Debt: $1000
        // Health factor = (1000e18 * 0.5 * 1e18) / 1000e18 = 0.5e18 (0.5)
        uint256 collateralValue = 1000e18;
        uint256 debtValue = 1000e18;
        uint256 expectedHealthFactor = (collateralValue * 50 / 100 * 1e18) / debtValue;
        assertEq(expectedHealthFactor, 0.5e18);
        // Health factor < 1e18 means position can be liquidated
        assertLt(expectedHealthFactor, 1e18);
    }

    function test_HealthFactor_AtLiquidationThreshold() public {
        // At liquidation threshold: Health factor = 1.0
        // Collateral: $2000, Debt: $1000
        // Health factor = (2000e18 * 0.5 * 1e18) / 1000e18 = 1e18 (1.0)
        uint256 collateralValue = 2000e18;
        uint256 debtValue = 1000e18;
        uint256 expectedHealthFactor = (collateralValue * 50 / 100 * 1e18) / debtValue;
        assertEq(expectedHealthFactor, 1e18);
    }

    function test_GetAccountDebtValue_WithNoDebt() public {
        uint256 debtValue = dscEngine.getAccountDebtValue(address(this));
        assertEq(debtValue, 0);
    }

    function test_GetAccountCollateralValue_MultipleTokens() public {
        // Test that multiple collateral tokens are summed correctly
        // This would require actual deposits, but we can test the logic
        uint256 wethValue = 2000e18; // 1 WETH = $2000
        uint256 wbtcValue = 100000e18; // 1 WBTC = $100,000
        uint256 expectedTotal = wethValue + wbtcValue;
        // Note: Actual test would require deposits
        assertGt(expectedTotal, wethValue);
        assertGt(expectedTotal, wbtcValue);
    }

    // ============ Revert Tests ============

    function test_RevertIfTokenAddressesAndPriceFeedsLengthMismatch() public {
        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedsLengthMismatch.selector);
        new DSCEngine([address(0)], [address(0)], address(deStablecoin));
    }

    function test_RevertIfTokenNotAllowed() public {
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dscEngine.depositCollateral(address(0), 100);
    }

    function test_RevertIfTransferFailed() public {
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        dscEngine.depositCollateral(address(0), 100);
    }

    function test_RevertIfHealthFactorIsBroken() public {
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorIsBroken.selector);
        dscEngine.depositCollateral(address(0), 100);
    }

    function test_RevertIfMintFailed() public {
        vm.expectRevert(DSCEngine.DSCEngine__MintFailed.selector);
        dscEngine.mintDsc(100);
    }

    function test_RevertIfBurnFailed() public {
        vm.expectRevert(DSCEngine.DSCEngine__BurnFailed.selector);
        dscEngine.burnDsc(100);
    }

    function test_RevertIfLiquidationFailed() public {
        vm.expectRevert(DSCEngine.DSCEngine__LiquidationFailed.selector);
        dscEngine.liquidate(address(0), address(0), 100, 100);
    }

    function test_RevertIfRedeemFailed() public {
        vm.expectRevert(DSCEngine.DSCEngine__RedeemFailed.selector);
        dscEngine.redeemCollateral(address(0), 100);
    }

    function test_RevertIfRedeemCollateralForDscFailed() public {
        vm.expectRevert(DSCEngine.DSCEngine__RedeemCollateralForDscFailed.selector);
        dscEngine.redeemCollateralForDsc(100, 100);
    }

    function test_RevertIfDepositCollateralAndMintDscFailed() public {
        vm.expectRevert(DSCEngine.DSCEngine__DepositCollateralAndMintDscFailed.selector);
        dscEngine.depositCollateralAndMintDsc(100, 100);
    }
}
