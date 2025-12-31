// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DeStablecoin} from "../../src/DeStablecoin.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";

contract DSCEngineTest is Test {
    DeployDSC public deployDSC;
    DeStablecoin public deStablecoin;
    DSCEngine public dscEngine;
    HelperConfig public helperConfig;

    function setUp() public {
        helperConfig = new HelperConfig();
        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc, address deployerKey) =
            helperConfig.activeNetworkConfig();

        address[] memory tokenAddresses = [weth, wbtc];
        address[] memory priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed];

        deployDSC = new DeployDSC();
        (deStablecoin, dscEngine) = deployDSC.run();
    }

    function test_GetUsdValue() public {
        uint256 usdValue = dscEngine.getUsdValue(weth, 100);
        assertEq(usdValue, 100);
    }

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
