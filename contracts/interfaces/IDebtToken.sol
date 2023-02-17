//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IGhoVariableDebtToken} from "gho-core/src/contracts/facilitators/aave/tokens/interfaces/IGhoVariableDebtToken.sol";

interface IDebtToken is IGhoVariableDebtToken {
    // Events
    event Mint(address indexed to, uint256 amount);

    event Burn(address indexed from, uint256 amount);

    event BorrowLimitChanged(uint256 newBorrowLimit);

    // Functions
    function mint(address to, uint256 amount) external;

    function burn(uint256 amount) external;

    function getBorrowLimit() external view returns (uint256);

    function setBorrowLimit(uint256 newBorrowLimit) external;

    function decreaseBalanceFromInterest(address user, uint256 amount) external;

    function getBalanceFromInterest(user) external view returns (uint256);
}
