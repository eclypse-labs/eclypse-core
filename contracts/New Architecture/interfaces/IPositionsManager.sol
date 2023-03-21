// SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

import "./IEclypseVault.sol";
import "@uniswap-core/interfaces/IUniswapV3Factory.sol";
import "@uniswap-periphery/interfaces/INonfungiblePositionManager.sol";
import "./IPriceFeed.sol";

interface IPositionsManager {

    enum Status {
        nonExistent,
        active,
        closedByOwner,
        closedByLiquidation
    }

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
        address _assetAddress;
    }

    struct ProtocolContracts {
        address userInteractions;
        IEclypseVault eclypseVault;
        IUniswapV3Factory uniswapFactory;
        INonfungiblePositionManager uniswapPositionsManager;
        IPriceFeed priceFeed;
    }

    struct AssetsValues {
        uint256 interestRate;
        uint256 totalBorrowedStableCoin;
        uint256 interestFactor;
        uint256 lastFactorUpdate;
        uint32 twapLength;
    }

    struct PoolPricingInfo {
        address poolAddress;
        bool inv; // True iff WETH is token0 of the pool.
    }
    
    struct RiskConstants {
        uint256 minCR; // Minimum collateral ratio
    }

    struct UserPositions {
        uint256 counter;
        mapping(uint256 => Positions) positions;
    }

    function initialize(
        address _uniFactory,
        address _uniPosNFT,
        address _StableCoinAddress,
        address _userInteractionsAddress,
        address _eclypseVaultAddress,
        address _priceFeedAddress
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
    function totalDebtOf(address _user) external returns (uint256 totalDebtInStableCoin);
    function debtOfInETH(uint256 _tokenId) external returns (uint256);
    
    function borrow(address sender, uint256 _tokenId, uint256 _amount) external;
    function repay(address sender, uint256 _tokenId, uint256 _amount) external;
    
    // LP functions
    function deposit(address _sender, uint256 _tokenId, uint256 _amountAdd0, uint256 _amountAdd1)
        external
        returns (uint128 liquidity, uint256 amount0, uint256 amount1);
    function withdraw(address _sender, uint256 _tokenId, uint128 _liquidityToRemove)
        external
        returns (uint256 amount0, uint256 amount1);

    // Price functions
    //TODO: Rewrite method when PriceFeed contract is done.
    function priceInETH(address _tokenAddress) external returns (uint256);


    // Liquidation functions
    function liquidatable(uint256 _tokenId) external returns (bool);
    function liquidatePosition(uint256 _tokenId, uint256 _StableCoinToRepay) external;
    function liquidateUnderlyings(uint256 _tokenId, uint256 _StableCoinToRepay) external;
    function batchliquidate(uint256[] memory _tokenIds, uint256[] memory _StableCoinToRepay) external;
}