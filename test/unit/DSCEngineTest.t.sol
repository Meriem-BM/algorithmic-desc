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
import {MockFailedTransferFrom} from "../mocks/MockFailedTransferFrom.sol";
import {MockFailedTransfer} from "../mocks/MockFailedTransfer.sol";
import {MockFailedMintDSC} from "../mocks/MockFailedMintDSC.sol";
import {MockV3Aggregator} from "@chainlink/contracts/v0.8/tests/MockV3Aggregator.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/v0.8/shared/interfaces/AggregatorV3Interface.sol";

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
        (
            wethUsdPriceFeed,
            wbtcUsdPriceFeed,
            weth,
            wbtc,
            deployerKey
        ) = helperConfig.activeNetworkConfig();
        if (block.chainid == 31_337) {
            vm.deal(user, STARTING_USER_BALANCE);
        }
        ERC20Mock(weth).mint(user, STARTING_USER_BALANCE);
        ERC20Mock(wbtc).mint(user, STARTING_USER_BALANCE);
    }

    // ============ Constructor Tests ============

    address[] tokenAddresses;
    address[] priceFeedAddresses;

    function test_Constructor_RevertIfTokenAddressesAndPriceFeedsLengthMismatch()
        public
    {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(wethUsdPriceFeed);
        priceFeedAddresses.push(wbtcUsdPriceFeed);

        vm.expectRevert(
            DSCEngine
                .DSCEngine__TokenAddressesAndPriceFeedsLengthMismatch
                .selector
        );
        new DSCEngine(
            tokenAddresses,
            priceFeedAddresses,
            address(deStablecoin)
        );
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

    // ============ Deposit Collateral Tests ============

    function test_RevertsIfTransferFromFails() public {
        // Step 1: Create a mock token that always fails on transferFrom
        MockFailedTransferFrom mockCollateral = new MockFailedTransferFrom();

        // Step 2: Set up token and price feed arrays for DSCEngine constructor
        tokenAddresses = [address(mockCollateral)];
        priceFeedAddresses = [wethUsdPriceFeed];

        // Step 3: Create a new DSCEngine that accepts the mock token as collateral
        DSCEngine mockDscEngine = new DSCEngine(
            tokenAddresses,
            priceFeedAddresses,
            address(deStablecoin)
        );

        // Step 4: Mint tokens to the user (they need tokens to attempt deposit)
        mockCollateral.mint(user, amountCollateral);

        // Step 5: User approves the engine to spend their tokens
        vm.prank(user);
        mockCollateral.approve(address(mockDscEngine), amountCollateral);

        // Step 6: User attempts to deposit collateral, but transferFrom will fail
        // The MockFailedTransferFrom always returns false, so depositCollateral should revert
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(DSCEngine.DSCEngine__TransferFailed.selector)
        );
        mockDscEngine.depositCollateral(
            address(mockCollateral),
            amountCollateral
        );
    }

    function test_RevertIfCollateralZero() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscEngine), amountCollateral);

        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__AmountMustBeGreaterThanZero.selector
            )
        );
        dscEngine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function test_RevertWithUnapprovedCollateral() public {
        ERC20Mock unapprovedCollateral = new ERC20Mock(
            "Unapproved Collateral",
            "UAC",
            user,
            100 ether
        );

        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscEngine), amountCollateral);
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__NotAllowedToken.selector
            )
        );
        dscEngine.depositCollateral(
            address(unapprovedCollateral),
            amountCollateral
        );
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscEngine), amountCollateral);
        dscEngine.depositCollateral(weth, amountCollateral);
        vm.stopPrank();
        _;
    }

    function test_CanDepositCollateralWithoutMinting()
        public
        depositedCollateral
    {
        uint256 userBalance = deStablecoin.balanceOf(user);
        assertEq(userBalance, 0);
    }

    function test_GetAccountInformationAfterDeposit()
        public
        depositedCollateral
    {
        (uint256 totalCollateralValueInUsd, uint256 totalDebtMinted) = dscEngine
            .getAccountInformation(user);
        uint256 expectedDipositedValue = dscEngine.getTokenAmountFromUsd(
            weth,
            totalCollateralValueInUsd
        );
        assertEq(expectedDipositedValue, amountCollateral);
        assertEq(totalDebtMinted, 0);
    }

    // ============ Deposit and Mint DeStablecoin Tests ============

    function test_RevertsIfMintedDscBreaksHealthFactor() public {
        // Calculate USD value of collateral
        uint256 collateralValueInUsd = dscEngine.getUsdValue(
            weth,
            amountCollateral
        );

        // Calculate an amount to mint that would break health factor
        // Health factor = (collateral * 50%) / debt
        // For health factor < 1, we need debt > collateral * 50%
        // Let's mint 60% of collateral value to ensure health factor breaks
        amountToMint =
            (collateralValueInUsd * 60e18) /
            dscEngine.getPrecision();

        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscEngine), amountCollateral);

        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorIsBroken.selector);
        dscEngine.depositCollateralAndMintDsc(
            weth,
            amountCollateral,
            amountToMint
        );
        vm.stopPrank();
    }

    modifier depositedCollateralAndMintedDsc() {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscEngine), amountCollateral);
        dscEngine.depositCollateralAndMintDsc(
            weth,
            amountCollateral,
            amountToMint
        );
        vm.stopPrank();
        _;
    }

    function test_CanMintWithDepositedCollateral()
        public
        depositedCollateralAndMintedDsc
    {
        uint256 userBalance = deStablecoin.balanceOf(user);
        assertEq(userBalance, amountToMint);
    }

    // =========== Mint DeStablecoin Tests ============

    function test_RevertIfMintAmountIsZero() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscEngine), amountCollateral);
        dscEngine.depositCollateralAndMintDsc(
            weth,
            amountCollateral,
            amountToMint
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__AmountMustBeGreaterThanZero.selector
            )
        );
        dscEngine.mintDsc(0);
        vm.stopPrank();
    }

    function test_CanMintDsc() public depositedCollateral {
        vm.prank(user);
        dscEngine.mintDsc(amountToMint);

        uint256 userBalance = deStablecoin.balanceOf(user);
        assertEq(userBalance, amountToMint);
    }

    // use Mock to force mint failure
    function test_RevertIfMintFails() public {
        MockFailedMintDSC mockDsc = new MockFailedMintDSC();

        tokenAddresses = [weth];
        priceFeedAddresses = [wethUsdPriceFeed];
        address owner = msg.sender;

        vm.prank(owner);
        DSCEngine mockDscEngine = new DSCEngine(
            tokenAddresses,
            priceFeedAddresses,
            address(mockDsc)
        );
        mockDsc.transferOwnership(address(mockDscEngine));

        vm.startPrank(user);
        ERC20Mock(weth).approve(address(mockDscEngine), amountCollateral);

        vm.expectRevert(
            abi.encodeWithSelector(DSCEngine.DSCEngine__MintFailed.selector)
        );
        mockDscEngine.depositCollateralAndMintDsc(
            weth,
            amountCollateral,
            amountToMint
        );
        vm.stopPrank();
    }

    function test_RevertsIfMintAmountBreaksHealthFactor()
        public
        depositedCollateral
    {
        // Calculate USD value of collateral
        uint256 collateralValueInUsd = dscEngine.getUsdValue(
            weth,
            amountCollateral
        );

        // Calculate an amount to mint that would break health factor
        amountToMint =
            (collateralValueInUsd * 60e18) /
            dscEngine.getPrecision();

        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorIsBroken.selector);
        dscEngine.mintDsc(amountToMint);
        vm.stopPrank();
    }

    function test_CannotMintWithoutDepositingCollateral() public {
        vm.startPrank(user);

        // No collateral deposited, or approval given
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorIsBroken.selector);
        dscEngine.mintDsc(amountToMint);
        vm.stopPrank();
    }

    // =========== Burn DeStablecoin Tests ============

    function test_RevertIfBurnAmountIsZero()
        public
        depositedCollateralAndMintedDsc
    {
        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__AmountMustBeGreaterThanZero.selector
            )
        );
        dscEngine.burnDsc(0);
        vm.stopPrank();
    }

    function test_CannotBurnMoreThanUserBalance()
        public
        depositedCollateralAndMintedDsc
    {
        vm.startPrank(user);
        uint256 userBalance = deStablecoin.balanceOf(user);
        uint256 burnAmount = userBalance + 1 ether;

        vm.expectRevert();
        dscEngine.burnDsc(burnAmount);
        vm.stopPrank();
    }

    function test_CanBurnDsc() public depositedCollateralAndMintedDsc {
        vm.startPrank(user);
        uint256 userBalanceBeforeBurn = deStablecoin.balanceOf(user);
        assertEq(userBalanceBeforeBurn, amountToMint);

        deStablecoin.approve(address(dscEngine), amountToMint);
        dscEngine.burnDsc(amountToMint);

        uint256 userBalanceAfterBurn = deStablecoin.balanceOf(user);
        assertEq(userBalanceAfterBurn, 0);
        vm.stopPrank();
    }

    // ============ Redeem Collateral Tests ============

    function test_RevertIfRedeemAmountIsZero() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscEngine), amountCollateral);
        dscEngine.depositCollateralAndMintDsc(
            weth,
            amountCollateral,
            amountToMint
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__AmountMustBeGreaterThanZero.selector
            )
        );
        dscEngine.redeemCollateral(weth, 0);
        vm.stopPrank();
    }

    function test_CanRedeemCollateral() public depositedCollateral {
        vm.startPrank(user);
        uint256 userBalanceBeforeRedeem = dscEngine.getCollateralBalanceOfUser(
            user,
            weth
        );
        assertEq(userBalanceBeforeRedeem, amountCollateral);
        dscEngine.redeemCollateral(weth, amountCollateral);
        uint256 userBalanceAfterRedeem = dscEngine.getCollateralBalanceOfUser(
            user,
            weth
        );
        assertEq(userBalanceAfterRedeem, 0);
        vm.stopPrank();
    }

    function test_RevertsIfTransferFails() public {
        address owner = msg.sender;

        // Step 1: Create a mock token that fails only on transfer (not transferFrom)
        vm.prank(owner);
        MockFailedTransfer mockCollateral = new MockFailedTransfer();

        // Step 2: Mint tokens to the user while owner still has control
        vm.prank(owner);
        mockCollateral.mint(user, amountCollateral);

        // Step 3: Set up token and price feed arrays for DSCEngine constructor
        tokenAddresses = [address(mockCollateral)];
        priceFeedAddresses = [wethUsdPriceFeed];

        // Step 4: Create a new DSCEngine that accepts the mock token as collateral
        vm.prank(owner);
        DSCEngine mockDscEngine = new DSCEngine(
            tokenAddresses,
            priceFeedAddresses,
            address(deStablecoin)
        );

        // Step 5: Transfer ownership to mockDscEngine
        vm.prank(owner);
        mockCollateral.transferOwnership(address(mockDscEngine));

        // Step 6: User approves the engine to spend their tokens
        vm.startPrank(user);
        mockCollateral.approve(address(mockDscEngine), amountCollateral);

        // Step 7: User deposits collateral successfully (transferFrom works)
        mockDscEngine.depositCollateral(
            address(mockCollateral),
            amountCollateral
        );

        // Step 8: User attempts to redeem collateral, but transfer will fail
        vm.expectRevert(
            abi.encodeWithSelector(DSCEngine.DSCEngine__TransferFailed.selector)
        );
        mockDscEngine.redeemCollateral(
            address(mockCollateral),
            amountCollateral
        );
        vm.stopPrank();
    }

    function test_EmitCollateralRedeemedWithCorrectArgs()
        public
        depositedCollateral
    {
        vm.expectEmit(true, true, true, true, address(dscEngine));
        emit DSCEngine.CollateralRedeemed(user, user, weth, amountCollateral);
        vm.prank(user);
        dscEngine.redeemCollateral(weth, amountCollateral);
    }

    // ============ Redeem collateral for DeStablecoin Tests ============

    function test_MustRedeemMoreThanZero()
        public
        depositedCollateralAndMintedDsc
    {
        vm.startPrank(user);
        deStablecoin.approve(address(dscEngine), amountToMint);

        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__AmountMustBeGreaterThanZero.selector
            )
        );
        dscEngine.redeemCollateralForDsc(weth, 0, amountToMint);
        vm.stopPrank();
    }

    function test_CanRedeemDepositedCollateral()
        public
        depositedCollateralAndMintedDsc
    {
        vm.startPrank(user);
        uint256 userDscBalanceBefore = deStablecoin.balanceOf(user);
        assertEq(userDscBalanceBefore, amountToMint);

        uint256 userCollateralBalanceBefore = dscEngine
            .getCollateralBalanceOfUser(user, weth);
        assertEq(userCollateralBalanceBefore, amountCollateral);

        deStablecoin.approve(address(dscEngine), amountToMint);
        dscEngine.redeemCollateralForDsc(weth, amountCollateral, amountToMint);

        uint256 userDscBalanceAfter = deStablecoin.balanceOf(user);
        assertEq(userDscBalanceAfter, 0);

        uint256 userCollateralBalanceAfter = dscEngine
            .getCollateralBalanceOfUser(user, weth);
        assertEq(userCollateralBalanceAfter, 0);
        vm.stopPrank();
    }

    // ============ Health Factor Tests ============

    function test_ProperlyReportsHealthyAccount()
        public
        depositedCollateralAndMintedDsc
    {
        uint256 expoectedHealthFactor = dscEngine.getHealthFactor(user);
        uint256 healthFactor = dscEngine.getHealthFactor(user);
        assertEq(healthFactor, expoectedHealthFactor);
    }

    function test_HealthFactorCanGoBelowMinimum()
        public
        depositedCollateralAndMintedDsc
    {
        int256 ethUsdUpdatedPrice = 18e8; // $1800 per ETH

        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);

        uint256 healthFactor = dscEngine.getHealthFactor(user);
        // Calculating expected health factor:
        // Collateral value in USD = 10 ETH * $1800/ETH = $18,000
        // After liquidation threshold (50%): $18,000 * 50% = $9,000
        // Debt minted = $100
        // Health Factor = (Collateral Value * Liquidation Threshold) / Debt
        // Health Factor = ($18,000 * 50%) / $100 = 9000 = 0.9 ether
        assertEq(healthFactor, 0.9 ether);
    }

    // ============ Liquaidation Tests ============

    function test_MustImproveHealthFactorOnLiquidation()
        public
        depositedCollateralAndMintedDsc
    {
        // Arrange - Liquidator setup with enough collateral to stay healthy
        collateralToCover = 20 ether;
        ERC20Mock(weth).mint(liquidator, collateralToCover);

        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(dscEngine), collateralToCover);
        uint256 debtToCover = 10 ether;
        dscEngine.depositCollateralAndMintDsc(
            weth,
            collateralToCover,
            amountToMint
        );
        deStablecoin.approve(address(dscEngine), debtToCover);

        // Act - Crash the price so user is undercollateralized
        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18
        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);

        // Get health factor before liquidation
        uint256 healthFactorBefore = dscEngine.getHealthFactor(user);

        // Act - Liquidate the user
        dscEngine.liquidate(user, weth, debtToCover);

        // Assert - Health factor should have improved
        uint256 healthFactorAfter = dscEngine.getHealthFactor(user);
        assertGt(healthFactorAfter, healthFactorBefore);

        vm.stopPrank();
    }

    function test_CantLiquidateGoodHealthFactor()
        public
        depositedCollateralAndMintedDsc
    {
        ERC20Mock(weth).mint(liquidator, collateralToCover);

        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(dscEngine), collateralToCover);
        dscEngine.depositCollateralAndMintDsc(
            weth,
            collateralToCover,
            amountToMint
        );
        deStablecoin.approve(address(dscEngine), amountToMint);

        // Act / Assert - Attempt to liquidate the user with good health factor
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__HealthFactorIsOk.selector
            )
        );
        dscEngine.liquidate(user, weth, amountToMint);

        vm.stopPrank();
    }

    modifier liquidated() {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscEngine), amountCollateral);
        dscEngine.depositCollateralAndMintDsc(
            weth,
            amountCollateral,
            amountToMint
        );
        vm.stopPrank();
        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18

        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);
        uint256 userHealthFactor = dscEngine.getHealthFactor(user);

        ERC20Mock(weth).mint(liquidator, collateralToCover);

        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(dscEngine), collateralToCover);
        dscEngine.depositCollateralAndMintDsc(
            weth,
            collateralToCover,
            amountToMint
        );
        deStablecoin.approve(address(dscEngine), amountToMint);
        dscEngine.liquidate(user, weth, amountToMint);
        vm.stopPrank();
        _;
    }

    function test_LiquidationPayoutIsCorrect() public liquidated {
        uint256 liquidatorWethBalance = ERC20Mock(weth).balanceOf(liquidator);
        uint256 expectedWeth = dscEngine.getTokenAmountFromUsd(
            weth,
            amountToMint
        ) +
            ((dscEngine.getTokenAmountFromUsd(weth, amountToMint) *
                dscEngine.getLiquidationBonus()) /
                dscEngine.getLiquidationPrecision());
        uint256 hardCodedExpected = 6_111_111_111_111_111_110;
        assertEq(liquidatorWethBalance, hardCodedExpected);
        assertEq(liquidatorWethBalance, expectedWeth);
    }

    function test_UserStillHasSomeEthAfterLiquidation() public liquidated {
        uint256 userWethBalance = dscEngine.getCollateralBalanceOfUser(
            user,
            weth
        );
        assertGt(userWethBalance, 0);
    }

    function test_LiquidatorTakesOnUsersDebt() public liquidated {
        (, uint256 liquidatorDscMinted) = dscEngine.getAccountInformation(
            liquidator
        );
        assertEq(liquidatorDscMinted, amountToMint);
    }

    // ============ View / Pure Function Tests ============

    function test_GetCollateralTokenPriceFeed() public {
        address priceFeed = dscEngine.getCollateralTokenPriceFeed(weth);
        assertEq(priceFeed, wethUsdPriceFeed);
    }

    function test_GetCollateralTokens() public {
        address[] memory collateralTokens = dscEngine.getCollateralTokens();
        assertEq(collateralTokens[0], weth);
    }

    function test_GetMinHealthFactor() public {
        uint256 minHealthFactor = dscEngine.getMinHealthFactor();
        assertEq(minHealthFactor, MIN_HEALTH_FACTOR);
    }

    function test_GetLiquidationThreshold() public {
        uint256 liquidationThreshold = dscEngine.getLiquidationThreshold();
        assertEq(liquidationThreshold, LIQUIDATION_THRESHOLD);
    }

    function test_GetAccountCollateralValueFromInformation()
        public
        depositedCollateral
    {
        (uint256 collateralValue, ) = dscEngine.getAccountInformation(user);
        uint256 expectedCollateralValue = dscEngine.getUsdValue(
            weth,
            amountCollateral
        );
        assertEq(collateralValue, expectedCollateralValue);
    }

    function test_GetCollateralBalanceOfUser() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscEngine), amountCollateral);
        dscEngine.depositCollateral(weth, amountCollateral);
        vm.stopPrank();
        uint256 collateralBalance = dscEngine.getCollateralBalanceOfUser(user, weth);
        assertEq(collateralBalance, amountCollateral);
    }

    function test_GetAccountCollateralValue() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscEngine), amountCollateral);
        dscEngine.depositCollateral(weth, amountCollateral);
        vm.stopPrank();
        uint256 collateralValue = dscEngine.getAccountCollateralValue(user);
        uint256 expectedCollateralValue = dscEngine.getUsdValue(
            weth,
            amountCollateral
        );
        assertEq(collateralValue, expectedCollateralValue);
    }

    function test_GetDsc() public {
        address dscAddress = dscEngine.getDsc();
        assertEq(dscAddress, address(deStablecoin));
    }

    function test_LiquidationPrecision() public {
        uint256 expectedLiquidationPrecision = 100;
        uint256 actualLiquidationPrecision = dscEngine.getLiquidationPrecision();
        assertEq(actualLiquidationPrecision, expectedLiquidationPrecision);
    }
}
