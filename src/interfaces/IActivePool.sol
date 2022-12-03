// SPDX-License-Identifier: MIT

pragma solidity >=0.6.11;

import "./IPool.sol";

interface IActivePool is IPool {
    // --- Events ---
    //event BorrowerOperationsAddressChanged(address _newBorrowerOperationsAddress);
    //event TroveManagerAddressChanged(address _newTroveManagerAddress);
    //event ActivePoolGHODebtUpdated(uint _GHODebt);
    //event ActivePoolCollateralBalanceUpdated(uint _collateralValue);

    // --- Functions ---
    function sendLp(address _account, uint256 _tokenId) external;
    
    function increaseGHODebt(uint256 _amount) external;
    function decreaseGHODebt(uint256 _amount) external;
    
    function increaseLiquidity(
        uint256 tokenId,
        uint256 amountAdd0,
        uint256 amountAdd1
    )
        external
        returns (
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        );

    function removeLiquidity(uint256 _tokenId, uint128 _liquidityToRemove)
        external
        returns (uint256 amount0, uint256 amount1);
}
