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

    // Ethereum addresses
    address public constant wethAddr =
        0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant usdcAddr =
        0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant uniPoolUsdcETHAddr =
        0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640;

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
           "ADD RPC HERE"
        ); // ethereum mainnet

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

        /*vm.startPrank(user1);
        uniswapPositionsNFT.approve(address(borrowerOperation), 549666);
        borrowerOperation.openPosition(549666);
        vm.stopPrank();

        vm.startPrank(user2);
        uniswapPositionsNFT.approve(address(borrowerOperation), 549638);
        borrowerOperation.openPosition(549638);
        vm.stopPrank();

        console.log(lpPositionsManager.getPosition(549666).user);
        
        */
    }
}
