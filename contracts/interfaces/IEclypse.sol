// SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

import "@uniswap-periphery/interfaces/INonfungiblePositionManager.sol";

// Common interface for the Trove Manager.
interface IEclypse {
    //Possible status a position can have.
    enum Status {
        nonExistent,
        active,
        closedByOwner,
        closedByLiquidation
    }

    struct ProtocolValues {
        uint256 interestRate;
        uint256 totalBorrowedGho;
        uint256 interestFactor;
        uint256 lastFactorUpdate;
        uint32 twapLength;
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
        uint256 debtPrincipal;
        uint256 interestConstant;
    }

    // The pool's data
    struct RiskConstants {
        uint256 minCR; // Minimum collateral ratio
    }

    struct PoolPricingInfo {
        address poolAddress;
        bool inv; // true if and only if WETH is token0 of the pool.
    }

    // --- Events ---
    event TokenAddedToPool(address _token, address _pool);
    event PositionStatusChanged(uint256 _tokenId, Status status);
    event DepositedLP(address _user, uint256 _tokenId);
    event IncreasedDebt(address _user, uint256 _tokenId, uint256 _oldAmount, uint256 _newAmount);
    event DecreasedDebt(address _user, uint256 _tokenId, uint256 _oldAmount, uint256 _newAmount);

    event PositionMinted(uint256 _tokenId);
    event PositionBurned(uint256 _tokenId);
    event LiquidityIncreased(uint256 _tokenId, uint128 liquidity);
    event LiquidityDecreased(uint256 _tokenId, uint128 liquidity);
    event MintedSupplyUpdated(uint256 _mintedSupply);
    event InterestRepaid(address _sender, uint256 _amount);
    event PositionSent(address _account, uint256 _tokenId);
    event TokenSent(address _token, address _account, uint256 _amount);

    function addPairToProtocol(
        address _poolAddress,
        address _token0,
        address _token1,
        address _ETHpoolToken0,
        address _ETHpoolToken1,
        bool _inv0,
        bool _inv1
    ) external;
    function getPosition(uint256 _tokenId) external view returns (Position memory position);
    function getPositionsCount() external view returns (uint256);

    function openPosition(address _owner, uint256 _tokenId) external;
    function closePosition(address _owner, uint256 _tokenId) external;

    function positionAmounts(uint256 _tokenId) external view returns (uint256 amountToken0, uint256 amountToken1);

    function debtOf(uint256 _tokenId) external view returns (uint256 currentDebt);
    function totalDebtOf(address _user) external view returns (uint256 totalDebtInGHO);
    function borrowGHO(address sender, uint256 _tokenId, uint256 _amount) external;
    function repayGHO(address sender, uint256 _tokenId, uint256 _amount) external;

    function priceInETH(address _tokenAddress) external view returns (uint256 priceX96);
    function debtOfInETH(uint256 _tokenId) external view returns (uint256);
    function positionValueInETH(uint256 _tokenId) external view returns (uint256 value);
    function totalPositionsValueInETH(address _user) external view returns (uint256 totalValue);

    function collRatioOf(uint256 _tokenId) external returns (uint256);
    function getRiskConstants(address _pool) external view returns (uint256 riskConstants);
    function updateRiskConstants(address _pool, uint256 _riskConstants) external;

    function increaseLiquidity(address sender, uint256 _tokenId, uint256 amountAdd0, uint256 amountAdd1)
        external
        returns (uint128 liquidity, uint256 amount0, uint256 amount1);
    function decreaseLiquidity(uint256 _tokenId, uint128 _liquidityToRemove, address sender)
        external
        returns (uint256 amount0, uint256 amount1);
    function sendPosition(address _account, uint256 _tokenId) external;
}
