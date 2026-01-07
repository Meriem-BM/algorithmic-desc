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
    // =========================================== Errors ===========================================
    error DSCEngine__NotEnoughCollateral();
    error DSCEngine__TokenAddressesAndPriceFeedsLengthMismatch();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferFailed();
    error DSCEngine__HealthFactorIsBroken();
    error DSCEngine__HealthFactorIsOk();
    error DSCEngine__MintFailed();
    error DSCEngine__InvalidPriceFeed();

    // =========================================== State Variables ===========================================
    mapping(address token => address priceFeed) private s_priceFeeds; // token => price feed
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited; // user => token => amount deposited
    mapping(address user => uint256 amountDscMinted) private s_userDscMinted; // user => amount DSC minted
    mapping(address user => mapping(address token => uint256 amount)) private s_debtTokenMapping; // user => token => amount debt

    address[] private s_collateralTokens;
    DeStablecoin private immutable i_dsc;

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // This means you need to be 200% over-collateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant LIQUIDATION_BONUS = 10; // This means you get assets at a 10% discount when liquidating
    uint256 private constant MIN_HEALTH_FACTOR = 1;

    // =========================================== Events ===========================================
    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);
    event DscMinted(address indexed user, uint256 indexed amount);
    event CollateralRedeemed(address indexed from, address indexed to, address indexed token, uint256 amount);

    // =========================================== Modifiers ===========================================
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

    // =========================================== Constructor ===========================================
    constructor(address[] memory _tokenAddresses, address[] memory _priceFeedAddresses, address dscAddress) {
        if (_tokenAddresses.length != _priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedsLengthMismatch();
        }
        for (uint256 i = 0; i < _tokenAddresses.length; i++) {
            s_priceFeeds[_tokenAddresses[i]] = _priceFeedAddresses[i];
            s_collateralTokens.push(_tokenAddresses[i]);
        }
        i_dsc = DeStablecoin(dscAddress); // Using interface - more flexible
    }

    // =========================================== External Functions ===========================================
    /**
     * @notice Deposits collateral and mints DSC in a single transaction
     * @param _collateral The address of the collateral to deposit
     * @param _amountCollateral The amount of collateral to deposit
     * @param _amountDscToMint The amount of DSC to mint
     */
    function depositCollateralAndMintDsc(address _collateral, uint256 _amountCollateral, uint256 _amountDscToMint)
        external
    {
        depositCollateral(_collateral, _amountCollateral);
        mintDsc(_amountDscToMint);
    }

    /**
     * @notice Deposits collateral into the contract
     * @param _collateralAddress The address of the collateral to deposit
     * @param _amountCollateral The amount of collateral to deposit
     */
    function depositCollateral(address _collateralAddress, uint256 _amountCollateral)
        public
        moreThanZero(_amountCollateral)
        isAllowedToken(_collateralAddress)
        nonReentrant
    {
        // For deposits: Interaction first (receive tokens), then update state
        // This ensures state only updates if tokens are successfully received
        bool success = IERC20(_collateralAddress).transferFrom(msg.sender, address(this), _amountCollateral);
        if (!success) revert DSCEngine__TransferFailed();
        // Update state after confirming tokens received
        s_collateralDeposited[msg.sender][_collateralAddress] += _amountCollateral;
        emit CollateralDeposited(msg.sender, _collateralAddress, _amountCollateral);
    }

    /**
     * @notice Redeems collateral for DSC
     * @param _collateralAddress The address of the collateral to redeem
     * @param _amountCollateral The amount of collateral to redeem
     * @param _amountDscToBurn The amount of DSC to burn
     */
    function redeemCollateralForDsc(address _collateralAddress, uint256 _amountCollateral, uint256 _amountDscToBurn)
        external
        moreThanZero(_amountCollateral)
        moreThanZero(_amountDscToBurn)
        isAllowedToken(_collateralAddress)
        nonReentrant
    {
        _burnDsc(_amountDscToBurn, msg.sender, msg.sender);
        _redeemCollateral(_collateralAddress, _amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice Redeems collateral
     * @param _collateral The address of the collateral to redeem
     * @param _amountCollateral The amount of collateral to redeem
     */
    function redeemCollateral(address _collateral, uint256 _amountCollateral)
        public
        moreThanZero(_amountCollateral)
        isAllowedToken(_collateral)
        nonReentrant
    {
        _redeemCollateral(_collateral, _amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice Mints DSC
     * @param _amountDscToMint The amount of DSC to mint
     * @notice Must have more than 0 DSC to mint and the health factor must not be broken
     */
    function mintDsc(uint256 _amountDscToMint) public moreThanZero(_amountDscToMint) nonReentrant {
        s_userDscMinted[msg.sender] += _amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, _amountDscToMint);
        if (!minted) revert DSCEngine__MintFailed();
        emit DscMinted(msg.sender, _amountDscToMint);
    }

    /**
     * @notice Burns DSC tokens to reduce debt
     * @param _amount The amount of DSC to burn
     * @dev User must approve this contract to spend their DSC tokens before calling this function
     * @dev Approval: dscToken.approve(address(this), _amount)
     */
    function burnDsc(uint256 _amount) external moreThanZero(_amount) nonReentrant {
        _burnDsc(_amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function liquidate(address _userToBeLiquidated, address _collateralAddress, uint256 _debtToCover)
        external
        isAllowedToken(_collateralAddress)
        moreThanZero(_debtToCover)
        nonReentrant
    {
        uint256 startingUserHealthFactor = _healthFactor(_userToBeLiquidated);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) revert DSCEngine__HealthFactorIsOk();

        // If covering 100 DSC, we need to $100 of collateral
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(_collateralAddress, _debtToCover);
        // And give them a 10% bonus
        // So we are giving the liquidator $110 of WETH for 100 DSC
        // We should implement a feature to liquidate in the event the protocol is insolvent
        // And sweep extra amounts into a treasury
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        // Burn DSC equal to debtToCover
        // Figure out how much collateral to recover based on how much burnt

        // Validate user has enough collateral
        if (s_collateralDeposited[_userToBeLiquidated][_collateralAddress] < tokenAmountFromDebtCovered + bonusCollateral) {
            revert DSCEngine__NotEnoughCollateral();
        }
        
        // Validate liquidator has enough DSC
        if (IERC20(address(i_dsc)).balanceOf(msg.sender) < _debtToCover) {
            revert DSCEngine__NotEnoughCollateral();
        }

        _redeemCollateral(
            _collateralAddress, tokenAmountFromDebtCovered + bonusCollateral, _userToBeLiquidated, msg.sender
        );
        _burnDsc(_debtToCover, _userToBeLiquidated, msg.sender);

        // Verify health factor improved
        uint256 endingUserHealthFactor = _healthFactor(_userToBeLiquidated);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorIsBroken();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    // =========================================== Private Functions ===========================================

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
    }

    /**
     * @notice Burns DSC tokens from an account
     * @param _amountDscToBurn The amount of DSC to burn
     * @param _onBehalfOf The account to burn DSC from
     * @param _dscFrom The account to burn DSC from
     */
    function _burnDsc(uint256 _amountDscToBurn, address _onBehalfOf, address _dscFrom) private {
        s_userDscMinted[_onBehalfOf] -= _amountDscToBurn;
        bool success = IERC20(address(i_dsc)).transferFrom(_dscFrom, address(this), _amountDscToBurn);
        if (!success) revert DSCEngine__TransferFailed();
        i_dsc.burn(_amountDscToBurn);
    }

    // =========================================== Private & Internal View & Pure Functions ===========================================

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
        totalDebtMinted = s_userDscMinted[_account];
        totalCollateralValueInUsd = getAccountCollateralValue(_account);
    }

    /**
     * @notice Calculates the health factor of an account
     * @param _account The account address
     * @return The health factor
     * @dev Health factor = (total collateral value * liquidation threshold) / total debt value
     * @dev Liquidation threshold = 50%
     * @dev Precision = 1e18
     * @dev Total collateral value = sum of all collateral values
     * @dev Total debt value = sum of all debt values
     * @dev Collateral value = collateral amount * collateral price
     * @dev Debt value = debt amount * debt price
     * @dev Collateral price = price feed value
     * @dev Debt price = price feed value
     */
    function _healthFactor(address _account) private view returns (uint256) {
        (uint256 totalCollateralValueInUsd, uint256 totalDebtMinted) = _getAccountInfo(_account);
        return _calculateHealthFactor(totalCollateralValueInUsd, totalDebtMinted);
    }

    /**
     * @notice Gets the USD value of a token
     * @param _token The address of the token
     * @param _amount The amount of the token in Wei
     * @return The USD value of the token
     */
    function _getUsdValue(address _token, uint256 _amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[_token]);
        (, int256 price,, uint256 updatedAt, uint80 answeredInRound) = priceFeed.latestRoundData();
        
        // Validate price is positive
        if (price <= 0) revert DSCEngine__InvalidPriceFeed();
        
        // Validate price is not stale (assuming 3 hours = 10800 seconds)
        if (block.timestamp - updatedAt > 3 hours) revert DSCEngine__InvalidPriceFeed();
        
        // Validate round is complete
        if (answeredInRound == 0) revert DSCEngine__InvalidPriceFeed();
        
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * _amount) / PRECISION;
    }

    function _calculateHealthFactor(uint256 _totalCollateralValueInUsd, uint256 _totalDebtMinted)
        internal
        pure
        returns (uint256)
    {
        if (_totalDebtMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold =
            (_totalCollateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / _totalDebtMinted;
    }

    /**
     * @notice Reverts if the health factor is broken
     * @param _account The account address
     * @dev If the health factor is less than the minimum health factor, revert
     */
    function _revertIfHealthFactorIsBroken(address _account) private view {
        if (_healthFactor(_account) < MIN_HEALTH_FACTOR) revert DSCEngine__HealthFactorIsBroken();
    }

    // =========================================== Public & External View Functions ===========================================

    function calculateHealthFactor(uint256 _totalCollateralValueInUsd, uint256 _totalDebtMinted)
        external
        pure
        returns (uint256)
    {
        return _calculateHealthFactor(_totalCollateralValueInUsd, _totalDebtMinted);
    }

    function getAccountInformation(address _account)
        external
        view
        returns (uint256 totalCollateralValueInUsd, uint256 totalDebtMinted)
    {
        return _getAccountInfo(_account);
    }

    function getUsdValue(address _token, uint256 _amount) external view returns (uint256) {
        return _getUsdValue(_token, _amount);
    }

    function getCollateralBalanceOfUser(address _account, address _token) external view returns (uint256) {
        return s_collateralDeposited[_account][_token];
    }

    function getAccountCollateralValue(address _account) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[_account][token];
            totalCollateralValueInUsd += _getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,, uint256 updatedAt, uint80 answeredInRound) = priceFeed.latestRoundData();
        
        // Validate price is positive
        if (price <= 0) revert DSCEngine__InvalidPriceFeed();
        
        // Validate price is not stale (assuming 3 hours = 10800 seconds)
        if (block.timestamp - updatedAt > 3 hours) revert DSCEngine__InvalidPriceFeed();
        
        // Validate round is complete
        if (answeredInRound == 0) revert DSCEngine__InvalidPriceFeed();
        
        // $100e18 USD Debt
        // 1 ETH = 2000 USD
        // The returned value from Chainlink will be 2000 * 1e8
        // Most USD pairs have 8 decimals, so we will just pretend they all do
        return ((usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION));
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getDsc() external view returns (address) {
        return address(i_dsc);
    }

    function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return s_priceFeeds[token];
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }
}
