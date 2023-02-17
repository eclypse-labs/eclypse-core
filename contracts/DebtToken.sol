//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./interfaces/IDebtToken.sol" as IDebtToken;

contract DebtToken is IDebtToken {
    event Mint(address indexed to, uint256 amount);
    event Burn(address indexed from, uint256 amount);
    event BorrowLimitChanged(uint256 newBorrowLimit);
}
