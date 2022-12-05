//SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

// import "forge-std/Test.sol";
// import "../src/GHOToken.sol";
// import "../src/BorrowerOperations.sol";
// import "../src/ActivePool.sol";
// import "../src/LPPositionsManager.sol";
// import "@uniswap-core/interfaces/IUniswapV3Factory.sol";
// import "@uniswap-core/interfaces/IUniswapV3Pool.sol";
// import "@uniswap-periphery/interfaces/INonfungiblePositionManager.sol";
// import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "./UniswapTest.sol";

contract LPPositionsManagerTest is UniswapTest {

    uint256 public fee;
    function setUp() public {
        uniswapTest();
        fee = 500;

    }


    function testDepositAndWithdraw() public {
        
        uint256 initBalanceUsdc = USDC.balanceOf(facticeUser1);
        uint256 initBalanceWeth = WETH.balanceOf(facticeUser1);

        vm.startPrank(facticeUser1);

        borrowerOperation.closePosition(facticeUser1_tokenId);

        vm.stopPrank();

        uint256 endBalanceUsdc = USDC.balanceOf(facticeUser1);
        uint256 endBalanceWeth = WETH.balanceOf(facticeUser1);

        assertEq(initBalanceUsdc, endBalanceUsdc);
        assertEq(initBalanceWeth, endBalanceWeth);


    }


    //     //TODO: test deposit + borrow + check health factor

    // we now want to borrow GHO and check the health facto of the position
        function testDepositWithdrawAndCheckHealthFactor() public{



            vm.startPrank(facticeUser1);

            borrowerOperation.borrowGHO(1, facticeUser1_tokenId);

            vm.stopPrank();

        }


    //     //TODO: test deposit + borrow + can't withdraw if it would liquidate the position

    //     //TODO: test liquidation (change oracle price)

    //     function testNumberIs42() public {}

    //     function testFailSubtract43() public {}
}
