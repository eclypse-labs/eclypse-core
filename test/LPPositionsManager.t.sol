//SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

import "forge-std/Test.sol";
import "../src/GHOToken.sol";
import "../src/BorrowerOperations.sol";
import "../src/ActivePool.sol";
import "../src/LPPositionsManager.sol";
import "@uniswap-core/interfaces/IUniswapV3Factory.sol";
import "@uniswap-core/interfaces/IUniswapV3Pool.sol";
import "@uniswap-periphery/interfaces/INonfungiblePositionManager.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "./UniswapTest.sol";

contract LPPositionsManagerTest is UniswapTest {
    uint256 public fee;

    function setUp() public {
        uniswapTest();
    }

    /*function testDepositAndWithdraw() public {
        uint256 initBalanceUsdc = USDC.balanceOf(facticeUser1);
        uint256 initBalanceWeth = WETH.balanceOf(facticeUser1);

        vm.startPrank(facticeUser1);

        borrowerOperation.closePosition(facticeUser1_tokenId);

        vm.stopPrank();

        uint256 endBalanceUsdc = USDC.balanceOf(facticeUser1);
        uint256 endBalanceWeth = WETH.balanceOf(facticeUser1);

        assertEq(initBalanceUsdc, endBalanceUsdc);
        assertEq(initBalanceWeth, endBalanceWeth);
    }*/

    //     //TODO: test deposit + borrow + check health factor

    // we now want to borrow GHO and check the health facto of the position
    // function testDepositWithdrawAndCheckHealthFactor() public {
    //     vm.startPrank(facticeUser1);

    //     console.log(address(facticeUser1));
    //     console.log(lpPositionsManager.getPosition(tokenId).user);
    //     borrowerOperation.borrowGHO(10**18 * 10, tokenId);

    //     vm.stopPrank();
    // }

    function testBorrowAndRepayGHO_wrongUserBorrow() public {
        vm.startPrank(address(facticeUser2));
        vm.expectRevert(bytes("You are not the owner of this position."));
        borrowerOperation.borrowGHO(10, facticeUser1_tokenId);
        vm.stopPrank();
    }

    function testBorrowAndRepayGHO_wrongUserRepay() public {
        vm.startPrank(address(facticeUser1));
        borrowerOperation.borrowGHO(10, facticeUser1_tokenId);
        vm.stopPrank();
        vm.startPrank(address(facticeUser2));
        vm.expectRevert(bytes("You are not the owner of this position."));
        borrowerOperation.repayGHO(10, facticeUser1_tokenId);
        vm.stopPrank();
    }

    function testBorrowAndRepayGHO_checkDebtEvolution() public {
        vm.startPrank(address(facticeUser1));
        uint256 initialDebt = lpPositionsManager
            .getPosition(facticeUser1_tokenId)
            .debt;
        borrowerOperation.borrowGHO(10, facticeUser1_tokenId);
        uint256 currentDebt = lpPositionsManager
            .getPosition(facticeUser1_tokenId)
            .debt;
        assertGt(
            currentDebt,
            initialDebt,
            "borrowing GHO should increase the debt"
        );
        borrowerOperation.repayGHO(10, facticeUser1_tokenId);
        uint256 finalDebt = lpPositionsManager
            .getPosition(facticeUser1_tokenId)
            .debt;
        assertLt(
            finalDebt,
            currentDebt,
            "repaying GHO should decrease the debt"
        );
        assertEq(
            finalDebt,
            initialDebt,
            "repaying GHO should decrease the debt to the initial debt"
        );
        vm.stopPrank();
    }

    function testBorrowAndRepayGHO_borrow0GHO() public {
        vm.startPrank(address(facticeUser1));
        vm.expectRevert(bytes("Cannot withdraw 0 GHO."));
        borrowerOperation.borrowGHO(0, facticeUser1_tokenId);
        vm.stopPrank();
    }

    function testBorrowAndRepayGHO_repay0GHO() public {
        vm.startPrank(address(facticeUser1));
        borrowerOperation.borrowGHO(10, facticeUser1_tokenId);
        vm.expectRevert(bytes("Cannot repay 0 GHO."));
        borrowerOperation.repayGHO(0, facticeUser1_tokenId);
        vm.stopPrank();
    }

    function testBorrowAndRepayGHO_repayMoreThanDebt() public {
        vm.startPrank(address(facticeUser1));
        borrowerOperation.borrowGHO(10, facticeUser1_tokenId);
        vm.expectRevert(
            bytes("Cannot repay more GHO than the position's debt.")
        );
        borrowerOperation.repayGHO(11, facticeUser1_tokenId);
        vm.stopPrank();
    }

    function testLiquidatablePosition() public {
        vm.startPrank(deployer);
        uint256 _minCR = Math.mulDiv(15, 1 << 96, 10);
        console.log("minCR calculated: ", _minCR);
        lpPositionsManager.updateRiskConstants(
            address(uniPoolUsdcETHAddr),
            _minCR
        );
        vm.stopPrank();

        vm.startPrank(address(facticeUser1));
        console.log(lpPositionsManager.positionValueInETH(facticeUser1_tokenId) / 10**18);
        console.log(
            "total supply of GHO before borrow: ",
            ghoToken.totalSupply() / ghoToken.decimals()
        );
        console.log(
            "total debt of facticeUser1 before borrow: ",
            lpPositionsManager.totalDebtOf(facticeUser1) / ghoToken.decimals()
        );
        borrowerOperation.borrowGHO(10000, facticeUser1_tokenId);
        vm.stopPrank();

        console.log(
            "user's cr after borrow: ",
            lpPositionsManager.computeCR(facticeUser1_tokenId) / (1 << 96)
        );
        console.log(
            "borrowed GHO : ",
            ghoToken.balanceOf(facticeUser1) / ghoToken.decimals()
        );
        console.log(
            "total supply of GHO after borrow: ",
            ghoToken.totalSupply() / ghoToken.decimals()
        );
        console.log(
            "total debt of user1 after borrow: ",
            lpPositionsManager.totalDebtOf(facticeUser1) / ghoToken.decimals()
        );

        uint256 cr = lpPositionsManager.computeCR(facticeUser1_tokenId);
        assertTrue(cr > _minCR);
    }

    //     //TODO: test deposit + borrow + can't withdraw if it would liquidate the position

    //     //TODO: test liquidation (change oracle price)

    //     function testNumberIs42() public {}

    //     function testFailSubtract43() public {}
}
