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
import "@uniswap-periphery/interfaces/INonfungiblePositionManager.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";

abstract contract UniswapTest is Test {
    ERC20Mintable token;

    address deployer = makeAddr("deployer");
    address oracleLiquidityDepositor = makeAddr("oracleLiquidityDepositor");
    address user1 = 0x7C28C02aF52c1Ddf7Ae6f3892cCC8451a17f2842; //	tokenID = 549666
    address user2 = 0x95BF9205341e9b3bC7aD426C44e80f5455DAC1cE; // tokenID = 549638

    address facticeUser1 = makeAddr("facticeUser1");
    address facticeUser2 = makeAddr("facticeUser2");
    uint256 facticeUser1_tokenId;

    address public constant wethAddr =
        0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;
    address public constant usdcAddr =
        0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    address public constant uniPoolUsdcETHAddr =
        0x45dDa9cb7c25131DF268515131f647d726f50608;

    IERC20 WETH = IERC20(wethAddr);
    IERC20 USDC = IERC20(usdcAddr);

    ActivePool activePool;
    BorrowerOperations borrowerOperation;
    GHOToken ghoToken;
    LPPositionsManager lpPositionsManager;
    INonfungiblePositionManager uniswapPositionsNFT;
    IUniswapV3Pool uniV3PoolWeth_Usdc;

    //     IUniswapV3Factory uniswapFactory =
    //         IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);

    function uniswapTest() public {
        vm.createSelectFork("https://rpc.ankr.com/polygon", 36_385_297); // polygon mainet 1_670_147_167

        uniswapPositionsNFT = INonfungiblePositionManager(
            0xC36442b4a4522E871399CD717aBDD847Ab11FE88
        );

        uniV3PoolWeth_Usdc = IUniswapV3Pool(
            0x45dDa9cb7c25131DF268515131f647d726f50608
        );
        //         uniPoolGhoEth = IUniswapV3Pool(
        //             uniswapFactory.createPool(address(GHO), address(WETH), fee)
        //         );

        vm.startPrank(deployer);
        activePool = new ActivePool();
        borrowerOperation = new BorrowerOperations();
        lpPositionsManager = new LPPositionsManager();
        ghoToken = new GHOToken(address(borrowerOperation));

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

        vm.stopPrank();
        addFacticeUser();
    }

    function addUserOnMainnet() private {
        vm.startPrank(user1);
        uniswapPositionsNFT.approve(address(borrowerOperation), 549666);
        borrowerOperation.openPosition(549666);
        vm.stopPrank();

        vm.startPrank(user2);
        uniswapPositionsNFT.approve(address(borrowerOperation), 549638);
        borrowerOperation.openPosition(549638);
        vm.stopPrank();
    }

    function addFacticeUser() private {
        vm.startPrank(facticeUser1);
        //console.log(ILPPositionsManager.Status.closedByOwner);

        deal(usdcAddr, facticeUser1, 10 ether);
        deal(wethAddr, facticeUser1, 10 ether);

        USDC.approve(address(uniswapPositionsNFT), 3000 ether);
        WETH.approve(address(uniswapPositionsNFT), 3000 ether);

        // uniswapPositionsNFT::mint((0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174,
        // 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619, 500, 204920, 204930, 0,
        //78651133592434045, 0, 78651133592434045, 0xCcDA2f3B7255Fa09B963bEc26720940209E27ecd, 1670147167))

        //uniV3PoolWeth_Usdc::mint(uniswapPositionsNFT: [0xC36442b4a4522E871399CD717aBDD847Ab11FE88],
        //204920, 204930, 5585850858003193, 0x0000000000000000000000002791bca1f2de4661ed88a30c99a7a9449aa8417400
        //00000000000000000000007ceb23fd6bc0add59e62ac25578270cff1b9f619000000000000000000000000000000000000000000
        //00000000000000000001f4000000000000000000000000ccda2f3b7255fa09b963bec26720940209e27ecd)

        INonfungiblePositionManager.MintParams
            memory mintParams = INonfungiblePositionManager.MintParams({
                token0: usdcAddr,
                token1: wethAddr,
                fee: 500,
                tickLower: int24(204920),
                tickUpper: int24(204930),
                amount0Desired: 1,
                amount1Desired: 78651133592434045,
                amount0Min: 0,
                amount1Min: 0,
                recipient: facticeUser1,
                deadline: block.timestamp
            });

        (uint256 tokenId, , , ) = uniswapPositionsNFT.mint(mintParams);
        console.log("couscous");
        uniswapPositionsNFT.approve(address(borrowerOperation), tokenId);
        borrowerOperation.openPosition(tokenId);
        vm.stopPrank();
        // facticeUser1.transfer

        // console.log(uniswapPositionsNFT.getPosition(tokenId).user);
        // uniswapPositionsNFT.approve(address(borrowerOperation), tokenId);
        // borrowerOperation.openPosition(tokenId);
        // console.log(lpPositionsManager.getPosition(tokenId).user);
        // vm.stopPrank();
    }

    function createEthGhoPool() private {
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
        //         vm.stopPrank();
    }
}
