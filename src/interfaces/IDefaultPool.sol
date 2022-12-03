// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

import "./IPool.sol";


interface IDefaultPool is IPool {
    // --- Events ---
    event TroveManagerAddressChanged(address _newTroveManagerAddress);
    event DefaultPoolGHODebtUpdated(uint _GHODebt);
    event DefaultPoolETHBalanceUpdated(uint _ETH);

    // --- Functions ---
    function sendETHToActivePool(uint _amount) external;
}
