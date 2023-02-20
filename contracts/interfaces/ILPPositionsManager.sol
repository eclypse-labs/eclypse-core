// SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

// Common interface for the Trove Manager.
interface ILPPositionsManager {
    // --- Events ---
    event TokenAddedToPool(address _token, address _pool);

    event PositionStatusChanged(uint256 _tokenId, Status status);
    event DepositedLP(address _user, uint256 _tokenId);
    event IncreasedDebt(
        address _user,
        uint256 _tokenId,
        uint256 _oldAmount,
        uint256 _newAmount
        );
    event DecreasedDebt(
        address _user,
        uint256 _tokenId,
        uint256 _oldAmount,
        uint256 _newAmount
    );

    // List of all of the LPPositionsManager's events

    event GHOTokenAddressChanged(address _newGHOTokenAddress);
    event ActivePoolAddressChanged(address _activePoolAddress);
    event BorrowerOperationsAddressChanged(address _newBorrowerOperationsAddress);

    // event StabilityPoolAddressChanged(address _stabilityPoolAddress);
    // event GasPoolAddressChanged(address _gasPoolAddress);

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
        uint256 debt;
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

    struct BorrowData {
        uint256 amount;
        uint256 mintedAmount;
        uint256 timestamp;
        uint256 interestRate;
    }

    // --- Functions ---

    function setAddresses(
        address _borrowerOperationsAddress,
        address _activePoolAddress,
        address _GHOTokenAddress
        //address _stabilityPoolAddress,
        //address _gasPoolAddress,
    ) external;

    function addPairToProtocol(
        address _poolAddress,
        address _token0,
        address _token1,
        address _ETHpoolToken0,
        address _ETHpoolToken1,
        bool _inv0,
        bool _inv1
    ) external;

    function changePositionStatus(uint256 _tokenId, Status status) external;

    function openPosition(address _owner, uint256 _tokenId) external;

    function getPosition(uint256 _tokenId)
        external
        view
        returns (Position memory position);

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

    function debtOf(uint256 _tokenId) external returns (uint256);

    function debtOfInETH(uint256 _tokenId) external returns (uint256);

    function totalDebtOf(address _user)
        external
        returns (uint256 totalDebtInGHO);

    //function increaseDebtOf(uint256 _tokenId, uint256 _amount, uint256 _tokenId) external;

    // function decreaseDebtOf(uint256 _tokenId, uint256 _amount)
    //     external returns (uint256);

    function setNewLiquidity(uint256 _tokenId, uint128 _liquidity) external;

    function liquidatable(uint256 _tokenId) external returns (bool);

    function priceInETH(address tokenAddress) external returns (uint256);

    function liquidatePosition(uint256 _tokenId, uint256 _GHOToRepay)
        external
        returns (bool);

    function liquidateUnderlyings(uint256 _tokenId, uint256 _GHOToRepay)
        external
        returns (bool);

    function batchliquidate(
        uint256[] memory _tokenIds,
        uint256[] memory _GHOToRepay
    ) external;
}

