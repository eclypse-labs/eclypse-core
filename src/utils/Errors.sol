pragma solidity ^0.8.0;

library Errors {
    error ZeroAddress();
    error InsufficientBalance(uint256 balance, uint256 amount);
    error InsufficientAllowance(uint256 allowance, uint256 amount);
    error InsufficientSupply(uint256 supply, uint256 amount);
    error InsufficientTotalSupply(uint256 totalSupply, uint256 amount);
}
