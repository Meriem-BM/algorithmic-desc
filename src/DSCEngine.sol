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
    error DSCEngine__HealthFactorIsBroken();
    error DSCEngine__MintFailed();
    error DSCEngine__BurnFailed();

    // --- State Variables ---
    mapping(address token => address priceFeed) private s_priceFeeds; // token => price feed
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited; // user => token => amount deposited
    mapping(address user => uint256 amountDscMinted) private s_userDscMinted; // user => amount DSC minted
    mapping(address user => mapping(address token => uint256 amount)) private s_debtTokenMapping; // user => token => amount debt

    address[] private s_collateralTokens;

    DeStablecoin private immutable s_dsc; // Using interface instead of concrete type
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // This means you need to be 200% over-collateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant LIQUIDATION_BONUS = 10; // This means you get assets at a 10% discount when liquidating
    uint256 private constant MIN_HEALTH_FACTOR = 1;

    // --- Events ---
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event DscMinted(address indexed user, uint256 indexed amount);
    event CollateralRedeemed(address indexed from, address indexed to, address indexed token, uint256 amount);
    event DscBurned(address indexed user, uint256 indexed amount);

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
    function depositCollateralAndMintDsc(address _collateral, uint256 _amountCollateral, uint256 _amountDscToMint)
        external
    {
        // 1. Deposit the collateral
        // 2. Mint the DSC
        depositCollateral(_collateral, _amountCollateral);
        mintDsc(_amountDscToMint);
    }

    /**
     * @notice Deposits collateral and mints DSC
     * @param _collateral The address of the collateral to deposit
     * @param _amountCollateral The amount of collateral to deposit
     */
    function depositCollateral(address _collateral, uint256 _amountCollateral)
        public
        moreThanZero(_amountCollateral)
        isAllowedToken(_collateral)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][_collateral] += _amountCollateral;
        emit CollateralDeposited(msg.sender, _collateral, _amountCollateral);
        bool success = IERC20(_collateral).transfer(msg.sender, _amountCollateral);
        if (!success) revert DSCEngine__TransferFailed();
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice Redeems collateral for DSC
     * @param _collateral The address of the collateral to redeem
     * @param _amountCollateral The amount of collateral to redeem
     * @param _amountDscToBurn The amount of DSC to burn
     */
    function redeemCollateralForDsc(address _collateral, uint256 _amountCollateral, uint256 _amountDscToBurn)
        public
        moreThanZero(_amountCollateral)
        moreThanZero(_amountDscToBurn)
        nonReentrant
    {
        burnDsc(_amountDscToBurn);
        redeemCollateral(_collateral, _amountCollateral);
        // redeem collateral already reverts if health factor is broken
    }

    /**
     * @notice Redeems collateral for DSC
     * @param _collateral The address of the collateral to redeem
     * @param _amountCollateral The amount of collateral to redeem
     */
    function redeemCollateral(address _collateral, uint256 _amountCollateral) public {
        _redeemCollateral(_collateral, _amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice Mints DSC
     * @param _amountDscToMint The amount of DSC to mint
     * @notice Must have more than 0 DSC to mint
     */
    function mintDsc(uint256 _amountDscToMint) public moreThanZero(_amountDscToMint) nonReentrant {
        // Using interface - we know exactly what functions are available
        s_userDscMinted[msg.sender] += _amountDscToMint;

        // 1. Check if the health factor is broken
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = s_dsc.mint(msg.sender, _amountDscToMint);
        if (!minted) revert DSCEngine__MintFailed();
        emit DscMinted(msg.sender, _amountDscToMint);
    }

    /**
     * @notice Burns DSC tokens to reduce debt
     * @param _amountDscToBurn The amount of DSC to burn
     * @dev User must approve this contract to spend their DSC tokens before calling this function
     * @dev Approval: dscToken.approve(address(this), _amountDscToBurn)
     */
    function burnDsc(uint256 _amountDscToBurn) public moreThanZero(_amountDscToBurn) nonReentrant {
        s_userDscMinted[msg.sender] -= _amountDscToBurn;
        // transferFrom requires user to approve this contract first
        bool success = IERC20(address(s_dsc)).transferFrom(msg.sender, address(this), _amountDscToBurn);
        if (!success) revert DSCEngine__BurnFailed();
        s_dsc.burn(_amountDscToBurn);
        emit DscBurned(msg.sender, _amountDscToBurn);
    }

    function liquidate(address _userToBeLiquidated, address _collateral, uint256 _debtToCover) external {
        uint256 startingUserHealthFactor = _healthFactor(_userToBeLiquidated);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) revert DSCEngine__HealthFactorIsBroken();

        // If covering 100 DSC, we need to $100 of collateral
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(_collateral, _debtToCover);
        // And give them a 10% bonus
        // So we are giving the liquidator $110 of WETH for 100 DSC
        // We should implement a feature to liquidate in the event the protocol is insolvent
        // And sweep extra amounts into a treasury
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        // Burn DSC equal to debtToCover
        // Figure out how much collateral to recover based on how much burnt

        _redeemCollateral(_collateral, tokenAmountFromDebtCovered + bonusCollateral, _userToBeLiquidated, address(this));
        _burnDsc(_debtToCover, _userToBeLiquidated, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(_userToBeLiquidated);
        if (endingUserHealthFactor >= startingUserHealthFactor) revert DSCEngine__HealthFactorIsBroken();
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    // --- private functions ---

    /**
     * @notice Redeems collateral from an account
     * @param _tokenCollatoralAddress The address of the collateral token
     * @param _amountCollateral The amount of collateral to redeem
     * @param _from The account to redeem from
     * @param _to The account to redeem to
     */
    function _redeemCollateral(address _tokenCollatoralAddress, uint256 _amountCollateral, address _from, address _to)
        private
    {
        s_collateralDeposited[_from][_tokenCollatoralAddress] -= _amountCollateral;
        emit CollateralRedeemed(_from, _to, _tokenCollatoralAddress, _amountCollateral);
        bool success = IERC20(_tokenCollatoralAddress).transfer(_to, _amountCollateral);
        if (!success) revert DSCEngine__TransferFailed();
        _revertIfHealthFactorIsBroken(_from);
    }

    /**
     * @notice Burns DSC tokens from an account
     * @param _amountDscToBurn The amount of DSC to burn
     * @param _onBehalfOf The account to burn DSC from
     * @param _dscFrom The account to burn DSC from
     */
    function _burnDsc(uint256 _amountDscToBurn, address _onBehalfOf, address _dscFrom) private {
        s_userDscMinted[_onBehalfOf] -= _amountDscToBurn;
        bool success = IERC20(address(s_dsc)).transferFrom(_dscFrom, address(this), _amountDscToBurn);
        if (!success) revert DSCEngine__BurnFailed();
        s_dsc.burn(_amountDscToBurn);
        emit DscBurned(_onBehalfOf, _amountDscToBurn);
    }

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
        if (_healthFactor(_account) < MIN_HEALTH_FACTOR) revert DSCEngine__HealthFactorIsBroken();
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

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        // $100e18 USD Debt
        // 1 ETH = 2000 USD
        // The returned value from Chainlink will be 2000 * 1e8
        // Most USD pairs have 8 decimals, so we will just pretend they all do
        return ((usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION));
    }
}
