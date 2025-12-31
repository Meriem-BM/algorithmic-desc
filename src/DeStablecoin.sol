// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ERC20Burnable, ERC20} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

contract DeStablecoin is ERC20Burnable, Ownable {
    constructor() ERC20("DeStablecoin", "DSC") Ownable(msg.sender) {}

    // Custom Errors
    error InvalidAddress();
    error AmountMustBeGreaterThanZero();
    error TotalSupplyExceeded(uint256 requested, uint256 maxSupply);
    error BalanceMustBeZero(uint256 remaining);
    error InsufficientBalance(uint256 balance, uint256 amount);

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) revert InvalidAddress();
        if (_amount == 0) revert AmountMustBeGreaterThanZero();

        uint256 newBalance = balanceOf(_to) + _amount;
        if (newBalance > totalSupply()) {
            revert TotalSupplyExceeded(newBalance, totalSupply());
        }

        _mint(_to, _amount);

        return true;
    }

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);

        if (balance < _amount) revert InsufficientBalance(balance, _amount);

        uint256 remaining = balance - _amount;
        if (remaining != 0) revert BalanceMustBeZero(remaining);

        super.burn(_amount);
    }
}
