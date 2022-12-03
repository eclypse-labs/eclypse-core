//SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "../src/GHOToken.sol";
import "../src/BorrowerOperations.sol";
import "../src/ActivePool.sol";
import "../src/LPPositionsManager.sol";
import "@uniswap-core/interfaces/IUniswapV3Factory.sol";
import "@uniswap-core/interfaces/IUniswapV3Pool.sol";
import "@uniswap-periphery/interfaces/INonfungiblePositionManager.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";

contract LPPositionsManagerTest is Test {
    using SafeMath for uint256;
    address deployer = makeAddr("deployer");
    address leFrero = 0x7E65EB2b4C8fb39aBD40289756Db40dFC2252313;
    address oracleLiquidityDepositor = makeAddr("oracleLiquidityDepositor");
    address user = makeAddr("user");

    address public constant wethAddr =
        0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant usdcAddr =
        0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant uniPoolUsdcETHAddr =
        0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640;

    IERC20 WETH = IERC20(wethAddr);
    IERC20 USDC = IERC20(usdcAddr);

    IUniswapV3Factory uniswapFactory =
        IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    IUniswapV3Pool uniPoolUsdcETH = IUniswapV3Pool(uniPoolUsdcETHAddr);

    INonfungiblePositionManager uniswapPositionsNFT =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

    GHOToken GHO;
    LPPositionsManager positionsManager;
    BorrowerOperations borrowerOperations;
    ActivePool activePool;
    IUniswapV3Pool uniPoolGhoEth;

    function setUp() public {
        vm.label(usdcAddr, "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48");
        vm.label(wethAddr, "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2");
        vm.createSelectFork(
            "https://eth-mainnet.g.alchemy.com/v2/nlV0EOb56btXprhPYONYhqtn7TMEmQFb"
        );
        vm.deal(deployer, 10 ether);
        vm.startPrank(deployer);
        // deploy everything
        borrowerOperations = new BorrowerOperations();
        positionsManager = new LPPositionsManager();
        activePool = new ActivePool();
        // address stabilityPoolAddress;
        // address gasPoolAddress;
        //GHO = new GHOToken(address(borrowerOperations));
        // Set addresses for everything
        borrowerOperations.setAddresses(
            address(positionsManager),
            address(activePool),
            //_stabilityPoolAddress,
            //_gasPoolAddress,
            address(GHO)
        );
        positionsManager.setAddresses(
            address(borrowerOperations),
            address(activePool),
            //_stabilityPoolAddress,
            //_gasPoolAddress,
            address(GHO)
        );
        activePool.setAddresses(
            address(positionsManager),
            address(activePool),
            //_stabilityPoolAddress,
            //_gasPoolAddress,
            address(GHO)
        );
        vm.stopPrank();
    }

    function testRiskConstantsAreCorrectlyUpdated() public {
        console.log("initial risk constant: ", positionsManager.getRiskConstants(address(uniPoolUsdcETH)));
        uint256 _minCR = Math.mulDiv(17, 1 << 96, 10);
        console.log("minCR calculated: ", _minCR);
        positionsManager.updateRiskConstants(address(uniPoolUsdcETH), _minCR);
        console.log("updated risk constant: " ,positionsManager.getRiskConstants(address(uniPoolUsdcETH)));
        assertEq(positionsManager.getRiskConstants(address(uniPoolUsdcETH)), _minCR, "risk constants are not updated correctly");
    }

    function testDepositCollateralFromBorrowerOperations() public {
        //deploy une pool GHO/ETH
        //console.log("uniPoolGhoEth", address(uniPoolGhoEth));

        positionsManager.addTokenETHpoolAddress(
            usdcAddr,
            uniPoolUsdcETHAddr,
            false
        );

        uint256 positionWethUsdcID = uniswapPositionsNFT.tokenOfOwnerByIndex(
            leFrero,
            4
        );
        console.log("tokenId: ", positionWethUsdcID);
        (
            ,
            ,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            ,
            ,
            ,

        ) = uniswapPositionsNFT.positions(positionWethUsdcID);

        //console.log(liquidity);
        vm.startPrank(leFrero);
        uniswapPositionsNFT.approve(
            address(borrowerOperations),
            positionWethUsdcID
        );

        borrowerOperations.openPosition(positionWethUsdcID);

        borrowerOperations.borrowGHO(1, positionWethUsdcID);

        //console.log(positionsManager.debtOf(positionWethUsdcID));
        vm.stopPrank();

        /*assert(
            positionsManager.getLiquidityAmount(leFrero) == liquidity,
            "liquidity amount should be equal"
        );*/

        //console.log(uniswapPositionsNFT.balanceOf(leFrero));
    }
}

