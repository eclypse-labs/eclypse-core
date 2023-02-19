//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from '@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20.sol';

interface IDebtToken is IERC20 {
    // Events
    event Mint(address indexed to, uint256 amount);

    event Burn(address indexed from, uint256 amount);

    event BorrowLimitChanged(uint256 newBorrowLimit);

    // Functions
    function mint(uint256 amount) external;

    function burn(uint256 amount) external;

    function getBorrowLimit() external view returns (uint256);

    function setBorrowLimit(uint256 newBorrowLimit) external;
}
