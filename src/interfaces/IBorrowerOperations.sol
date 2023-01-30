// SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

import "./IEclypseBase.sol";
import "./IStabilityPool.sol";
import "./IGHOToken.sol";

// Common interface for the Trove Manager.
interface IBorrowerOperations {
    // --- Events ---

    event LPPositionsManagerAddressChanged(
        address _newLPPositionsManagerAddress
    );
    event ActivePoolAddressChanged(address _activePoolAddress);
    event StabilityPoolAddressChanged(address _stabilityPoolAddress);
    event GasPoolAddressChanged(address _gasPoolAddress);
    event GHOTokenAddressChanged(address _GHOTokenAddress);

    event WithdrawnGHO(address _borrower, uint256 _GHOAmount, uint256 _tokenId, uint256 _time);
    event RepaidGHO(address _borrower, uint256 _GHOAmount, uint256 _tokenId, uint256 _time);

    // --- Functions ---

    function setAddresses(
        address _lpPositionsManagerAddress,
        address _activePoolAddress,
       // address _stabilityPoolAddress,
       // address _gasPoolAddress,
        address _GHOTokenAddress
    ) external;

    function openPosition(uint256 _tokenId) external;

    function closePosition(uint256 _tokenId) external;

    function borrowGHO(uint256 _GHOAmount, uint256 _tokenId) external payable;

    function repayGHO(uint256 _GHOAmount, uint256 _tokenId) external;

    function addCollateral(
        uint256 _tokenId,
        uint256 _amountAdd0,
        uint256 _amountAdd1
    )
        external
        returns (
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        );

    function addCollateralWithLockedTokens(
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

    function removeCollateralToUser(uint256 _tokenId, uint128 _liquidityToRemove)
        external
        returns (uint256 amount0, uint256 amount1);
    
    function removeCollateralToProtocol(uint256 _tokenId, uint128 _liquidityToRemove)
        external
        returns (uint256 amount0, uint256 amount1);
}