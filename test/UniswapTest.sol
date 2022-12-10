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
import "@openzeppelin/contracts/interfaces/IERC20.sol";

abstract contract UniswapTest is Test {
    IGHOToken ghoToken;

    address deployer = makeAddr("deployer");
    address oracleLiquidityDepositor = makeAddr("oracleLiquidityDepositor");
    address user1 = 0x7C28C02aF52c1Ddf7Ae6f3892cCC8451a17f2842; //	tokenID = 549666
    address user2 = 0x95BF9205341e9b3bC7aD426C44e80f5455DAC1cE; // tokenID = 549638

    address facticeUser1 = makeAddr("facticeUser1");
    address facticeUser2 = makeAddr("facticeUser2");
    uint256 facticeUser1_tokenId;

    address public constant wethAddr =
        0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant usdcAddr =
        0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant uniPoolUsdcETHAddr =
        0x45dDa9cb7c25131DF268515131f647d726f50608;

    IERC20 WETH = IERC20(wethAddr);
    IERC20 USDC = IERC20(usdcAddr);

    ActivePool activePool;
    BorrowerOperations borrowerOperation;
    LPPositionsManager lpPositionsManager;
    INonfungiblePositionManager uniswapPositionsNFT;
    IUniswapV3Pool uniV3PoolWeth_Usdc;
    IUniswapV3Pool uniPoolGhoEth;
    uint256 tokenId;
    
    IUniswapV3Factory uniswapFactory =
        IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);

    function uniswapTest() public {
        vm.createSelectFork("https://rpc.ankr.com/eth", 16_153_817); // eth mainet at block 16_153_817

        vm.startPrank(deployer);

        uniswapPositionsNFT = INonfungiblePositionManager(
            0xC36442b4a4522E871399CD717aBDD847Ab11FE88
        );

        uniV3PoolWeth_Usdc = IUniswapV3Pool(
            0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640
        );

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

        //         //whitelist la pool: updateRiskConstants
        // uint256 _minCR = 0;
        // positionsManager.updateRiskConstants(address(uniPoolUsdcETH), _minCR);
        // //pour l'oracle ajouter la pool ETH/GHO: addTokenETHpoolAddress
        // bool _inv = false; //TODO: set parameter _inv

        vm.stopPrank();
        addFacticeUser();
        createEthGhoPool();
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
        console.log("couscous");
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

        (facticeUser1_tokenId, , , ) = uniswapPositionsNFT.mint(mintParams);
        uniswapPositionsNFT.approve(address(borrowerOperation), facticeUser1_tokenId);
        borrowerOperation.openPosition(facticeUser1_tokenId);

        vm.stopPrank();
        // facticeUser1.transfer

        // console.log(uniswapPositionsNFT.getPosition(tokenId).user);
        // uniswapPositionsNFT.approve(address(borrowerOperation), tokenId);
        // borrowerOperation.openPosition(tokenId);
        //console.log(lpPositionsManager.getPosition(tokenId).user);
        // vm.stopPrank();
    }

    // creates teh ghoe/eth pool, puts liquidity in it and adds it to the protocol's list of pools
    function createEthGhoPool() private {
        vm.startPrank(deployer);

        //uniswapFactory.enableFeeAmount(500, 10);
        uniPoolGhoEth = IUniswapV3Pool(
            uniswapFactory.createPool(address(ghoToken), address(WETH), 500)
        );
        
        deal(address(ghoToken), deployer, 10**18 * 1225 * 2000);

        vm.deal(deployer, 3000 ether);
        //address(WETH).call{value: 2000 ether}(abi.encodeWithSignature("deposit()"));

        ghoToken.approve(address(uniswapPositionsNFT), 10**18 * 1225 * 2000);
        

        INonfungiblePositionManager.MintParams memory mintParams;
        if (uniPoolGhoEth.token0() == address(ghoToken)) {
            uniPoolGhoEth.initialize(uint160(FullMath.mulDiv(FixedPoint96.Q96, 1, 35))); // 1 ETH = 1225 GHO
            mintParams = INonfungiblePositionManager.MintParams({
                token0: address(ghoToken),
                token1: address(WETH),
                fee: 500,
                tickLower: -72000,
                tickUpper: -70000,
                amount0Desired: 10**18 * 1000 * 1225, // 12250 GHO
                amount1Desired: 10**18 * 1000, // 10 ETH
                amount0Min: 10**18 * 500 * 1225,
                amount1Min: 10**18 * 500,
                recipient: deployer,
                deadline: block.timestamp
            });
        } else {
            uniPoolGhoEth.initialize(uint160(FullMath.mulDiv(FixedPoint96.Q96, 35, 1))); // 1 ETH = 1225 GHO
            mintParams = INonfungiblePositionManager.MintParams({
                token0: address(WETH),
                token1: address(ghoToken),
                fee: 500,
                tickLower: 70000,
                tickUpper: 72000,
                amount0Desired: 10**18 * 1000, // 1000 ETH
                amount1Desired: 10**18 * 1000 * 1225, // 1225000 GHO
                amount0Min: 10**18 * 500,
                amount1Min: 10**18 * 500 * 1225,
                recipient: deployer,
                deadline: block.timestamp
            });
        }
        uniswapPositionsNFT.mint{value: 1000 ether}(mintParams);

        lpPositionsManager.addTokenETHpoolAddress(
            address(ghoToken),
            address(uniPoolGhoEth),
            address(ghoToken) > address(WETH) // inv = true if and only if GHO is token1 <=> address(GHO) > address(WETH)
        );
        console.log("gho balance", ghoToken.balanceOf(deployer));
        console.log("eth balance", deployer.balance);
        vm.stopPrank();
    }
}
