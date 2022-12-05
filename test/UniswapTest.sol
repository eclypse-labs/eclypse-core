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

    address user1 = 0x7C28C02aF52c1Ddf7Ae6f3892cCC8451a17f2842;
    // tokenID = 549666, block: 36385297, transactionHash : 0x7c06e0bbf0a2d8366fca14d2e3c957d2246112cc4a1402722475a7a6f3c8e7ea
    // LP Position : USDC => 139.296661 ($139.30)
    //               WETH => 0.144999216684979526 ($182.23)

    address user2 = 0x94f2F7dEef8b5778b0Ad706cD9d6d19aC11a3f04;
    // tokenID = 550389, block: 36402745, transactionHash : 0xbc297d0f6c00e3c6a75172dbbe33a152eec6889a4efbbfde98679f4288da9e1b
    // LP Position : USDC => 35.267822 ($35.27)
    //               WETH => 0.027791259596283775 ($34.93)

    address public constant wethAddr =
        0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619; //weth on polygon mainnet

    address public constant usdcAddr =
        0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174; //usdc on polygon mainnet

    address public constant uniPoolUsdcETHAddr =
        0x45dDa9cb7c25131DF268515131f647d726f50608; // USDC/WETH uniswap pool on polygon mainnet

    IERC20 WETH = IERC20(wethAddr);
    IERC20 USDC = IERC20(usdcAddr);

    ActivePool activePool;
    BorrowerOperations borrowerOperation;
    GHOToken ghoToken;
    LPPositionsManager lpPositionsManager;

    // deal(address token, address to, uint256 give) public; pour donner des thunasses

    INonfungiblePositionManager uniswapPositionsNFT;

    function uniswapTest() public {
        vm.createSelectFork("https://rpc.ankr.com/polygon", 36402745); // polygon mainet

        uniswapPositionsNFT = INonfungiblePositionManager(
            0xC36442b4a4522E871399CD717aBDD847Ab11FE88
        );

        vm.startPrank(deployer);
        activePool = new ActivePool();
        borrowerOperation = new BorrowerOperations();
        lpPositionsManager = new LPPositionsManager();
        ghoToken = new GHOToken(address(borrowerOperation));
        console.log("ghtoken address : ", address(ghoToken));

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

        vm.startPrank(user1);
        uniswapPositionsNFT.approve(address(borrowerOperation), 549666);
        borrowerOperation.openPosition(549666);
        vm.stopPrank();

        vm.startPrank(user2);
        uniswapPositionsNFT.approve(address(borrowerOperation), 550389);
        borrowerOperation.openPosition(550389);
        vm.stopPrank();

        lpPositionsManager.addTokenETHpoolAddress(
            address(usdcAddr),
            address(uniPoolUsdcETHAddr),
            false
        ); 
    }
}