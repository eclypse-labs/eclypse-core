// SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

// Common interface for the Trove Manager.
interface IBorrowerOperations {
    // --- Events ---

    event LPPositionsManagerAddressChanged(address _newLPPositionsManagerAddress);
    event ActivePoolAddressChanged(address _activePoolAddress);
    event GHOTokenAddressChanged(address _GHOTokenAddress);

    event OpenedPosition(address _borrower, uint256 _tokenId);
    event ClosedPosition(address _borrower, uint256 _tokenId);

    event WithdrawnGHO(address _borrower, uint256 _GHOAmount, uint256 _tokenId);
    event RepaidGHO(address _borrower, uint256 _GHOAmount, uint256 _tokenId);

    event AddedCollateral(uint256 _tokenId, uint128 _liquidity, uint256 _amountAdd0, uint256 _amountAdd1);

    event RemovedCollateral(uint256 _tokenId, uint128 _liquidity, uint256 _amount0, uint256 _amount1);

    // --- Functions ---

    function setAddresses(address _lpPositionsManagerAddress, address _activePoolAddress, address _GHOTokenAddress)
        external;

    function openPosition(uint256 _tokenId) external;

    function closePosition(uint256 _tokenId) external;

    function borrowGHO(uint256 _GHOAmount, uint256 _tokenId) external payable;

    function repayGHO(uint256 _GHOAmount, uint256 _tokenId) external;

    function addCollateral(uint256 _tokenId, uint256 _amountAdd0, uint256 _amountAdd1)
        external
        returns (uint128 liquidity, uint256 amount0, uint256 amount1);

    function removeCollateral(uint256 _tokenId, uint128 _liquidityToRemove)
        external
        returns (uint256 amount0, uint256 amount1);
}
