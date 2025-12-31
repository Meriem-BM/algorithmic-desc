// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/**
 * @title IDSCEngine
 * @notice Interface for all contracts used in the DSC Engine system
 * @dev This file consolidates all interfaces for easy reference
 * 
 * Note: IERC20 is imported from OpenZeppelin:
 * openzeppelin-contracts/contracts/token/ERC20/IERC20.sol
 */

// ============ Chainlink Price Feed Interface ============
interface AggregatorV3Interface {
    function decimals() external view returns (uint8);
    function description() external view returns (string memory);
    function version() external view returns (uint256);
    function getRoundData(uint80 _roundId)
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}

// ============ DSC Engine Interface ============
interface IDSCEngine {
    // Events
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    
    // Functions
    function depositCollateralAndMintDsc(uint256 _amountCollateral, uint256 _amountDscToMint) external;
    function depositCollateral(address _collateral, uint256 _amountCollateral) external;
    function redeemCollateralForDsc(uint256 _amountCollateral, uint256 _amountDscToBurn) external;
    function redeemCollateral(address _collateral, uint256 _amountCollateral) external;
    function mintDsc(uint256 _amountDscToMint) external;
    function burnDsc(uint256 _amountDscToBurn) external;
    function liquidate(address _borrowers, address _collateral, uint256 _amountCollateral, uint256 _amountDscToBurn) external;
    function getHealthFactor(address _borrowers) external view returns (uint256);
    function getAccountCollateralValue(address _account) external view returns (uint256);
}

