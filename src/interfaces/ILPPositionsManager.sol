// SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

import "./IEclypseBase.sol";
import "./IStabilityPool.sol";
import "./IGHOToken.sol";

// Common interface for the Trove Manager.
interface ILPPositionsManager is IEclypseBase {
    // --- Events ---
    event TokenAddedToPool(address _token, address _pool, uint256 _time);
    event DepositedLP(address _user, uint256 _tokenId, uint256 _time);
    event IncreasedDebt(
        address _user,
        uint256 _tokenId,
        uint256 _oldAmount,
        uint256 _newAmount,
        uint256 _time
    );
    event DecreasedDebt(
        address _user,
        uint256 _tokenId,
        uint256 _oldAmount,
        uint256 _newAmount,
        uint256 _time
    );

    //Possible status a position can have.
    enum Status {
        nonExistent,
        active,
        closedByOwner,
        closedByLiquidation,
        closedByRedemption
    }

    //The structure of a position.
    struct Position {
        address user;
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        address poolAddress;
        uint256 tokenId;
        Status status;
        uint256 debt;
    }

    // --- Functions ---

    function setAddresses(
        address _borrowerOperationsAddress,
        address _activePoolAddress,
        //address _stabilityPoolAddress,
        //address _gasPoolAddress,
        address _GHOTokenAddress
    ) external;

    function _requirePositionIsActive(uint256 _tokenId) external view;

    function addPairToProtocol(address _poolAddress, address _token0, address _token1, address _ETHpoolToken0, address _ETHpoolToken1, bool _inv0, bool _inv1) external;

    function getPositionStatus(uint256 _tokenId)
        external
        view
        returns (Status status);

    function changePositionStatus(uint256 _tokenId, Status status) external;

    function openPosition(address _owner, uint256 _tokenId) external;

    function getPosition(uint256 _tokenId)
        external
        view
        returns (Position memory position);

    function computePositionAmounts(Position memory _position)
        external
        view
        returns (uint256 amountToken0, uint256 amountToken1);

    function positionAmounts(uint256 _tokenId)
        external
        view
        returns (uint256 amountToken0, uint256 amountToken1);

    function positionValueInETH(uint256 _tokenId)
        external
        view
        returns (uint256 value);

    function totalPositionsValueInETH(address _user)
        external
        view
        returns (uint256 totalValue);

    function debtOf(uint256 _tokenId) external view returns (uint256);

    function debtOfInETH(uint256 _tokenId) external view returns (uint256);

    function totalDebtOf(address _user)
        external
        view
        returns (uint256 totalDebtInGHO);

    function increaseDebtOf(uint256 _tokenId, uint256 _amount) external;

    function decreaseDebtOf(uint256 _tokenId, uint256 _amount) external;

    function setNewLiquidity(uint256 tokenId, uint128 liquidity) external;

    function liquidatable(uint256 _tokenId) external returns (bool);

    function priceInETH(address tokenAddress) external returns (uint256);

    function liquidate(uint256 _tokenId, uint256 _GHOToRepay)
        external
        returns (bool);

    function batchLiquidate(
        uint256[] memory _tokenIds,
        uint256[] memory _GHOToRepay
    ) external;
}
