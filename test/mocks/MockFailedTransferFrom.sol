// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockFailedTransfer
 * @notice Mock ERC20 token that always fails on transfer and transferFrom
 * @dev Useful for testing transfer failure scenarios in DSCEngine
 */
contract MockFailedTransferFrom is ERC20Burnable, Ownable {
    error DecentralizedStableCoin__AmountMustBeMoreThanZero();
    error DecentralizedStableCoin__BurnAmountExceedsBalance();
    error DecentralizedStableCoin__NotZeroAddress();

    constructor() ERC20("DecentralizedStableCoin", "DSC") Ownable(msg.sender) {}

    modifier moreThanZero(uint256 _amount) {
        if (_amount <= 0) {
            revert DecentralizedStableCoin__AmountMustBeMoreThanZero();
        }
        _;
    }

    /**
     * @notice Mint tokens for testing purposes
     * @dev Useful for setting up test balances before testing transfer failures
     */
    function mint(address _to, uint256 _amount) external onlyOwner moreThanZero(_amount) returns (bool) {
        if (_to == address(0)) {
            revert DecentralizedStableCoin__NotZeroAddress();
        }
        _mint(_to, _amount);
        return true;
    }

    /**
     * @notice Always returns false to simulate transfer failure
     */
    function transfer(address recipient, uint256 amount) public override returns (bool) {
        return super.transfer(recipient, amount);
    }

    /**
     * @notice Always returns false to simulate transferFrom failure
     * @dev This is critical for testing depositCollateral which uses transferFrom
     */
    function transferFrom(
        address,
        /*sender*/
        address,
        /*recipient*/
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
