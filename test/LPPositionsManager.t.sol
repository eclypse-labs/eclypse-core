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

contract LPPositionsManagerTest is UniswapTest{
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
        uint256 initialDebt = lpPositionsManager.getPosition(facticeUser1_tokenId).debt;
        borrowerOperation.borrowGHO(10, facticeUser1_tokenId);
        uint256 currentDebt = lpPositionsManager.getPosition(facticeUser1_tokenId).debt;
        assertGt(currentDebt, initialDebt, "borrowing GHO should increase the debt");
        borrowerOperation.repayGHO(10, facticeUser1_tokenId);
        uint256 finalDebt = lpPositionsManager.getPosition(facticeUser1_tokenId).debt;
        assertLt(finalDebt, currentDebt, "repaying GHO should decrease the debt");
        assertEq(finalDebt, initialDebt, "repaying GHO should decrease the debt to the initial debt");
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
        vm.expectRevert(bytes("Cannot repay more GHO than the position's debt."));
        borrowerOperation.repayGHO(11, facticeUser1_tokenId);
        vm.stopPrank();
    }

    function testPositionStatus_closeByOwner() public {
        assertEq(uint(lpPositionsManager.getPosition(facticeUser1_tokenId).status), 1, "Position should be active");
        vm.startPrank(address(facticeUser1));
        borrowerOperation.closePosition(facticeUser1_tokenId);
        vm.stopPrank();
        assertEq(uint(lpPositionsManager.getPosition(facticeUser1_tokenId).status), 2, "Position should be closed by owner");
    }

    function testPositionStatus_closeByOwnerDebtNotRepaid() public {
        assertEq(uint(lpPositionsManager.getPosition(facticeUser1_tokenId).status), 1, "Position should be active");
        vm.startPrank(address(facticeUser1));
        borrowerOperation.borrowGHO(10, facticeUser1_tokenId);
        vm.expectRevert(bytes("you have to repay your debt"));
        borrowerOperation.closePosition(facticeUser1_tokenId);
        vm.stopPrank();
        assertEq(uint(lpPositionsManager.getPosition(facticeUser1_tokenId).status), 1, "Position should be active");
    }

    function testPositionStatus_closeByOwnerDebtRepaid() public {
        assertEq(uint(lpPositionsManager.getPosition(facticeUser1_tokenId).status), 1, "Position should be active");
        vm.startPrank(address(facticeUser1));
        borrowerOperation.borrowGHO(10, facticeUser1_tokenId);
        borrowerOperation.repayGHO(10, facticeUser1_tokenId);
        borrowerOperation.closePosition(facticeUser1_tokenId);
        vm.stopPrank();
        assertEq(uint(lpPositionsManager.getPosition(facticeUser1_tokenId).status), 2, "Position should be closed by owner");
    }

    function testPositionStatus_notExistent() public {
        assertEq(uint(lpPositionsManager.getPosition(0).status), 0, "Position should not exist");
    }

    function testRiskConstant_increase() public {
        //uint256 initialRC = lpPositionsManager.getRiskConstants(address(uniPoolUsdcETHAddr));
        uint256 newMinRC = FullMath.mulDiv(15, FixedPoint96.Q96, 10);
        lpPositionsManager.updateRiskConstants(address(uniPoolUsdcETHAddr), newMinRC);
        assertEq(lpPositionsManager.getRiskConstants(address(uniPoolUsdcETHAddr)), newMinRC, "Risk constant should be updated");
    }

    function testRiskConstant_decrease() public {
        uint256 setInitialRC = FullMath.mulDiv(2, FixedPoint96.Q96, 1);
        uint256 setNewMinRC = FullMath.mulDiv(15, FixedPoint96.Q96, 10);

        lpPositionsManager.updateRiskConstants(address(uniPoolUsdcETHAddr), setInitialRC);
        uint256 initialRC = lpPositionsManager.getRiskConstants(address(uniPoolUsdcETHAddr));

        lpPositionsManager.updateRiskConstants(address(uniPoolUsdcETHAddr), setNewMinRC);
        uint256 newMinRC = lpPositionsManager.getRiskConstants(address(uniPoolUsdcETHAddr));

        assertLt(newMinRC, initialRC, "Risk constant should be updated and decreased");
    }

    function testRiskConstant_setTo1() public {
        vm.expectRevert(bytes("The minimum collateral ratio must be greater than 1."));
        uint256 newMinRC = FullMath.mulDiv(1, FixedPoint96.Q96, 1);
        lpPositionsManager.updateRiskConstants(address(uniPoolUsdcETHAddr), newMinRC);
    }

    function testRiskConstant_setToLessThan1() public {
        vm.expectRevert(bytes("The minimum collateral ratio must be greater than 1."));
        uint256 newMinRC = FullMath.mulDiv(1, FixedPoint96.Q96, 10);
        lpPositionsManager.updateRiskConstants(address(uniPoolUsdcETHAddr), newMinRC);
    }

    function testPositionAmounts() view public {
        //(uint256 amount0, uint256 amount1) = lpPositionsManager.positionAmounts(facticeUser1_tokenId);
        address token0 = lpPositionsManager.getPosition(facticeUser1_tokenId).token0;
        console.log("Token0: ", token0);
        address token1 = lpPositionsManager.getPosition(facticeUser1_tokenId).token1;
        console.log(lpPositionsManager.priceInETH(token1));
        console.log(lpPositionsManager.priceInETH(token0));
        //uint256 priceInETH = lpPositionsManager.positionValueInETH(facticeUser1_tokenId);
        //console.log(priceInETH);
    }

    // function testLiquidatablePosition() public {
    //     uint256 _minCR = Math.mulDiv(15, 1 << 96, 10);
    //     lpPositionsManager.updateRiskConstants(address(uniPoolUsdcETHAddr), _minCR);
    //     vm.startPrank(address(user1));
    //     borrowerOperation.borrowGHO(10000, 549666);
    //     vm.stopPrank();
    //     assertTrue(lpPositionsManager.computeCR(549666) > _minCR);
    // }

    // function testLiquidatablePosition() public {
    //     uint256 _minCR = Math.mulDiv(15, 1 << 96, 10);
    //     lpPositionsManager.updateRiskConstants(address(uniPoolUsdcETHAddr),_minCR);

    //     console.log(lpPositionsManager.positionValueInETH(tokenIdUser1));
    //     console.log(
    //         "total supply of GHO before borrow: ",
    //         ghoToken.totalSupply()
    //     );
    //     console.log(
    //         "total debt of user1 before borrow: ",
    //         lpPositionsManager.totalDebtOf(user1)
    //     );
    //     vm.startPrank(address(user1));
    //     borrowerOperation.borrowGHO(10000, tokenIdUser1);
    //     vm.stopPrank();

    //     console.log(
    //         "user's cr after borrow: ",
    //         lpPositionsManager.computeCR(tokenIdUser1)
    //     );
    //     console.log("borrowed GHO : ", ghoToken.balanceOf(address(user1)));
    //     console.log(
    //         "total supply of GHO after borrow: ",
    //         ghoToken.totalSupply()
    //     );
    //     console.log(
    //         "total debt of user1 after borrow: ",
    //         lpPositionsManager.totalDebtOf(user1)
    //     );

    //     uint256 cr = lpPositionsManager.computeCR(tokenIdUser1);
    //     assertTrue(cr > _minCR);
    // }

    // function testTotalDebtOf() public {
    //     console.log(
    //         "debt of the user1 before borrow : ",
    //         lpPositionsManager.totalDebtOf(user1)
    //     );
    //     assertEq(lpPositionsManager.totalDebtOf(user1), 0);

    //     vm.startPrank(address(user1));
    //     borrowerOperation.borrowGHO(100, 549666);
    //     vm.stopPrank();
    //     console.log(
    //         "debt of the user1 after borrow : ",
    //         lpPositionsManager.totalDebtOf(user1)
    //     );
    //     assertEq(lpPositionsManager.totalDebtOf(user1), 100);
    // }

    // function testComputeCRWithDebtEqual0() public {
    //     console.log("CR of user1 is ", lpPositionsManager.computeCR(549666));
    // }

    // function testComputeCRWithDebtNotEqual0() public {
    //     vm.startPrank(address(user1));
    //     borrowerOperation.borrowGHO(10, 549666);
    //     vm.stopPrank();
    //     console.log("COLLATERAL VALUE : ", activePool.getCollateralValue());

    //     console.log("CR of user1 is ", lpPositionsManager.computeCR(549666));
    // }

    // function testRiskConstantsAreCorrectlyUpdated() public {
    //     console.log(
    //         "initial risk constant: ",
    //         lpPositionsManager.getRiskConstants(address(uniPoolUsdcETHAddr))
    //     );
    //     uint256 _minCR = Math.mulDiv(17, 1 << 96, 10);
    //     console.log("minCR calculated: ", _minCR);
    //     lpPositionsManager.updateRiskConstants(
    //         address(uniPoolUsdcETHAddr),
    //         _minCR
    //     );
    //     console.log(
    //         "updated risk constant: ",
    //         lpPositionsManager.getRiskConstants(address(uniPoolUsdcETHAddr))
    //     );
    //     assertEq(
    //         lpPositionsManager.getRiskConstants(address(uniPoolUsdcETHAddr)),
    //         _minCR,
    //         "risk constants are not updated correctly"
    //     );
    // }

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
        (uint a, uint b) = lpPositionsManager.positionAmounts(facticeUser1_tokenId);
        console.log("factice position amounts", a, b);
        console.log(lpPositionsManager.positionValueInETH(facticeUser1_tokenId) / 10**18);
        console.log(
            "total supply of GHO before borrow: ",
            ghoToken.totalSupply()
        );
        console.log(
            "total debt of facticeUser1 before borrow: ",
            lpPositionsManager.totalDebtOf(facticeUser1)
        );
        borrowerOperation.borrowGHO(10**18 * 633, facticeUser1_tokenId);
        vm.stopPrank();
        console.log(
            "user's cr after borrow: ",
            lpPositionsManager.computeCR(facticeUser1_tokenId)
        );
        console.log(
            "borrowed GHO : ",
            ghoToken.balanceOf(facticeUser1)
        );
        console.log(
            "total supply of GHO after borrow: ",
            ghoToken.totalSupply()
        );
        console.log(
            "total debt of user1 after borrow: ",
            lpPositionsManager.totalDebtOf(facticeUser1)
        );
        uint256 cr = lpPositionsManager.computeCR(facticeUser1_tokenId);
        assertTrue(cr > _minCR);
    }


    //     //TODO: test deposit + borrow + can't withdraw if it would liquidate the position

    //     //TODO: test liquidation (change oracle price)

    //     function testNumberIs42() public {}

    //     function testFailSubtract43() public {}
}
