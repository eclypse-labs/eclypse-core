//SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "forge-std/Test.sol";
import "../src/ActivePool.sol";
import "./ERC20Mintable.sol";
import "forge-std/Test.sol";
import "../src/GHOToken.sol";
import "../src/BorrowerOperations.sol";
import "../src/ActivePool.sol";
import "../src/LPPositionsManager.sol";
import "@uniswap-core/interfaces/IUniswapV3Factory.sol";
import "@uniswap-core/interfaces/IUniswapV3Pool.sol";
import "@uniswap-core/libraries/FixedPoint96.sol";
import "@uniswap-periphery/interfaces/INonfungiblePositionManager.sol";
import "@uniswap-periphery/interfaces/ISwapRouter.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";

contract CompleteTest is Test {

    IGHOToken ghoToken;

    uint256 constant TOKEN18 = 10**18;
    uint256 constant TOKEN6 = 10**6;

    address deployer = makeAddr("deployer");
    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");
    address user3 = makeAddr("user3");
    address user4 = makeAddr("user4");
    address user5 = makeAddr("user5");


    uint256 user1_tokenId0;
    uint256 user1_tokenId1;
    uint256 user1_tokenId2;
    uint256 user1_tokenId3;

    uint256 user2_tokenId1;
    uint256 user2_tokenId2;
    uint256 user2_tokenId3;

    uint256 user3_tokenId1;
    uint256 user3_tokenId2;
    uint256 user3_tokenId3;

    uint256 user4_tokenId1;
    uint256 user4_tokenId2;
    uint256 user4_tokenId3;

    uint256 user5_tokenId1;
    uint256 user5_tokenId2;
    uint256 user5_tokenId3;

    address public constant wethAddr =
        0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant usdcAddr =
        0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    address public constant uniPoolUsdcETHAddr =
        0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640;
    address public constant swapRouterAddr =
        0xE592427A0AEce92De3Edee1F18E0157C05861564;

    IERC20 WETH = IERC20(wethAddr);
    IERC20 USDC = IERC20(usdcAddr);


    ActivePool activePool;
    BorrowerOperations borrowerOperation;
    LPPositionsManager lpPositionsManager;
    INonfungiblePositionManager uniswapPositionsNFT;
    ISwapRouter swapRouter;
    IUniswapV3Pool PoolWETH_USDC;
    IUniswapV3Pool PoolGHO_WETH;

    IUniswapV3Factory uniswapFactory =
        IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);

    function convertQ96(uint256 x) public returns (uint256){
        return FullMath.mulDiv(x, 1, 2**96);
    }

    function convertDecimals18(uint256 x) public returns (uint256){
        return FullMath.mulDiv(x, 1, 10**18);
    }

    function convertDecimals6(uint256 x) public returns (uint256){
        return FullMath.mulDiv(x, 1, 10**6);
    }

    function setUp() public {
        vm.startPrank(deployer);

        uniswapPositionsNFT = INonfungiblePositionManager(
            0xC36442b4a4522E871399CD717aBDD847Ab11FE88
        );

        swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

        PoolWETH_USDC = IUniswapV3Pool(uniPoolUsdcETHAddr);

        activePool = new ActivePool();
        borrowerOperation = new BorrowerOperations();
        lpPositionsManager = new LPPositionsManager();

        ghoToken = new GHOToken(
            address(borrowerOperation),
            address(lpPositionsManager)
        );

        borrowerOperation.setAddresses(
            address(lpPositionsManager),
            address(activePool),
            address(ghoToken)
        );
        lpPositionsManager.setAddresses(
            address(borrowerOperation),
            address(activePool),
            address(ghoToken)
        );
        activePool.setAddresses(
            address(borrowerOperation),
            address(lpPositionsManager)
        );

        lpPositionsManager.addPairToProtocol(
            uniPoolUsdcETHAddr,
            usdcAddr,
            wethAddr,
            uniPoolUsdcETHAddr,
            address(0),
            false,
            true
        );

        vm.stopPrank();

        vm.startPrank(user1);
        deal(usdcAddr, user1, 100_000_000_000 * TOKEN6); //100Md $
        deal(wethAddr, user1, 100_000 ether); //100K ETH

        USDC.approve(address(uniswapPositionsNFT), 100_000_000_000 * TOKEN6);
        WETH.approve(address(uniswapPositionsNFT), 100_000 ether);


        (user1_tokenId0, , , ) = uniswapPositionsNFT.mint(); //Pair not approved by protocole.
        (user1_tokenId1, , , ) = uniswapPositionsNFT.mint();
        (user1_tokenId2, , , ) = uniswapPositionsNFT.mint();
        (user1_tokenId3, , , ) = uniswapPositionsNFT.mint();

        uniswapPositionsNFT.approve(
            address(borrowerOperation),
            user1_tokenId1
        );

        uniswapPositionsNFT.approve(
            address(borrowerOperation),
            user1_tokenId2
        );

        uniswapPositionsNFT.approve(
            address(borrowerOperation),
            user1_tokenId3
        );

        borrowerOperation.openPosition(user1_tokenId1);
        borrowerOperation.openPosition(user1_tokenId2);
        borrowerOperation.openPosition(user1_tokenId3);

        vm.stopPrank();

        vm.startPrank(user2);

        deal(usdcAddr, user2, 100_000_000_000 * TOKEN6); //100Md $
        deal(wethAddr, user2, 100_000 ether); //100K ETH

        USDC.approve(address(uniswapPositionsNFT), 100_000_000_000 * TOKEN6);
        WETH.approve(address(uniswapPositionsNFT), 100_000 ether);

        (user2_tokenId1, , , ) = uniswapPositionsNFT.mint();
        (user2_tokenId2, , , ) = uniswapPositionsNFT.mint();
        (user2_tokenId3, , , ) = uniswapPositionsNFT.mint();

        uniswapPositionsNFT.approve(
            address(borrowerOperation),
            user2_tokenId1
        );

        uniswapPositionsNFT.approve(
            address(borrowerOperation),
            user2_tokenId2
        );

        uniswapPositionsNFT.approve(
            address(borrowerOperation),
            user2_tokenId3
        );

        borrowerOperation.openPosition(user2_tokenId1);
        borrowerOperation.openPosition(user2_tokenId2);
        borrowerOperation.openPosition(user2_tokenId3);

        vm.stopPrank();

        vm.startPrank(user3);

        deal(usdcAddr, user3, 100_000_000_000 * TOKEN6); //100Md $
        deal(wethAddr, user3, 100_000 ether); //100K ETH

        USDC.approve(address(uniswapPositionsNFT), 100_000_000_000 * TOKEN6);
        WETH.approve(address(uniswapPositionsNFT), 100_000 ether);

        (user3_tokenId1, , , ) = uniswapPositionsNFT.mint();
        (user3_tokenId2, , , ) = uniswapPositionsNFT.mint();
        (user3_tokenId3, , , ) = uniswapPositionsNFT.mint();

        uniswapPositionsNFT.approve(
            address(borrowerOperation),
            user3_tokenId1
        );

        uniswapPositionsNFT.approve(
            address(borrowerOperation),
            user3_tokenId2
        );

        uniswapPositionsNFT.approve(
            address(borrowerOperation),
            user3_tokenId3
        );

        borrowerOperation.openPosition(user3_tokenId1);
        borrowerOperation.openPosition(user3_tokenId2);
        borrowerOperation.openPosition(user3_tokenId3);

        vm.stopPrank();

        vm.startPrank(user4);

        deal(usdcAddr, user4, 100_000_000_000 * TOKEN6); //100Md $
        deal(wethAddr, user4, 100_000 ether); //100K ETH

        USDC.approve(address(uniswapPositionsNFT), 100_000_000_000 * TOKEN6);
        WETH.approve(address(uniswapPositionsNFT), 100_000 ether);

        (user4_tokenId1, , , ) = uniswapPositionsNFT.mint();
        (user4_tokenId2, , , ) = uniswapPositionsNFT.mint();
        (user4_tokenId3, , , ) = uniswapPositionsNFT.mint();

        uniswapPositionsNFT.approve(
            address(borrowerOperation),
            user4_tokenId1
        );

        uniswapPositionsNFT.approve(
            address(borrowerOperation),
            user4_tokenId2
        );

        uniswapPositionsNFT.approve(
            address(borrowerOperation),
            user4_tokenId3
        );

        borrowerOperation.openPosition(user4_tokenId1);
        borrowerOperation.openPosition(user4_tokenId2);
        borrowerOperation.openPosition(user4_tokenId3);

        vm.stopPrank();

        vm.startPrank(user5);

        deal(usdcAddr, user5, 100_000_000_000 * TOKEN6); //100Md $
        deal(wethAddr, user5, 100_000 ether); //100K ETH

        USDC.approve(address(uniswapPositionsNFT), 100_000_000_000 * TOKEN6);
        WETH.approve(address(uniswapPositionsNFT), 100_000 ether);

        (user5_tokenId1, , , ) = uniswapPositionsNFT.mint();
        (user5_tokenId2, , , ) = uniswapPositionsNFT.mint();
        (user5_tokenId3, , , ) = uniswapPositionsNFT.mint();

        uniswapPositionsNFT.approve(
            address(borrowerOperation),
            user5_tokenId1
        );

        uniswapPositionsNFT.approve(
            address(borrowerOperation),
            user5_tokenId2
        );

        uniswapPositionsNFT.approve(
            address(borrowerOperation),
            user5_tokenId3
        );

        borrowerOperation.openPosition(user5_tokenId1);
        borrowerOperation.openPosition(user5_tokenId2);
        borrowerOperation.openPosition(user5_tokenId3);

        vm.stopPrank();


    }

    function createMintParam(uint24 fees, int24 lower, int24 upper, uint256 amount0, uint256 amount1, address sender) public returns (INonfungiblePositionManager.MintParams memory){
        return INonfungiblePositionManager.MintParams({
                token0: usdcAddr,
                token1: wethAddr,
                fee: fees,
                tickLower: lower,
                tickUpper: upper,
                amount0Desired: amount0,
                amount1Desired: amount1,
                amount0Min: 0,
                amount1Min: 0,
                recipient: sender,
                deadline: block.timestamp
            });
    }

    function testComplete() public {
        assertEq(activePool.getMintedSupply(), 0, "At first, not supply should have been minted.");
        vm.startPrank(user1);
        borrowerOperation.borrowGHO(_GHOAmount, user1_tokenId1);
    }

}