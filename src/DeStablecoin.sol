// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ERC20Burnable, ERC20} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

contract DeStablecoin is ERC20Burnable, Ownable {
    constructor() ERC20("DeStablecoin", "DSC") Ownable(msg.sender) {}

    // =========================================== Errors ===========================================
    error DeStablecoin__InvalidAddress();
    error DeStablecoin__AmountMustBeGreaterThanZero();
    error DeStablecoin__InsufficientBalance(uint256 balance, uint256 amount);
    error DeStablecoin__BurnAmountExceedsBalance(uint256 remaining);

    // =========================================== Modifiers ===========================================
    modifier moreThanZero(uint256 _amount) {
        if (_amount <= 0) revert DeStablecoin__AmountMustBeGreaterThanZero();
        _;
    }

    // =========================================== Functions ===========================================
    function mint(address _to, uint256 _amount) external onlyOwner moreThanZero(_amount) returns (bool) {
        if (_to == address(0)) revert DeStablecoin__InvalidAddress();
        _mint(_to, _amount);
        return true;
    }

    function burn(uint256 _amount) public override onlyOwner moreThanZero(_amount) {
        uint256 balance = balanceOf(msg.sender);

        if (balance < _amount) revert DeStablecoin__InsufficientBalance(balance, _amount);

        uint256 remaining = balance - _amount;
        if (balance < _amount) revert DeStablecoin__BurnAmountExceedsBalance(remaining);

        super.burn(_amount);
    }
}
