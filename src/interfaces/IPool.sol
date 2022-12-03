// SPDX-License-Identifier: MIT

pragma solidity >=0.6.11;

// Common interface for the Pools.
interface IPool {
    
    // --- Events ---
    
    event ETHBalanceUpdated(uint _newBalance);
    event GHOBalanceUpdated(uint _newBalance);
    event ActivePoolAddressChanged(address _newActivePoolAddress);
    event DefaultPoolAddressChanged(address _newDefaultPoolAddress);
    event StabilityPoolAddressChanged(address _newStabilityPoolAddress);
    event LpSent(address _to, uint256 _tokenId);

    // --- Functions ---
    
    function getCollateralValue() external view returns (uint);

    function getGHODebt() external view returns (uint);

    function increaseGHODebt(uint _amount) external;

    function decreaseGHODebt(uint _amount) external;
}
