// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {DeStablecoin} from "./DeStablecoin.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IDSCEngine} from "./interfaces/IDSCEngine.sol";

/**
 * @title DSCEngine
 * @author @Meriem-BM
 * @notice This contract is the main contract for the DSCEngine system.
 * @dev This contract is responsible for the creation and management of the DSCEngine system.
 */

contract DSCEngine is ReentrancyGuard {
    // --- Errors ---
    error DSCEngine__NotEnoughCollateral();
    error DSCEngine__TokenAddressesAndPriceFeedsLengthMismatch();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferFailed();

    // --- State Variables ---
    mapping(address token => address priceFeed) private s_priceFeeds; // token => price feed
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited; // user => token => amount deposited
    mapping(address user => uint256 amountDscMinted) private s_userDscMinted; // user => amount DSC minted
    mapping(address user => mapping(address token => uint256 amount)) private s_debtTokenMapping; // user => token => amount debt

    address[] private s_collateralTokens;

    DeStablecoin private immutable s_dsc; // Using interface instead of concrete type
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;

    // --- Events ---
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event DscMinted(address indexed user, uint256 indexed amount);

    // --- Modifiers ---
    modifier moreThanZero(uint256 _amount) {
        if (_amount <= 0) revert DSCEngine__NotEnoughCollateral();
        _;
    }

    modifier isAllowedToken(address _token) {
        if (s_priceFeeds[_token] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }

    // --- functions ---
    constructor(address[] memory _tokenAddresses, address[] memory _priceFeedAddresses, address dscAddress) {
        if (_tokenAddresses.length != _priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedsLengthMismatch();
        }
        for (uint256 i = 0; i < _tokenAddresses.length; i++) {
            s_priceFeeds[_tokenAddresses[i]] = _priceFeedAddresses[i];
            s_collateralTokens.push(_tokenAddresses[i]);
        }
        s_dsc = DeStablecoin(dscAddress); // Using interface - more flexible
    }

    // --- external functions ---
    function depositCollateralAndMintDsc(uint256 _amountCollateral, uint256 _amountDscToMint) external {
        // 1. Deposit the collateral
        // 2. Mint the DSC
    }

    /**
     * @notice Deposits collateral and mints DSC
     * @param _collateral The address of the collateral to deposit
     * @param _amountCollateral The amount of collateral to deposit
     */
    function depositCollateral(address _collateral, uint256 _amountCollateral)
        external
        moreThanZero(_amountCollateral)
        isAllowedToken(_collateral)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][_collateral] += _amountCollateral;
        emit CollateralDeposited(msg.sender, _collateral, _amountCollateral);
        bool success = IERC20(_collateral).transferFrom(msg.sender, address(this), _amountCollateral);
        if (!success) revert DSCEngine__TransferFailed();
    }

    function redeemCollateralForDsc(uint256 _amountCollateral, uint256 _amountDscToBurn) external {
        // 1. Burn the DSC
        // 2. Redeem the collateral
    }

    function redeemCollateral(address _collateral, uint256 _amountCollateral) external {
        // 1. Redeem the collateral
    }

    /**
     * @notice Mints DSC
     * @param _amountDscToMint The amount of DSC to mint
     * @notice Must have more than 0 DSC to mint
     */
    function mintDsc(uint256 _amountDscToMint) external moreThanZero(_amountDscToMint) nonReentrant {
        // Using interface - we know exactly what functions are available
        s_userDscMinted[msg.sender] += _amountDscToMint;
        bool success = s_dsc.mint(msg.sender, _amountDscToMint);
        if (!success) revert DSCEngine__TransferFailed();
        emit DscMinted(msg.sender, _amountDscToMint);
    }

    function burnDsc(uint256 _amountDscToBurn) external {
        // Using interface - type-safe and clear
        s_dsc.burn(_amountDscToBurn);
    }

    function liquidate(address _borrowers, address _collateral, uint256 _amountCollateral, uint256 _amountDscToBurn)
        external {
        // 1. Burn the DSC
        // 2. Redeem the collateral
    }

    // --- private functions ---

    /**
     * @notice Gets the total collateral value of an account
     * @param _account The account address
     * @return totalCollateralValueInUsd The total collateral value
     * @return totalDebtMinted The total debt value
     */
    function _getAccountInfo(address _account)
        private
        view
        returns (uint256 totalCollateralValueInUsd, uint256 totalDebtMinted)
    {
        // 1. Get the total collateral value
        // 2. Get the total debt value
        totalCollateralValueInUsd = getAccountCollateralValue(_account);
        totalDebtMinted = getAccountDebtValue(_account);
        return (totalCollateralValueInUsd, totalDebtMinted);
    }

    /**
     * @notice Calculates the health factor of an account
     * @param _account The account address
     * @return The health factor
     */
    function _healthFactor(address _account) private view returns (uint256) {
        // 1. Get the total collateral value
        // 2. Get the total debt value
        // 3. Calculate the health factor
        (uint256 totalCollateralValueInUsd, uint256 totalDebtMinted) = _getAccountInfo(_account);
        uint256 collateralAdjustedForThreshold =
            (totalCollateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDebtMinted;
    }

    /**
     * @notice Reverts if the health factor is broken
     * @param _account The account address
     */
    function _revertIfHealthFactorIsBroken(address _account) private view {
        // 1. Get the health factor
        // 2. If the health factor is broken, revert
    }

    // --- Public & External View Functions ---
    function getAccountCollateralValue(address _account) public view returns (uint256 totalCollateralValueInUsd) {
        // 1. Get the total collateral value
        // 2. Calculate the account collateral value
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[_account][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getAccountDebtValue(address _account) public view returns (uint256) {
        // 1. Get the total debt value
        // 2. Calculate the account debt value
        return s_userDscMinted[_account];
    }

    function getUsdValue(address _token, uint256 _amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[_token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * _amount) / PRECISION;
    }
}
