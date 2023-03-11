// SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

import "./IActivePool.sol";
import "./IBorrowerOperations.sol";
import "./IStableCoin.sol";

import "@uniswap-core/interfaces/IUniswapV3Factory.sol";
import "@uniswap-periphery/interfaces/INonfungiblePositionManager.sol";

// Common interface for the Trove Manager.
interface ILPPositionsManager {
    // --- Events ---
    event TokenAddedToPool(address _token, address _pool);

    event PositionStatusChanged(uint256 _tokenId, Status status);
    event IncreasedDebt(address _user, uint256 _tokenId, uint256 _oldAmount, uint256 _newAmount);
    event DecreasedDebt(address _user, uint256 _tokenId, uint256 _oldAmount, uint256 _newAmount);

    event LiquidityIncreased(uint256 _tokenId, uint128 liquidity);
    event LiquidityDecreased(uint256 _tokenId, uint128 liquidity);
    
    event StableCoinAddressChanged(address _newStableCoinAddress);
    event ActivePoolAddressChanged(address _activePoolAddress);
    event BorrowerOperationsAddressChanged(address _newBorrowerOperationsAddress);

    //Possible status a position can have.
    enum Status {
        nonExistent,
        active,
        closedByOwner,
        closedByLiquidation
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

    struct ProtocolValues {
        uint256 interestRate;
        uint256 totalBorrowedStableCoin;
        uint256 interestFactor;
        uint256 lastFactorUpdate;
        uint32 twapLength;
    }

    struct ProtocolContracts {
        IStableCoin stableCoin;
        IActivePool activePool;
        IUniswapV3Factory uniswapFactory;
        INonfungiblePositionManager uniswapPositionsManager;
        address borrowerOperationsAddr;
    }

    // --- Functions ---

    function setAddresses(
        address _uniFactory,
        address _uniPosNFT,
        address _StableCoinAddr,
        address _borrowerOpAddr,
        address _activePoolAddr
    ) external;

    function addPoolToProtocol(
        address _poolAddress,
        address _token0,
        address _token1,
        address _ETHpoolToken0,
        address _ETHpoolToken1,
        bool _inv0,
        bool _inv1
    ) external;

    // Position functions
    function openPosition(address _owner, uint256 _tokenId) external;
    function closePosition(address _owner, uint256 _tokenId) external;
    function getPosition(uint256 _tokenId) external view returns (Position memory position);
    function positionAmounts(uint256 _tokenId) external view returns (uint256 amountToken0, uint256 amountToken1);
    function positionValueInETH(uint256 _tokenId) external view returns (uint256 value);
    function totalPositionsValueInETH(address _user) external view returns (uint256 totalValue);

    // Debt functions
    function debtOf(uint256 _tokenId) external returns (uint256);
    function debtOfInETH(uint256 _tokenId) external returns (uint256);
    function totalDebtOf(address _user) external returns (uint256 totalDebtInStableCoin);
    function borrow(address sender, uint256 _tokenId, uint256 _amount) external;
    function repay(address sender, uint256 _tokenId, uint256 _amount) external;

    // LP functions
    function increaseLiquidity(address sender, uint256 _tokenId, uint256 amountAdd0, uint256 amountAdd1)
        external
        returns (uint128 liquidity, uint256 amount0, uint256 amount1);
    function decreaseLiquidity(address sender, uint256 _tokenId, uint128 _liquidityToRemove)
        external
        returns (uint256 amount0, uint256 amount1);

    // Price functions [TODO: move to a separate contract]
    function priceInETH(address tokenAddress) external returns (uint256);

    // Liquidation functions
    function liquidatable(uint256 _tokenId) external returns (bool);
    function liquidatePosition(uint256 _tokenId, uint256 _StableCoinToRepay) external returns (bool);
    function liquidateUnderlyings(uint256 _tokenId, uint256 _StableCoinToRepay) external returns (bool);
    function batchliquidate(uint256[] memory _tokenIds, uint256[] memory _StableCoinToRepay) external;
}
