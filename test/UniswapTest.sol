//SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "forge-std/Test.sol";
import "@uniswap-core/interfaces/IUniswapV3Factory.sol";
import "@uniswap-core/interfaces/IUniswapV3Pool.sol";
import "@uniswap-core/libraries/FixedPoint96.sol";
import "@uniswap-periphery/interfaces/INonfungiblePositionManager.sol";
import "@uniswap-periphery/interfaces/ISwapRouter.sol";
import "@uniswap-periphery/interfaces/IQuoterV2.sol";
import "@uniswap-core/libraries/FullMath.sol";
import "./FakePriceFeed.sol";

////////////////////////////////////////////////////
// OLD IMPORTS BELOW

// import "../contracts/ActivePool.sol";
// import "../contracts/BorrowerOperations.sol";
// import "../contracts/interfaces/IEclypse.sol";
// import "../contracts/LPPositionsManager.sol";

////////////////////////////////////////////////////
// NEW IMPORTS BELOW

import "../contracts/EclypseVault.sol";
import "../contracts/UserInteractions.sol";
import "../contracts/interfaces/IEclypseVault.sol";
import "../contracts/PositionsManager.sol";
import "../contracts/PriceFeed.sol";
import "gho-core/src/contracts/gho/GhoToken.sol";

abstract contract UniswapTest is Test {
	GhoToken ghoToken;

	uint256 constant TOKEN18 = 10 ** 18;
	uint256 constant TOKEN6 = 10 ** 6;

	address deployer = makeAddr("deployer");
	address oracleLiquidityDepositor = makeAddr("oracleLiquidityDepositor");
	address user1 = 0x7C28C02aF52c1Ddf7Ae6f3892cCC8451a17f2842; // tokenID = 549666
	address user2 = 0x95BF9205341e9b3bC7aD426C44e80f5455DAC1cE; // tokenID = 549638

	address facticeUser1 = makeAddr("facticeUser1");
	address facticeUser2 = makeAddr("facticeUser2");
	address facticeUser3 = makeAddr("facticeUser3");
	uint256 facticeUser1_tokenId;
	uint256 facticeUser1_tokenId2;

	address public constant wethAddr = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
	address public constant usdcAddr = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
	address public constant daiAddr = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
	address public uniPoolUsdcETHAddr = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640;
	address public constant swapRouterAddr = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
	address public uniPoolWBTCETHAddr = 0xCBCdF9626bC03E24f779434178A73a0B4bad62eD;
	address public WBTCAddr = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
	address public constant feedRegisteryAddr = 0x47Fb2585D2C56Fe188D0E6ec628a38b74fCeeeDf;
	address public constant uniswapFactoryAddr = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
	address public constant uniswapPositionsNFTAddr = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;

	IERC20 WETH = IERC20(wethAddr);
	IERC20 USDC = IERC20(usdcAddr);
	IERC20 WBTC = IERC20(WBTCAddr);

	EclypseVault eclypseVault;
	UserInteractions userInteractions;
	PositionsManager positionsManager;
	PriceFeed priceFeed;
	INonfungiblePositionManager uniswapPositionsNFT;
	ISwapRouter swapRouter;
	IUniswapV3Pool uniV3PoolWeth_Usdc;
	IUniswapV3Pool uniPoolGhoEth;
	IQuoterV2 quoter;
	uint256 tokenId;
	FakePriceFeed fakePriceFeed;

	IUniswapV3Factory uniswapFactory = IUniswapV3Factory(uniswapFactoryAddr);

	function convertQ96(uint256 x) public pure returns (uint256) {
		return FullMath.mulDiv(x, 1, 2 ** 96);
	}

	function convertDecimals18(uint256 x) public pure returns (uint256) {
		return FullMath.mulDiv(x, 1, 10 ** 18);
	}

	function convertDecimals6(uint256 x) public pure returns (uint256) {
		return FullMath.mulDiv(x, 1, 10 ** 6);
	}

	function uniswapTest() public {
		vm.createSelectFork("https://rpc.ankr.com/eth", 16_153_817); // eth mainnet at block 16_153_817
		//vm.createSelectFork("https://rpc.ankr.com/polygon", 36_655_806); // polygon at block 16_153_817 (same timestamp as eth mainnet)

		vm.startPrank(deployer);

		fakePriceFeed = new FakePriceFeed();

		uniswapPositionsNFT = INonfungiblePositionManager(uniswapPositionsNFTAddr);

		quoter = IQuoterV2(0x61fFE014bA17989E743c5F6cB21bF9697530B21e);

		swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

		uniV3PoolWeth_Usdc = IUniswapV3Pool(uniPoolUsdcETHAddr);

		eclypseVault = new EclypseVault();
		userInteractions = new UserInteractions();
		positionsManager = new PositionsManager();
		priceFeed = new PriceFeed();

		ghoToken = new GhoToken();
		ghoToken.addFacilitator(address(eclypseVault), IGhoToken.Facilitator(1_000_000 * 10 ** 18, 0, "Eclypse (EclypseVault)"));

		userInteractions.initialize(uniswapPositionsNFTAddr, address(positionsManager));
		positionsManager.initialize(
			uniswapFactoryAddr,
			uniswapPositionsNFTAddr,
			address(userInteractions),
			address(eclypseVault),
			address(priceFeed)
		);

		eclypseVault.initialize(uniswapPositionsNFTAddr, address(positionsManager));

		// whitelist la pool: updateRiskConstants
		// pour l'oracle ajouter la pool ETH/GHO: addTokenETHpoolAddress
		positionsManager.addPoolToProtocol(uniPoolUsdcETHAddr);

		uint256 _minCR = FullMath.mulDiv(15, FixedPoint96.Q96, 10);
		positionsManager.updateRiskConstants(address(uniPoolUsdcETHAddr), _minCR);
		// protocol values are initialized here
		IPositionsManager.AssetsValues memory assetValues;
		assetValues.interestRate = 79228162564014647528974148095;
		assetValues.totalBorrowedStableCoin = 0;
		assetValues.interestFactor = 1 << 96;
		assetValues.lastFactorUpdate = block.timestamp;
		assetValues.twapLength = 60;
		priceFeed.initialize(feedRegisteryAddr);
		positionsManager.addAssetsValuesToProtocol(address(ghoToken), assetValues);

		vm.stopPrank();
		createEthGhoPool();
		addFacticeUser();

		vm.label(address(wethAddr), "WETH");
		vm.label(address(usdcAddr), "USDC");
		vm.label(address(uniPoolUsdcETHAddr), "USDC/ETH pool");
		vm.label(address(ghoToken), "GHO");
		vm.label(address(userInteractions), "UserInteractions");
		vm.label(address(positionsManager), "PositionsManager");
		vm.label(address(eclypseVault), "EclypseVault");
		vm.label(address(uniswapPositionsNFT), "UniswapPositionsNFT");
		vm.label(address(swapRouter), "SwapRouter");
		vm.label(uniswapPositionsNFTAddr, "UniswapPositionsNFT");
	}

	function addFacticeUser() private {
		vm.startPrank(facticeUser1);
		deal(usdcAddr, facticeUser1, 100_000_000_000_000_000 * TOKEN6);
		deal(wethAddr, facticeUser1, 100 ether);

		USDC.approve(address(uniswapPositionsNFT), 100_000_000_000_000_000 * TOKEN6);
		WETH.approve(address(uniswapPositionsNFT), 100 ether);
		ghoToken.approve(address(positionsManager), 1000 * TOKEN18);

		// uniswapPositionsNFT::mint((0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174,
		// 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619, 500, 204920, 204930, 0,
		// 78651133592434045, 0, 78651133592434045, 0xCcDA2f3B7255Fa09B963bEc26720940209E27ecd, 1670147167))

		// uniV3PoolWeth_Usdc::mint(uniswapPositionsNFT: [0xC36442b4a4522E871399CD717aBDD847Ab11FE88],
		// 204920, 204930, 5585850858003193, 0x0000000000000000000000002791bca1f2de4661ed88a30c99a7a9449aa8417400
		// 00000000000000000000007ceb23fd6bc0add59e62ac25578270cff1b9f619000000000000000000000000000000000000000000
		// 00000000000000000001f4000000000000000000000000ccda2f3b7255fa09b963bec26720940209e27ecd)

		INonfungiblePositionManager.MintParams memory mintParams = INonfungiblePositionManager.MintParams({
			token0: usdcAddr,
			token1: wethAddr,
			fee: 500,
			tickLower: int24(204860),
			tickUpper: int24(204930),
			amount0Desired: 1250 * TOKEN6,
			amount1Desired: 1 * TOKEN18,
			amount0Min: 0,
			amount1Min: 0,
			recipient: facticeUser1,
			deadline: block.timestamp
		});

		(facticeUser1_tokenId, , , ) = uniswapPositionsNFT.mint(mintParams);
		(facticeUser1_tokenId2, , , ) = uniswapPositionsNFT.mint(mintParams);

		uniswapPositionsNFT.approve(address(positionsManager), facticeUser1_tokenId);
		uniswapPositionsNFT.approve(address(positionsManager), facticeUser1_tokenId2);

		userInteractions.openPosition(facticeUser1_tokenId, address(ghoToken));
		userInteractions.openPosition(facticeUser1_tokenId2, address(ghoToken));
		vm.stopPrank();

		vm.startPrank(address(eclypseVault));
		ghoToken.mint(facticeUser1, 1000 * TOKEN18);
		ghoToken.mint(facticeUser2, 1000 * TOKEN18);
		ghoToken.mint(facticeUser3, 1000 * TOKEN18);
		vm.stopPrank();

		vm.startPrank(facticeUser2);
		ghoToken.approve(address(positionsManager), 100 * TOKEN18);
		vm.stopPrank();

		vm.startPrank(facticeUser3);
		ghoToken.approve(address(positionsManager), 100 * TOKEN18);
		vm.stopPrank();
	}

	// creates the gho/eth pool, puts liquidity in it and adds it to the protocol's list of pools
	function createEthGhoPool() private {
		vm.startPrank(deployer);

		uniPoolGhoEth = IUniswapV3Pool(uniswapFactory.createPool(address(ghoToken), address(WETH), 500));

		deal(address(ghoToken), deployer, 1225 * 2000 * TOKEN18);

		vm.deal(deployer, 3000 ether);
		// address(WETH).call{value: 2000 ether}(abi.encodeWithSignature("deposit()"));

		ghoToken.approve(address(uniswapPositionsNFT), 1225 * 2000 * TOKEN18);

		INonfungiblePositionManager.MintParams memory mintParams;
		if (uniPoolGhoEth.token0() == address(ghoToken)) {
			uniPoolGhoEth.initialize(uint160(FullMath.mulDiv(FixedPoint96.Q96, 1, 35))); // 1 ETH = 1225 GHO
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
			uniPoolGhoEth.initialize(uint160(FullMath.mulDiv(FixedPoint96.Q96, 35, 1))); // 1 ETH = 1225 GHO
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
		uniswapPositionsNFT.mint{ value: 1000 ether }(mintParams);

		positionsManager.addPoolToProtocol(address(uniPoolGhoEth));

		ghoToken.approve(swapRouterAddr, 25 * 2 * TOKEN18);

		ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
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
}