//     uint24 fee = 100;
//         uniPoolGhoEth = IUniswapV3Pool(
//             uniswapFactory.createPool(address(GHO), address(WETH), fee)
//         );
//         vm.startPrank(oracleLiquidityDepositor);
//         //giving depositor 10 ETH
//         vm.deal(oracleLiquidityDepositor, 10 ether);
//         //giving depositor 10 WETH
//         deal(address(WETH), oracleLiquidityDepositor, 10 ether);
//         //giving depositor 10 GHO
//         deal(address(GHO), oracleLiquidityDepositor, 10000 ether);
//         //deposit de la liquidité pour l'oracle
//         uint128 amount = 1000;
//         bytes memory data;
//         uniPoolGhoEth.mint(
//             oracleLiquidityDepositor,
//             -69082,
//             -73136,
//             amount,
//             data
//         );
//         vm.stopPrank();
//         //trouver l'addresse de univ3 pool ETH/USDC : https://info.uniswap.org/#/pools/0x88e6a0c2ddd26feeb64f039a2c41296fcb3f5640
//         vm.startPrank(deployer);
//         //whitelist la pool: updateRiskConstants
//         uint256 _minCR = 0;
//         positionsManager.updateRiskConstants(address(uniPoolUsdcETH), _minCR);
//         //pour l'oracle ajouter la pool ETH/GHO: addTokenETHpoolAddress
//         bool _inv = false; //TODO: set parameter _inv
//         positionsManager.addTokenETHpoolAddress(
//             address(USDC),
//             address(uniPoolGhoEth),
//             _inv
//         );
//         vm.stopPrank();*/
//     }

//     //TODO: test deposit
//     function testDeposit() public {
//         uint256 _tokenId;
//         uint256 collateralRatio;

//         INonfungiblePositionManager.MintParams
//             memory mintParams = INonfungiblePositionManager.MintParams({
//                 token0: wethAddr,
//                 token1: usdcAddr,
//                 fee: 0,
//                 tickLower: int24(69082),
//                 tickUpper: int24(73136),
//                 amount0Desired: 1 ether,
//                 amount1Desired: 5000 ether,
//                 amount0Min: 0,
//                 amount1Min: 0,
//                 recipient: address(this),
//                 deadline: 0
//             });

//         //We set the token identifier for the given position
//         (_tokenId, , , ) = uniswapPositionsNFT.mint(mintParams);
//         //we compute the colaterl ratio of the opened position
//         borrowerOperations.openPosition(_tokenId);
//         collateralRatio = positionsManager.computeCR(_tokenId);
//         //we verifity that the position is not undercollateralized.
//         assertTrue(collateralRatio > 1, "the position is undercollateralized");

//         vm.stopPrank();
//     }

//     //TODO: test deposit + withdraw

//     function testDepositAndWithdraw() public {
//         uint256 _tokenId;

//         INonfungiblePositionManager.MintParams
//             memory mintParams = INonfungiblePositionManager.MintParams({
//                 token0: wethAddr,
//                 token1: usdcAddr,
//                 fee: 0,
//                 tickLower: int24(69082),
//                 tickUpper: int24(73136),
//                 amount0Desired: 1 ether,
//                 amount1Desired: 5000 ether,
//                 amount0Min: 0,
//                 amount1Min: 0,
//                 recipient: address(this),
//                 deadline: block.timestamp
//             });

//         (_tokenId, , , ) = uniswapPositionsNFT.mint(mintParams);
//     }

//     //TODO: test deposit + borrow + check health factor

//     //TODO: test deposit + borrow + can't withdraw if it would liquidate the position

//     //TODO: test liquidation (change oracle price)

//     function testNumberIs42() public {}

//     function testFailSubtract43() public {}
// }
