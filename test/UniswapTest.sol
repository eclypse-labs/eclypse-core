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
    // polygon users !!!!
    address user1 = 0x7C28C02aF52c1Ddf7Ae6f3892cCC8451a17f2842; //	tokenID = 549666
    address user2 = 0x95BF9205341e9b3bC7aD426C44e80f5455DAC1cE; // tokenID = 549638

    // Polygon addresses
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

    // deal(address token, address to, uint256 give) public; pour donner des thunasses

    INonfungiblePositionManager uniswapPositionsNFT;

    function uniswapTest() public {
        vm.createSelectFork(
           "https://polygon-mainnet.g.alchemy.com/v2/h8l-R6mdwbnOIskdfNCmA_pFNWlWtArt", 36385297
        ); // polygon mainnet

        // same for polygon and ethereum
        uniswapPositionsNFT = INonfungiblePositionManager(
            0xC36442b4a4522E871399CD717aBDD847Ab11FE88
        );

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

        // commented due to polygon setup 

        vm.startPrank(user1);
        uniswapPositionsNFT.approve(address(borrowerOperation), 549666);
        borrowerOperation.openPosition(549666);
        vm.stopPrank();

        vm.startPrank(user2);
        uniswapPositionsNFT.approve(address(borrowerOperation), 549638);
        borrowerOperation.openPosition(549638);
        vm.stopPrank();

        console.log("THIS IS THE POSITION ADDRESS : ",lpPositionsManager.getPosition(549666).poolAddress);
        
        
    }
}
