// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DeStablecoin} from "../../src/DeStablecoin.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

contract DSCEngineTest is StdCheats, Test {
    DeStablecoin public deStablecoin;
    DSCEngine public dscEngine;
    HelperConfig public helperConfig;

    address public weth;
    address public wbtc;
    address public wethUsdPriceFeed;
    address public wbtcUsdPriceFeed;
    uint256 public deployerKey;

    uint256 amountCollateral = 10 ether;
    uint256 amountToMint = 100 ether;
    address public user = address(1);

    uint256 public constant STARTING_USER_BALANCE = 10 ether;
    uint256 public constant MIN_HEALTH_FACTOR = 1e18;
    uint256 public constant LIQUIDATION_THRESHOLD = 50;

    // Liquidation
    address public liquidator = makeAddr("liquidator");
    uint256 public collateralToCover = 20 ether;

    function setUp() external {
        DeployDSC deployer = new DeployDSC();
        (deStablecoin, dscEngine, helperConfig) = deployer.run();
        (wethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc, deployerKey) = helperConfig.activeNetworkConfig();
        if (block.chainid == 31_337) {
            vm.deal(user, STARTING_USER_BALANCE);
        }
        ERC20Mock(weth).mint(user, STARTING_USER_BALANCE);
        ERC20Mock(wbtc).mint(user, STARTING_USER_BALANCE);
    }

    // ============ Constructor Tests ============
    address[] tokenAddresses;
    address[] priceFeedAddresses;

    function test_Constructor_RevertIfTokenAddressesAndPriceFeedsLengthMismatch() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(wethUsdPriceFeed);
        priceFeedAddresses.push(wbtcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedsLengthMismatch.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(deStablecoin));
    }

    // ============ Price Feed Tests ============

    function test_GetTokenAmountFromUsd() public view {
        // If we want $100 of WETH @ $2000/WETH, that would be 0.05 WETH
        uint256 expectedWeth = 0.05 ether;
        uint256 amountWeth = dscEngine.getTokenAmountFromUsd(weth, 100 ether);
        assertEq(amountWeth, expectedWeth);
    }

    function test_GetUsdValue() public view {
        uint256 ethAmount = 15e18;
        // 15e18 ETH * $2000/ETH = $30,000e18
        uint256 expectedUsd = 30_000e18;
        uint256 usdValue = dscEngine.getUsdValue(weth, ethAmount);
        assertEq(usdValue, expectedUsd);
    }

    // ============ Health Factor Tests ============

    // function test_HealthFactor_WithNoCollateralAndNoDebt() public {
    //     // Test initial state - no collateral, no debt
    //     uint256 collateralValue = dscEngine.getAccountCollateralValue(address(this));
    //     uint256 debtValue = dscEngine.getAccountDebtValue(address(this));
    //     assertEq(collateralValue, 0);
    //     assertEq(debtValue, 0);
    // }

    // function test_HealthFactor_Calculation_WithCollateralAndDebt() public {
    //     // Setup: Deposit 1 WETH ($2000) and mint $1000 DSC
    //     // Health factor = (collateral * threshold * precision) / debt
    //     // = (2000e18 * 50/100 * 1e18) / 1000e18
    //     // = (1000e18 * 1e18) / 1000e18 = 1e18 (health factor of 1.0)

    //     address user = address(1);
    //     uint256 collateralAmount = 1e18; // 1 WETH
    //     uint256 debtAmount = 1000e18; // $1000 DSC

    //     // Get WETH token and give user some tokens
    //     IERC20 wethToken = IERC20(weth);
    //     vm.startPrank(weth);
    //     // For mock tokens, we can use the mint function if available
    //     // Or transfer from the deployer
    //     vm.stopPrank();

    //     // Calculate expected values
    //     uint256 expectedCollateralValue = 2000e18; // $2000
    //     uint256 expectedHealthFactor = (expectedCollateralValue * 50 / 100 * 1e18) / debtAmount;
    //     // Expected: (2000e18 * 0.5 * 1e18) / 1000e18 = 1e18

    //     // Note: This test verifies the calculation logic
    //     // Full integration test would require actual deposit and mint
    //     assertEq(expectedHealthFactor, 1e18);
    // }

    // function test_HealthFactor_HealthyPosition() public {
    //     // Healthy position: 2x collateral to debt ratio
    //     // Collateral: $4000, Debt: $1000
    //     // Health factor = (4000e18 * 0.5 * 1e18) / 1000e18 = 2e18 (2.0)
    //     uint256 collateralValue = 4000e18;
    //     uint256 debtValue = 1000e18;
    //     uint256 expectedHealthFactor = (collateralValue * 50 / 100 * 1e18) / debtValue;
    //     assertEq(expectedHealthFactor, 2e18);
    // }

    // function test_HealthFactor_UnhealthyPosition() public {
    //     // Unhealthy position: Less than 1x collateral to debt ratio
    //     // Collateral: $1000, Debt: $1000
    //     // Health factor = (1000e18 * 0.5 * 1e18) / 1000e18 = 0.5e18 (0.5)
    //     uint256 collateralValue = 1000e18;
    //     uint256 debtValue = 1000e18;
    //     uint256 expectedHealthFactor = (collateralValue * 50 / 100 * 1e18) / debtValue;
    //     assertEq(expectedHealthFactor, 0.5e18);
    //     // Health factor < 1e18 means position can be liquidated
    //     assertLt(expectedHealthFactor, 1e18);
    // }

    // function test_HealthFactor_AtLiquidationThreshold() public {
    //     // At liquidation threshold: Health factor = 1.0
    //     // Collateral: $2000, Debt: $1000
    //     // Health factor = (2000e18 * 0.5 * 1e18) / 1000e18 = 1e18 (1.0)
    //     uint256 collateralValue = 2000e18;
    //     uint256 debtValue = 1000e18;
    //     uint256 expectedHealthFactor = (collateralValue * 50 / 100 * 1e18) / debtValue;
    //     assertEq(expectedHealthFactor, 1e18);
    // }

    // function test_GetAccountDebtValue_WithNoDebt() public {
    //     uint256 debtValue = dscEngine.getAccountDebtValue(address(this));
    //     assertEq(debtValue, 0);
    // }

    // function test_GetAccountCollateralValue_MultipleTokens() public {
    //     // Test that multiple collateral tokens are summed correctly
    //     // This would require actual deposits, but we can test the logic
    //     uint256 wethValue = 2000e18; // 1 WETH = $2000
    //     uint256 wbtcValue = 100000e18; // 1 WBTC = $100,000
    //     uint256 expectedTotal = wethValue + wbtcValue;
    //     // Note: Actual test would require deposits
    //     assertGt(expectedTotal, wethValue);
    //     assertGt(expectedTotal, wbtcValue);
    // }

    // ============ Revert Tests ============

    // function test_RevertIfTokenAddressesAndPriceFeedsLengthMismatch() public {
    //     vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedsLengthMismatch.selector);
    //     new DSCEngine(tokenAddresses, priceFeedAddresses, address(deStablecoin));
    // }

    // function test_RevertIfTokenNotAllowed() public {
    //     vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
    //     dscEngine.depositCollateral(address(0), 100);
    // }

    // function test_RevertIfTransferFailed() public {
    //     vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
    //     dscEngine.depositCollateral(address(0), 100);
    // }

    // function test_RevertIfHealthFactorIsBroken() public {
    //     vm.expectRevert(DSCEngine.DSCEngine__HealthFactorIsBroken.selector);
    //     dscEngine.depositCollateral(address(0), 100);
    // }

    // function test_RevertIfMintFailed() public {
    //     vm.expectRevert(DSCEngine.DSCEngine__MintFailed.selector);
    //     dscEngine.mintDsc(100);
    // }

    // function test_RevertIfBurnFailed() public {
    //     vm.expectRevert(DSCEngine.DSCEngine__BurnFailed.selector);
    //     dscEngine.burnDsc(100);
    // }

    // function test_RevertIfLiquidationFailed() public {
    //     vm.expectRevert(DSCEngine.DSCEngine__LiquidationFailed.selector);
    //     dscEngine.liquidate(address(0), address(0), 100, 100);
    // }

    // function test_RevertIfRedeemFailed() public {
    //     vm.expectRevert(DSCEngine.DSCEngine__RedeemFailed.selector);
    //     dscEngine.redeemCollateral(address(0), 100);
    // }

    // function test_RevertIfRedeemCollateralForDscFailed() public {
    //     vm.expectRevert(DSCEngine.DSCEngine__RedeemCollateralForDscFailed.selector);
    //     dscEngine.redeemCollateralForDsc(100, 100);
    // }

    // function test_RevertIfDepositCollateralAndMintDscFailed() public {
    //     vm.expectRevert(DSCEngine.DSCEngine__DepositCollateralAndMintDscFailed.selector);
    //     dscEngine.depositCollateralAndMintDsc(100, 100);
    // }
}
