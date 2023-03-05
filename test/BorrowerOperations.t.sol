//SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

import "forge-std/Test.sol";

import "@uniswap-core/interfaces/IUniswapV3Factory.sol";
import "@uniswap-core/interfaces/IUniswapV3Pool.sol";
import "@uniswap-periphery/interfaces/INonfungiblePositionManager.sol";
import "./UniswapTest.sol";
import "@uniswap-periphery/interfaces/IQuoterV2.sol";

import {Errors} from "../contracts/utils/Errors.sol";

contract BorrowerOperationsTest is UniswapTest {
    uint256 public fee;

    function setUp() public {
        uniswapTest();
    }

    function testAddCollateralFuzz() public {
        vm.startPrank(address(facticeUser1));

        USDC.approve(address(eclypse), 100_000 ether);
        WETH.approve(address(eclypse), 100_000 ether);

        uint256 amountIn = 1 ether;

        bytes memory path = abi.encode(
            "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2", "500"
        );
        (
            uint256 amountOut,
            uint160[] memory sqrtPriceX96AfterList,
            uint32[] memory initializedTicksCrossedList,
            uint256 gasEstimate
        ) = quoter.quoteExactInput(path, amountIn);
        console.log(amountOut);

        uint128 initialLiquidity = eclypse.getPosition(facticeUser1_tokenId).liquidity;

        borrowerOperation.addCollateral(facticeUser1_tokenId, amountIn, amountOut);
        vm.stopPrank();

        uint128 endLiquidity = eclypse.getPosition(facticeUser1_tokenId).liquidity;
        assertGt(endLiquidity, initialLiquidity, "Adding collateral should increase liquidity");
    }

    function testAddCollateral() public {
        vm.startPrank(address(facticeUser1));

        USDC.approve(address(eclypse), 100_000 ether);
        WETH.approve(address(eclypse), 100_000 ether);

        uint128 initialLiquidity = eclypse.getPosition(facticeUser1_tokenId).liquidity;

        borrowerOperation.addCollateral(facticeUser1_tokenId, 10 ether, 10 ether);
        vm.stopPrank();

        uint128 endLiquidity = eclypse.getPosition(facticeUser1_tokenId).liquidity;
        assertGt(endLiquidity, initialLiquidity, "Adding collateral should increase liquidity");
    }

    function testAdd0Collateral() public {
        vm.expectRevert(Errors.AmountShouldBePositive.selector);
        vm.startPrank(address(facticeUser1));

        borrowerOperation.addCollateral(facticeUser1_tokenId, 0, 0);
        vm.stopPrank();
    }

    function testRemoveCollateral() public {
        vm.startPrank(address(facticeUser1));

        uint128 initialLiquidity = eclypse.getPosition(facticeUser1_tokenId).liquidity;

        borrowerOperation.removeCollateral(facticeUser1_tokenId, 1_000_000_000_000); //initial liquidity = 35_814_000_398_394
        vm.stopPrank();

        uint128 endLiquidity = eclypse.getPosition(facticeUser1_tokenId).liquidity;
        assertLt(endLiquidity, initialLiquidity, "removing collateral should decrease liquidity");
    }

    // function testRemoveCollateralWithUnactivePosition() public {
    //     vm.startPrank(address(facticeUser1));
    //     borrowerOperation.closePosition(facticeUser1_tokenId);

    //     vm.expectRevert();
    //     borrowerOperation.removeCollateral(facticeUser1_tokenId, 1_000_000_000_000);
    // }

    function testRemoveMoreThanActualLiquidity() public {
        vm.startPrank(address(facticeUser1));

        uint128 initialLiquidity = eclypse.getPosition(facticeUser1_tokenId).liquidity;

        uint128 liquidityToRemove = initialLiquidity + 1_000_000_000_000;
        vm.expectRevert(abi.encodeWithSelector(Errors.MustRemoveLessLiquidity.selector, liquidityToRemove, initialLiquidity));
        borrowerOperation.removeCollateral(facticeUser1_tokenId, liquidityToRemove);
        vm.stopPrank();
    }

    // function testRemoveCollateralMakesLiquidatable() public {
    //     vm.startPrank(deployer);
    //     uint256 _minCR = Math.mulDiv(16, FixedPoint96.Q96, 10);
    //     eclypse.updateRiskConstants(address(uniPoolUsdcETHAddr), _minCR);
    //     vm.stopPrank();

    //     vm.startPrank(address(facticeUser1));
    //     borrowerOperation.borrowGHO(100 * TOKEN18, facticeUser1_tokenId);

    //     uint128 initialLiquidity = eclypse.getPosition(facticeUser1_tokenId).liquidity;

    //     vm.expectRevert(bytes("Collateral Ratio cannot be lower than the minimum collateral ratio."));
    //     borrowerOperation.removeCollateral(facticeUser1_tokenId, initialLiquidity - 1_000_000_000_000);

    //     vm.stopPrank();
    // }

    //     function testChangeTicks() public {

    //     int24 initialLowerTick = lpPositionsManager.getPosition(facticeUser1_tokenId).tickLower;
    //     int24 initialUpperTick = lpPositionsManager.getPosition(facticeUser1_tokenId).tickUpper;

    //     int24 newLowerTick = initialLowerTick + 10;
    //     int24 newUpperTick = initialUpperTick + 10;
    //     vm.startPrank(address(facticeUser1));
    //     uint256 _newTokenId = borrowerOperation.changeTick(facticeUser1_tokenId, newLowerTick, newUpperTick);
    //     vm.stopPrank();

    //     assertEq(
    //         uint256(lpPositionsManager.getPosition(_newTokenId).status),
    //         1,
    //         "Position should be active."
    //     );
    //     assertEq(
    //         lpPositionsManager.getPosition(_newTokenId).tickLower,
    //         newLowerTick,
    //         "Position should have new lower tick."
    //     );
    //     assertEq(
    //         lpPositionsManager.getPosition(_newTokenId).tickUpper,
    //         newUpperTick,
    //         "Position should have new upper tick."
    //     );
    //     assertEq(
    //         uint256(
    //             lpPositionsManager.getPosition(facticeUser1_tokenId).status
    //         ),
    //         2,
    //         "Position should be closed by owner."
    //     );

    //     assertEq(
    //         lpPositionsManager.getPosition(facticeUser1_tokenId).debt,
    //         lpPositionsManager.getPosition(_newTokenId).debt,
    //         "Position should have same debt."
    //     );

    // }

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

    function testBorrowGHO() public {
        uint256 initialBalance = ghoToken.balanceOf(facticeUser1);
        vm.startPrank(address(facticeUser1));
        borrowerOperation.borrowGHO(10 * TOKEN18, facticeUser1_tokenId);
        vm.stopPrank();
        assertEq(ghoToken.balanceOf(facticeUser1), initialBalance + 10 * TOKEN18);
    }

    function testRepayGHO() public {
        uint256 initialBalance = ghoToken.balanceOf(facticeUser1);
        vm.startPrank(address(facticeUser1));
        borrowerOperation.borrowGHO(10 * TOKEN18, facticeUser1_tokenId);
        vm.stopPrank();
        vm.startPrank(address(facticeUser1));
        borrowerOperation.repayGHO(10 * TOKEN18, facticeUser1_tokenId);
        assertEq(ghoToken.balanceOf(facticeUser1), initialBalance);
        vm.stopPrank();
    }

    function testBorrowAndRepayGHO_wrongUserBorrow() public {
        vm.startPrank(address(facticeUser2));
        vm.expectRevert(abi.encodeWithSelector(Errors.NotOwnerOfPosition.selector, facticeUser1_tokenId));
        borrowerOperation.borrowGHO(10 * TOKEN18, facticeUser1_tokenId);
        vm.stopPrank();
    }

    function testBorrowAndRepayGHO_wrongUserRepay() public {
        vm.startPrank(address(facticeUser1));
        borrowerOperation.borrowGHO(10 * TOKEN18, facticeUser1_tokenId);
        vm.stopPrank();
        vm.startPrank(address(facticeUser2));
        vm.expectRevert(abi.encodeWithSelector(Errors.NotOwnerOfPosition.selector, facticeUser1_tokenId));
        borrowerOperation.repayGHO(10 * TOKEN18, facticeUser1_tokenId);
        vm.stopPrank();
    }

    function testBorrowAndRepayGHO_checkDebtEvolution() public {
        vm.startPrank(address(facticeUser1));
        uint256 initialDebt = eclypse.debtOf(facticeUser1_tokenId);

        borrowerOperation.borrowGHO(TOKEN18, facticeUser1_tokenId);
        uint256 currentDebt = eclypse.debtOf(facticeUser1_tokenId);
        assertGt(currentDebt, initialDebt, "Borrowing GHO should increase the debt.");
        vm.warp(block.timestamp + 365 days);
        uint256 afterYearDebt = eclypse.debtOf(facticeUser1_tokenId);

        assertGt(afterYearDebt, currentDebt, "Borrowing GHO should increase the debt.");

        deal(address(ghoToken), facticeUser1, (currentDebt * 51) / 50 + 1); // deal ourselves the interest to pay : 2% per year
        borrowerOperation.repayGHO(afterYearDebt, facticeUser1_tokenId);
        uint256 finalDebt = eclypse.debtOf(facticeUser1_tokenId);
        assertLt(finalDebt, afterYearDebt, "Repaying GHO should decrease the debt.");
        assertEq(finalDebt, initialDebt, "Repaying GHO should decrease the debt to the initial debt.");
        vm.stopPrank();
    }

    function testBorrowAndRepayGHO_borrow0GHO() public {
        uint256 initialBalance = ghoToken.balanceOf(facticeUser1);
        vm.startPrank(address(facticeUser1));
        vm.expectRevert(Errors.AmountShouldBePositive.selector);
        borrowerOperation.borrowGHO(0, facticeUser1_tokenId);
        assertEq(ghoToken.balanceOf(facticeUser1), initialBalance);
        vm.stopPrank();
    }

    function testBorrowAndRepayGHO_repay0GHO() public {
        vm.startPrank(address(facticeUser1));
        borrowerOperation.borrowGHO(10 * TOKEN18, facticeUser1_tokenId);
        vm.expectRevert(Errors.AmountShouldBePositive.selector);
        borrowerOperation.repayGHO(0, facticeUser1_tokenId);
        vm.stopPrank();
    }

    function testBorrowAndRepayGHO_repayMoreThanDebt() public {
        vm.startPrank(address(facticeUser1));
        borrowerOperation.borrowGHO(10 * TOKEN18, facticeUser1_tokenId);
        //vm.expectRevert(bytes("Cannot repay more GHO than the position's debt."));
        borrowerOperation.repayGHO(11 * TOKEN18, facticeUser1_tokenId);
        assertEq(eclypse.debtOf(facticeUser1_tokenId), 0);
        vm.stopPrank();
    }

    function testBorrowGHO_borrowMultipleTimes() public {
        vm.startPrank(address(facticeUser1));
        borrowerOperation.borrowGHO(10 * TOKEN18, facticeUser1_tokenId);
        assertEq(eclypse.debtOf(facticeUser1_tokenId), 10 * TOKEN18);
        borrowerOperation.borrowGHO(10 * TOKEN18, facticeUser1_tokenId);
        assertEq(eclypse.debtOf(facticeUser1_tokenId), 20 * TOKEN18);
        vm.stopPrank();
    }

    function testBorrowGHO_repayMultipleTimesExactAmounts() public {
        vm.startPrank(address(facticeUser1));
        borrowerOperation.borrowGHO(10 * TOKEN18, facticeUser1_tokenId);
        assertEq(eclypse.debtOf(facticeUser1_tokenId), 10 * TOKEN18);
        borrowerOperation.borrowGHO(10 * TOKEN18, facticeUser1_tokenId);
        assertEq(eclypse.debtOf(facticeUser1_tokenId), 20 * TOKEN18);
        borrowerOperation.repayGHO(10 * TOKEN18, facticeUser1_tokenId);

        assertEq(eclypse.debtOf(facticeUser1_tokenId), 10 * TOKEN18);
        borrowerOperation.repayGHO(10 * TOKEN18, facticeUser1_tokenId);
        assertEq(eclypse.debtOf(facticeUser1_tokenId), 0);
        vm.stopPrank();
    }

    function testBorrowGHO_repayMultipleTimesNotExactAmounts() public {
        vm.startPrank(address(facticeUser1));
        borrowerOperation.borrowGHO(10 * TOKEN18, facticeUser1_tokenId);
        assertEq(eclypse.debtOf(facticeUser1_tokenId), 10 * TOKEN18, "Debt should be 10 GHO.");
        assertEq(eclypse.getProtocolValues().totalBorrowedGho, 10 * TOKEN18, "GHO debt should be 10 GHO.");
        borrowerOperation.borrowGHO(10 * TOKEN18, facticeUser1_tokenId);
        assertEq(eclypse.debtOf(facticeUser1_tokenId), 20 * TOKEN18, "Debt should be 20 GHO.");
        assertEq(eclypse.getProtocolValues().totalBorrowedGho, 20 * TOKEN18, "GHO debt should be 20 GHO.");
        borrowerOperation.repayGHO(5 * TOKEN18, facticeUser1_tokenId);
        assertEq(eclypse.debtOf(facticeUser1_tokenId), 15 * TOKEN18, "Debt should be 15 GHO.");
        vm.stopPrank();
    }

    function testBorrowGHO_borrowMultiplePositions() public {
        vm.startPrank(address(facticeUser1));
        borrowerOperation.borrowGHO(10 * TOKEN18, facticeUser1_tokenId);
        assertEq(eclypse.debtOf(facticeUser1_tokenId), 10 * TOKEN18);
        borrowerOperation.borrowGHO(10 * TOKEN18, facticeUser1_tokenId2);
        assertEq(eclypse.debtOf(facticeUser1_tokenId2), 10 * TOKEN18);
        vm.stopPrank();
    }

    function testBorrowGHO_repayMultiplePositions() public {
        vm.startPrank(address(facticeUser1));
        borrowerOperation.borrowGHO(10 * TOKEN18, facticeUser1_tokenId);
        assertEq(eclypse.debtOf(facticeUser1_tokenId), 10 * TOKEN18);
        borrowerOperation.borrowGHO(10 * TOKEN18, facticeUser1_tokenId2);
        assertEq(eclypse.debtOf(facticeUser1_tokenId2), 10 * TOKEN18);
        borrowerOperation.repayGHO(10 * TOKEN18, facticeUser1_tokenId);
        assertEq(eclypse.debtOf(facticeUser1_tokenId), 0);
        borrowerOperation.repayGHO(10 * TOKEN18, facticeUser1_tokenId2);
        assertEq(eclypse.debtOf(facticeUser1_tokenId2), 0);
        vm.stopPrank();
    }
}
