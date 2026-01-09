// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockFailedTransfer
 * @notice Mock ERC20 token that always fails on transfer and transferFrom
 * @dev Useful for testing transfer failure scenarios in DSCEngine
 */
contract MockFailedTransfer is ERC20Burnable, Ownable {
    error DecentralizedStableCoin__AmountMustBeMoreThanZero();
    error DecentralizedStableCoin__BurnAmountExceedsBalance();

    constructor() ERC20("MockFailedTransfer", "MFT") Ownable(msg.sender) {}

    /**
     * @notice Mint tokens for testing purposes
     * @dev Useful for setting up test balances before testing transfer failures
     */
    function mint(address account, uint256 amount) public {
        _mint(account, amount);
    }

    /**
     * @notice Always returns false to simulate transfer failure
     */
    function transfer(address /*recipient*/, uint256 /*amount*/) public pure override returns (bool) {
        return false;
    }

    /**
     * @notice Always returns false to simulate transferFrom failure
     * @dev This is critical for testing depositCollateral which uses transferFrom
     */
    function transferFrom(
        address, /*sender*/
        address, /*recipient*/
        uint256 /*amount*/
    )
        public
        pure
        override
        returns (bool)
    {
        return false;
    }
}
