// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockFailedTransferOnly
 * @notice Mock ERC20 token that always fails on transfer but succeeds on transferFrom
 * @dev Useful for testing transfer failure scenarios during redemption in DSCEngine
 */
contract MockFailedTransfer is ERC20Burnable, Ownable {
    error DecentralizedStableCoin__AmountMustBeMoreThanZero();
    error DecentralizedStableCoin__NotZeroAddress();

    constructor() ERC20("MockFailedTransferOnly", "MFTO") Ownable(msg.sender) {}

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
     * @dev This simulates redeem failure scenario
     */
    function transfer(
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

    /**
     * @notice Normal transferFrom that succeeds
     * @dev This allows deposits to succeed while transfers (redeems) fail
     */
    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        return super.transferFrom(sender, recipient, amount);
    }
}
