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

    // Number of decimals for GHO token
    uint256 constant TOKEN18 = 10 ** 18;

    // Number of decimals for USDC token
    uint256 constant TOKEN6 = 10 ** 6;

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
        0xE0554a476A092703abdB3Ef35c80e0D76d32939F;
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

    function setUp() public {
        vm.createSelectFork("https://rpc.ankr.com/eth");
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
            address(lpPositionsManager),
            address(activePool)
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
            address(lpPositionsManager),
            address(ghoToken)
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

        vm.startPrank(address(activePool));
        ghoToken.mint(address(user1), 100 * TOKEN18);
        ghoToken.mint(address(user2), 100 * TOKEN18);
        ghoToken.mint(address(user3), 100 * TOKEN18);
        ghoToken.mint(address(user4), 100 * TOKEN18);
        ghoToken.mint(address(user5), 100 * TOKEN18);
        vm.stopPrank();

        //------------------------ start : user1 configurations for test ------------------------

        vm.startPrank(user1);

        deal(usdcAddr, user1, 100_000_000_000 * TOKEN6); //100Md $
        deal(wethAddr, user1, 100_000 ether); //100K ETH

        USDC.approve(address(uniswapPositionsNFT), 100_000_000_000 * TOKEN6);
        WETH.approve(address(uniswapPositionsNFT), 100_000 ether);
        USDC.approve(address(activePool), 100_000_000_000 * TOKEN6);
        WETH.approve(address(activePool), 100_000 ether);
        ghoToken.approve(address(activePool), 100 * TOKEN18);

        //uint24 fees, int24 lower, int24 upper, uint256 amount0, uint256 amount1, address sender
        //(user1_tokenId0, , , ) = uniswapPositionsNFT.mint(); //Pair not approved by protocole.
        (user1_tokenId1, , , ) = uniswapPositionsNFT.mint(
            createMintParams(
                100,
                115135,
                276324,
                280989067,
                249999999487800429,
                user1
            )
        );
        (user1_tokenId2, , , ) = uniswapPositionsNFT.mint(
            createMintParams(
                100,
                184216,
                230270,
                339911608,
                149407050671375578,
                user1
            )
        );
        (user1_tokenId3, , , ) = uniswapPositionsNFT.mint(
            createMintParams(100, 205335, 207243, 46637557137, 0, user1)
        );

        uniswapPositionsNFT.approve(address(borrowerOperation), user1_tokenId1);

        uniswapPositionsNFT.approve(address(borrowerOperation), user1_tokenId2);

        uniswapPositionsNFT.approve(address(borrowerOperation), user1_tokenId3);

        borrowerOperation.openPosition(user1_tokenId1);
        borrowerOperation.openPosition(user1_tokenId2);
        borrowerOperation.openPosition(user1_tokenId3);

        vm.stopPrank();

        //------------------------- end : user1 configurations for test -------------------------

        //------------------------ start : user2 configurations for test ------------------------

        vm.startPrank(user2);

        deal(usdcAddr, user2, 100_000_000_000 * TOKEN6); //100Md $
        deal(wethAddr, user2, 100_000 ether); //100K ETH

        USDC.approve(address(uniswapPositionsNFT), 100_000_000_000 * TOKEN6);
        WETH.approve(address(uniswapPositionsNFT), 100_000 ether);
        USDC.approve(address(activePool), 100_000_000_000 * TOKEN6);
        WETH.approve(address(activePool), 100_000 ether);
        ghoToken.approve(address(activePool), 100 * TOKEN18);

        (user2_tokenId1, , , ) = uniswapPositionsNFT.mint(
            createMintParams(
                100,
                204805,
                207243,
                263090524275,
                64156357155675129377,
                user2
            )
        );
        (user2_tokenId2, , , ) = uniswapPositionsNFT.mint(
            createMintParams(
                100,
                204642,
                207243,
                346797719887,
                424424889204713414,
                user2
            )
        );
        (user2_tokenId3, , , ) = uniswapPositionsNFT.mint(
            createMintParams(
                100,
                204619,
                207243,
                8147401333,
                3142772096131753480,
                user2
            )
        );

        uniswapPositionsNFT.approve(address(borrowerOperation), user2_tokenId1);

        uniswapPositionsNFT.approve(address(borrowerOperation), user2_tokenId2);

        uniswapPositionsNFT.approve(address(borrowerOperation), user2_tokenId3);

        borrowerOperation.openPosition(user2_tokenId1);
        borrowerOperation.openPosition(user2_tokenId2);
        borrowerOperation.openPosition(user2_tokenId3);

        vm.stopPrank();

        //------------------------- end : user2 configurations for test -------------------------

        //------------------------ start : user3 configurations for test ------------------------

        vm.startPrank(user3);

        deal(usdcAddr, user3, 100_000_000_000 * TOKEN6); //100Md $
        deal(wethAddr, user3, 100_000 ether); //100K ETH

        USDC.approve(address(uniswapPositionsNFT), 100_000_000_000 * TOKEN6);
        WETH.approve(address(uniswapPositionsNFT), 100_000 ether);
        USDC.approve(address(activePool), 100_000_000_000 * TOKEN6);
        WETH.approve(address(activePool), 100_000 ether);
        ghoToken.approve(address(activePool), 100 * TOKEN18);

        (user3_tokenId1, , , ) = uniswapPositionsNFT.mint(
            createMintParams(
                100,
                204361,
                207243,
                402251943327,
                21723060789068296769,
                user3
            )
        );
        (user3_tokenId2, , , ) = uniswapPositionsNFT.mint(
            createMintParams(
                100,
                203878,
                207243,
                14339519322,
                10799999999468255542,
                user3
            )
        );
        (user3_tokenId3, , , ) = uniswapPositionsNFT.mint(
            createMintParams(
                100,
                203465,
                207243,
                411353548280,
                38175199687068858458,
                user3
            )
        );

        uniswapPositionsNFT.approve(address(borrowerOperation), user3_tokenId1);

        uniswapPositionsNFT.approve(address(borrowerOperation), user3_tokenId2);

        uniswapPositionsNFT.approve(address(borrowerOperation), user3_tokenId3);

        borrowerOperation.openPosition(user3_tokenId1);
        borrowerOperation.openPosition(user3_tokenId2);
        borrowerOperation.openPosition(user3_tokenId3);

        vm.stopPrank();

        //------------------------- end : user3 configurations for test -------------------------

        //------------------------ start : user4 configurations for test ------------------------

        vm.startPrank(user4);

        deal(usdcAddr, user4, 100_000_000_000 * TOKEN6); //100Md $
        deal(wethAddr, user4, 100_000 ether); //100K ETH

        USDC.approve(address(uniswapPositionsNFT), 100_000_000_000 * TOKEN6);
        WETH.approve(address(uniswapPositionsNFT), 100_000 ether);
        USDC.approve(address(activePool), 100_000_000_000 * TOKEN6);
        WETH.approve(address(activePool), 100_000 ether);
        ghoToken.approve(address(activePool), 100 * TOKEN18);

        //uint24 fees, int24 lower, int24 upper, uint256 amount0, uint256 amount1, address sender
        (user4_tokenId1, , , ) = uniswapPositionsNFT.mint(
            createMintParams(
                100,
                202763,
                207243,
                466435657866,
                3744921609026570929,
                user4
            )
        );
        (user4_tokenId2, , , ) = uniswapPositionsNFT.mint(
            createMintParams(
                100,
                202667,
                207243,
                50000 * TOKEN6,
                798277255604665973,
                user4
            )
        );
        (user4_tokenId3, , , ) = uniswapPositionsNFT.mint(
            createMintParams(
                100,
                201936,
                207243,
                12052947528,
                8324207920310153428,
                user4
            )
        );

        uniswapPositionsNFT.approve(address(borrowerOperation), user4_tokenId1);

        uniswapPositionsNFT.approve(address(borrowerOperation), user4_tokenId2);

        uniswapPositionsNFT.approve(address(borrowerOperation), user4_tokenId3);

        borrowerOperation.openPosition(user4_tokenId1);
        borrowerOperation.openPosition(user4_tokenId2);
        borrowerOperation.openPosition(user4_tokenId3);

        vm.stopPrank();

        //------------------------- end : user4 configurations for test -------------------------

        //------------------------ start : user5 configurations for test ------------------------

        vm.startPrank(user5);

        deal(usdcAddr, user5, 100_000_000_000 * TOKEN6); //100Md $
        deal(wethAddr, user5, 100_000 ether); //100K ETH

        USDC.approve(address(uniswapPositionsNFT), 100_000_000_000 * TOKEN6);
        WETH.approve(address(uniswapPositionsNFT), 100_000 ether);
        USDC.approve(address(activePool), 100_000_000_000 * TOKEN6);
        WETH.approve(address(activePool), 100_000 ether);
        ghoToken.approve(address(activePool), 100 * TOKEN18);

        (user5_tokenId1, , , ) = uniswapPositionsNFT.mint(
            createMintParams(
                100,
                201935,
                207243,
                3706008306,
                5705995494298136638,
                user5
            )
        );
        (user5_tokenId2, , , ) = uniswapPositionsNFT.mint(
            createMintParams(
                100,
                200311,
                207243,
                50000 * TOKEN6,
                10587577356159341,
                user5
            )
        );

        (user5_tokenId3, , , ) = uniswapPositionsNFT.mint(
            createMintParams(
                100,
                200311,
                207243,
                8215000547,
                17795864747568551189,
                user5
            )
        );

        uniswapPositionsNFT.approve(address(borrowerOperation), user5_tokenId1);

        uniswapPositionsNFT.approve(address(borrowerOperation), user5_tokenId2);

        uniswapPositionsNFT.approve(address(borrowerOperation), user5_tokenId3);

        borrowerOperation.openPosition(user5_tokenId1);
        borrowerOperation.openPosition(user5_tokenId2);
        borrowerOperation.openPosition(user5_tokenId3);

        vm.stopPrank();

        //------------------------- end : user5 configurations for test -------------------------

        createEthGhoPool();
    }

    function createMintParams(
        uint24 fees,
        int24 lower,
        int24 upper,
        uint256 amount0,
        uint256 amount1,
        address sender
    ) public view returns (INonfungiblePositionManager.MintParams memory) {
        return
            INonfungiblePositionManager.MintParams({
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

    function createEthGhoPool() private {
        vm.startPrank(deployer);

        PoolGHO_WETH = IUniswapV3Pool(
            uniswapFactory.createPool(address(ghoToken), address(WETH), 500)
        );

        deal(address(ghoToken), deployer, 1225 * 2000 * TOKEN18);

        vm.deal(deployer, 3000 ether);
        // address(WETH).call{value: 2000 ether}(abi.encodeWithSignature("deposit()"));

        ghoToken.approve(address(uniswapPositionsNFT), 1225 * 2000 * TOKEN18);

        INonfungiblePositionManager.MintParams memory mintParams;
        if (PoolGHO_WETH.token0() == address(ghoToken)) {
            PoolGHO_WETH.initialize(
                uint160(FullMath.mulDiv(FixedPoint96.Q96, 1, 35))
            ); // 1 ETH = 1225 GHO
            mintParams = INonfungiblePositionManager.MintParams({
                token0: address(ghoToken),
                token1: address(WETH),
                fee: 500,
                tickLower: -72000,
                tickUpper: -70000,
                amount0Desired: 1000 * 1225 * TOKEN18, // 12250 GHO
                amount1Desired: 1000 * TOKEN18, // 10 ETH
                amount0Min: 500 * 1225 * TOKEN18,
                amount1Min: 500 * TOKEN18,
                recipient: deployer,
                deadline: block.timestamp
            });
        } else {
            PoolGHO_WETH.initialize(
                uint160(FullMath.mulDiv(FixedPoint96.Q96, 35, 1))
            ); // 1 ETH = 1225 GHO
            mintParams = INonfungiblePositionManager.MintParams({
                token0: address(WETH),
                token1: address(ghoToken),
                fee: 500,
                tickLower: 70000,
                tickUpper: 72000,
                amount0Desired: 1000 * TOKEN18, // 1000 ETH
                amount1Desired: 1000 * 1225 * TOKEN18, // 1225000 GHO
                amount0Min: 500 * TOKEN18,
                amount1Min: 500 * 1225 * TOKEN18,
                recipient: deployer,
                deadline: block.timestamp
            });
        }
        uniswapPositionsNFT.mint{value: 1000 ether}(mintParams);

        lpPositionsManager.addPairToProtocol(
            address(PoolGHO_WETH),
            address(ghoToken),
            wethAddr,
            address(PoolGHO_WETH),
            address(0),
            false,
            true
        );

        ghoToken.approve(swapRouterAddr, 25 * 2 * TOKEN18);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: address(ghoToken),
                tokenOut: wethAddr,
                fee: 500,
                recipient: deployer,
                deadline: block.timestamp + 5 minutes,
                amountIn: 25 * TOKEN18,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1 minutes);
        swapRouter.exactInputSingle(params);
        vm.roll(block.number + 2);
        vm.warp(block.timestamp + 90 seconds);
        swapRouter.exactInputSingle(params);
        vm.stopPrank();
    }

    function testComplete() public {
        vm.startPrank(deployer);

        uint256 _minCR = Math.mulDiv(15, FixedPoint96.Q96, 10);
        lpPositionsManager.updateRiskConstants(
            address(uniPoolUsdcETHAddr),
            _minCR
        );

        vm.stopPrank();

        assertEq(
            activePool.getMintedSupply(),
            0,
            "At first, not supply should have been minted."
        );

        uint256 GHOAmount = 10 * TOKEN18;
        uint256 GHOAmount3 = 30 * TOKEN18;

        vm.startPrank(user1);

        borrowerOperation.borrowGHO(GHOAmount, user1_tokenId1);
        assertEq(
            activePool.getMintedSupply(),
            GHOAmount,
            "GHOAmount1_1 should have been minted."
        );
        assertEq(
            lpPositionsManager.debtOf(user1_tokenId1),
            GHOAmount,
            "The debt of user1 position 1 should be of GHOAmount1_1."
        );

        borrowerOperation.borrowGHO(GHOAmount, user1_tokenId2);
        assertEq(
            activePool.getMintedSupply(),
            GHOAmount + GHOAmount,
            "GHOAmount1_1 + GHOAmount1_2 should have been minted."
        );
        assertEq(
            lpPositionsManager.debtOf(user1_tokenId2),
            GHOAmount,
            "The debt of user1 position 2 should be of GHOAmount1_2."
        );

        borrowerOperation.borrowGHO(GHOAmount, user1_tokenId3);
        assertEq(
            activePool.getMintedSupply(),
            GHOAmount + GHOAmount + GHOAmount,
            "GHOAmount1_1 + GHOAmount1_2 + GHOAmount1_3 should have been minted."
        );
        assertEq(
            lpPositionsManager.debtOf(user1_tokenId3),
            GHOAmount,
            "The debt of user1 position 3 should be of GHOAmount1_3."
        );

        assertEq(
            lpPositionsManager.totalDebtOf(user1),
            GHOAmount + GHOAmount + GHOAmount,
            "The total debt of user1 should be of GHOAmount1_1 + GHOAmount1_2 + GHOAmount1_3."
        );

        vm.stopPrank();

        vm.startPrank(user2);

        borrowerOperation.borrowGHO(GHOAmount, user2_tokenId1);
        assertEq(
            activePool.getMintedSupply(),
            GHOAmount3 + GHOAmount,
            "GHOAmount1 + GHOAmount2_1 should have been minted."
        );
        assertEq(
            lpPositionsManager.debtOf(user2_tokenId1),
            GHOAmount,
            "The debt of user2 position 1 should be of GHOAmount1_1."
        );

        borrowerOperation.borrowGHO(GHOAmount, user2_tokenId2);
        assertEq(
            activePool.getMintedSupply(),
            GHOAmount3 + GHOAmount + GHOAmount,
            "GHOAmount1 + GHOAmount2_1 + GHOAmount2_2 should have been minted."
        );
        assertEq(
            lpPositionsManager.debtOf(user2_tokenId2),
            GHOAmount,
            "The debt of user2 position 2 should be of GHOAmount1_2."
        );

        borrowerOperation.borrowGHO(GHOAmount, user2_tokenId3);
        assertEq(
            activePool.getMintedSupply(),
            GHOAmount3 + GHOAmount3,
            "GHOAmount1 + GHOAmount2_1 + GHOAmount2_2 + GHOAmount2_3 should have been minted."
        );
        assertEq(
            lpPositionsManager.debtOf(user2_tokenId3),
            GHOAmount,
            "The debt of user2 position 3 should be of GHOAmount1_3."
        );

        assertEq(
            lpPositionsManager.totalDebtOf(user2),
            GHOAmount + GHOAmount + GHOAmount,
            "The total debt of user2 should be of GHOAmount1_1 + GHOAmount1_2 + GHOAmount1_3."
        );

        vm.stopPrank();

        vm.startPrank(user3);

        borrowerOperation.borrowGHO(GHOAmount, user3_tokenId1);
        assertEq(
            activePool.getMintedSupply(),
            GHOAmount3 + GHOAmount3 + GHOAmount,
            "GHOAmount1 + GHOAmount2 + GHOAmount3_1 should have been minted."
        );
        assertEq(
            lpPositionsManager.debtOf(user3_tokenId1),
            GHOAmount,
            "The debt of user3 position 1 should be of GHOAmount1_1."
        );

        borrowerOperation.borrowGHO(GHOAmount, user3_tokenId2);
        assertEq(
            activePool.getMintedSupply(),
            GHOAmount3 + GHOAmount3 + GHOAmount + GHOAmount,
            "GHOAmount1 + GHOAmount2 + GHOAmount3_1 + GHOAmount3_2 should have been minted."
        );
        assertEq(
            lpPositionsManager.debtOf(user3_tokenId2),
            GHOAmount,
            "The debt of user3 position 2 should be of GHOAmount1_2."
        );

        borrowerOperation.borrowGHO(GHOAmount, user3_tokenId3);
        assertEq(
            activePool.getMintedSupply(),
            GHOAmount3 + GHOAmount3 + GHOAmount3,
            "GHOAmount1 + GHOAmount2 + GHOAmount3_1 + GHOAmount3_2 + GHOAmount3_3 should have been minted."
        );
        assertEq(
            lpPositionsManager.debtOf(user3_tokenId3),
            GHOAmount,
            "The debt of user3 position 3 should be of GHOAmount1_3."
        );

        assertEq(
            lpPositionsManager.totalDebtOf(user3),
            GHOAmount + GHOAmount + GHOAmount,
            "The total debt of user3 should be of GHOAmount1_1 + GHOAmount1_2 + GHOAmount1_3."
        );

        vm.stopPrank();

        vm.startPrank(user4);

        borrowerOperation.borrowGHO(GHOAmount, user4_tokenId1);
        assertEq(
            activePool.getMintedSupply(),
            GHOAmount3 + GHOAmount3 + GHOAmount3 + GHOAmount,
            "GHOAmount1 + GHOAmount2 + GHOAmount3 + GHOAmount4_1 should have been minted."
        );
        assertEq(
            lpPositionsManager.debtOf(user4_tokenId1),
            GHOAmount,
            "The debt of user4 position 1 should be of GHOAmount1_1."
        );

        borrowerOperation.borrowGHO(GHOAmount, user4_tokenId2);
        assertEq(
            activePool.getMintedSupply(),
            GHOAmount3 + GHOAmount3 + GHOAmount3 + GHOAmount + GHOAmount,
            "GHOAmount1 + GHOAmount2 + GHOAmount3 + GHOAmount4_1 + GHOAmount4_2 should have been minted."
        );
        assertEq(
            lpPositionsManager.debtOf(user4_tokenId2),
            GHOAmount,
            "The debt of user4 position 2 should be of GHOAmount1_2."
        );

        borrowerOperation.borrowGHO(GHOAmount, user4_tokenId3);
        assertEq(
            activePool.getMintedSupply(),
            GHOAmount3 + GHOAmount3 + GHOAmount3 + GHOAmount3,
            "GHOAmount1 + GHOAmount2 + GHOAmount3 + GHOAmount4_1 + GHOAmount4_2 + GHOAmount4_3 should have been minted."
        );
        assertEq(
            lpPositionsManager.debtOf(user4_tokenId3),
            GHOAmount,
            "The debt of user4 position 3 should be of GHOAmount1_3."
        );

        assertEq(
            lpPositionsManager.totalDebtOf(user4),
            GHOAmount + GHOAmount + GHOAmount,
            "The total debt of user4 should be of GHOAmount1_1 + GHOAmount1_2 + GHOAmount1_3."
        );

        vm.stopPrank();

        vm.startPrank(user5);

        borrowerOperation.borrowGHO(GHOAmount, user5_tokenId1);
        assertEq(
            activePool.getMintedSupply(),
            GHOAmount3 + GHOAmount3 + GHOAmount3 + GHOAmount3 + GHOAmount,
            "GHOAmount1 + GHOAmount2 + GHOAmount3 + GHOAmount4 + GHOAmount5_1 should have been minted."
        );
        assertEq(
            lpPositionsManager.debtOf(user5_tokenId1),
            GHOAmount,
            "The debt of user5 position 1 should be of GHOAmount1_1."
        );

        borrowerOperation.borrowGHO(GHOAmount, user5_tokenId2);
        assertEq(
            activePool.getMintedSupply(),
            GHOAmount3 +
                GHOAmount3 +
                GHOAmount3 +
                GHOAmount3 +
                GHOAmount +
                GHOAmount,
            "GHOAmount1 + GHOAmount2 + GHOAmount3 + GHOAmount4 + GHOAmount5_1 + GHOAmount5_2 should have been minted."
        );
        assertEq(
            lpPositionsManager.debtOf(user5_tokenId2),
            GHOAmount,
            "The debt of user5 position 2 should be of GHOAmount1_2."
        );

        borrowerOperation.borrowGHO(GHOAmount, user5_tokenId3);
        assertEq(
            activePool.getMintedSupply(),
            GHOAmount3 + GHOAmount3 + GHOAmount3 + GHOAmount3 + GHOAmount3,
            "GHOAmount1 + GHOAmount2 + GHOAmount3 + GHOAmount4 + GHOAmount5_1 + GHOAmount5_2 + GHOAmount5_3 should have been minted."
        );
        assertEq(
            lpPositionsManager.debtOf(user5_tokenId3),
            GHOAmount,
            "The debt of user5 position 3 should be of GHOAmount1_3."
        );

        assertEq(
            lpPositionsManager.totalDebtOf(user5),
            GHOAmount + GHOAmount + GHOAmount,
            "The total debt of user5 should be of GHOAmount1_1 + GHOAmount1_2 + GHOAmount1_3."
        );

        vm.stopPrank();

        uint256 initialDebtUser1 = lpPositionsManager.totalDebtOf(user1);

        vm.warp(block.timestamp + 365 days);

        assertGt(
            lpPositionsManager.totalDebtOf(user1),
            initialDebtUser1,
            "The total debt of user1 should have increased."
        );

        vm.startPrank(user1);

        // User1 repays only the fees of his positions

        borrowerOperation.repayGHO(200000000000000000, user1_tokenId1);
        borrowerOperation.repayGHO(200000000000000000, user1_tokenId2);
        borrowerOperation.repayGHO(200000000000000000, user1_tokenId3);

        // The fees should have been transfered to the address where we collect it, we should have 3 times 200000000000000000

        assertEq(
            600000000000000000,
            ghoToken.balanceOf(0x53A5a93e8b82030C3a52e9ff36801956b8661333),
            "The fees should have been transfered to this address "
        );

        vm.stopPrank();

        assertEq(activePool.getMintedSupply(), 150 * TOKEN18);

        assertEq(
            lpPositionsManager.totalDebtOf(user1),
            initialDebtUser1,
            "The total debt of user1 should be the same as before."
        );

        vm.warp(block.timestamp + 365 days);

        vm.startPrank(user1);

        borrowerOperation.repayGHO(200000000000000000, user1_tokenId1);
        borrowerOperation.repayGHO(200000000000000000, user1_tokenId2);
        borrowerOperation.repayGHO(200000000000000000, user1_tokenId3);

        // We should have accumulated 6 times 200000000000000000 because the user1 calls repayGHO 6 times
        assertEq(
            1200000000000000000,
            ghoToken.balanceOf(0x53A5a93e8b82030C3a52e9ff36801956b8661333),
            "The fees should have been transfered to this address "
        );

        vm.stopPrank();

        assertEq(activePool.getMintedSupply(), 150 * TOKEN18);

        assertEq(
            lpPositionsManager.totalDebtOf(user1),
            initialDebtUser1,
            "The total debt of user1 should be the same as before."
        );

        vm.startPrank(user1);

        borrowerOperation.borrowGHO(7 * TOKEN18, user1_tokenId1);
        borrowerOperation.borrowGHO(4 * TOKEN18, user1_tokenId2);
        borrowerOperation.borrowGHO(9 * TOKEN18, user1_tokenId3);

        borrowerOperation.borrowGHO(6 * TOKEN18, user1_tokenId1);
        borrowerOperation.borrowGHO(7 * TOKEN18, user1_tokenId2);
        borrowerOperation.borrowGHO(5 * TOKEN18, user1_tokenId3);

        borrowerOperation.repayGHO(3 * TOKEN18, user1_tokenId1);
        borrowerOperation.repayGHO(1 * TOKEN18, user1_tokenId2);
        borrowerOperation.repayGHO(4 * TOKEN18, user1_tokenId3);

        vm.stopPrank();
        assertEq(activePool.getMintedSupply(), 180 * TOKEN18);

        assertEq(
            lpPositionsManager.totalDebtOf(user1),
            2 * initialDebtUser1,
            "The total debt of user1 should be the doubled."
        );

        vm.warp(block.timestamp + 365 days);

        vm.startPrank(user1);

        borrowerOperation.repayGHO(10400000000000000000, user1_tokenId1);

        borrowerOperation.repayGHO(10400000000000000000, user1_tokenId2);

        borrowerOperation.repayGHO(10400000000000000000, user1_tokenId3);

        vm.stopPrank();

        assertEq(
            lpPositionsManager.totalDebtOf(user1),
            initialDebtUser1,
            "The total debt of user1 should be the same as before."
        );

        assertEq(
            lpPositionsManager.totalDebtOf(user2),
            3183624 * 10 ** 13,
            "The total debt of user2 should be 31.83624 GHO."
        );

        assertEq(activePool.getMintedSupply(), 14964 * 10 ** 16);

        vm.startPrank(user1);

        // Try to close the 3 positions of user1 while the debt is ot repaid for all of them

        vm.expectRevert("Debt is not repaid.");
        borrowerOperation.closePosition(user1_tokenId1);

        vm.expectRevert("Debt is not repaid.");
        borrowerOperation.closePosition(user1_tokenId2);

        vm.expectRevert("Debt is not repaid.");
        borrowerOperation.closePosition(user1_tokenId3);

        // Repay all the debt of the 3 positions

        borrowerOperation.repayGHO(10 * TOKEN18, user1_tokenId1);
        borrowerOperation.repayGHO(10 * TOKEN18, user1_tokenId2);
        borrowerOperation.repayGHO(10 * TOKEN18, user1_tokenId3);
        vm.stopPrank();

        assertEq(activePool.getMintedSupply(), 120 * TOKEN18);

        vm.warp(block.timestamp + 365 days);

        assertEq(
            lpPositionsManager.totalDebtOf(user1),
            0,
            "The total debt of user1 should be 0."
        );

        vm.startPrank(user1);
        borrowerOperation.closePosition(user1_tokenId1);
        borrowerOperation.closePosition(user1_tokenId2);
        borrowerOperation.closePosition(user1_tokenId3);
        vm.stopPrank();

        vm.startPrank(user2);
        borrowerOperation.addCollateral(
            user2_tokenId1,
            1000 * TOKEN6,
            10 * TOKEN18
        );
        //GITAN mais fonctionne.

        uint128 liquidity = lpPositionsManager
            .getPosition(user2_tokenId1)
            .liquidity;
        borrowerOperation.removeCollateral(user2_tokenId1, liquidity / 2);

        assertEq(
            lpPositionsManager.getPosition(user2_tokenId1).liquidity,
            liquidity / 2,
            "The liquidity of user2 position 1 should be half of the initial liquidity."
        );
        vm.stopPrank();

        // vm.startPrank(user2);
        // vm.expectRevert();
        // borrowerOperation.removeCollateral(user2_tokenId2, lpPositionsManager.getPosition(user2_tokenId2).liquidity);
        // vm.stopPrank();
    }

    function convertQ96(uint256 x) public pure returns (uint256) {
        return FullMath.mulDiv(x, 1, 2 ** 96);
    }

    function convertDecimals18(uint256 x) public pure returns (uint256) {
        return FullMath.mulDiv(x, 1, 10 ** 18);
    }

    function convertDecimals6(uint256 x) public pure returns (uint256) {
        return FullMath.mulDiv(x, 1, 10 ** 6);
    }

    function setUpForUser(address user, INonfungiblePositionManager.MintParams calldata mintParamsNFT1, INonfungiblePositionManager.MintParams calldata mintParamsNFT2,INonfungiblePositionManager.MintParams calldata mintParamsNFT3) public returns (uint256 tokenId) {
    }

}
