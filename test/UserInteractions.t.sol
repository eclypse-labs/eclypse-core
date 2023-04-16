//SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

import "forge-std/Test.sol";

import "@uniswap-core/interfaces/IUniswapV3Factory.sol";
import "@uniswap-core/interfaces/IUniswapV3Pool.sol";
import "@uniswap-periphery/interfaces/INonfungiblePositionManager.sol";
import "./UniswapTest.sol";
import "@uniswap-periphery/interfaces/IQuoterV2.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/utils/math/SignedMath.sol";

import "./FakePriceFeed.sol";

import { Errors } from "../contracts/utils/Errors.sol";

contract UserInteractionsTest is UniswapTest {
	uint256 public fee;

	function setUp() public {
		uniswapTest();
	}

	// function testAddCollateralFuzz() public {
	// 	vm.startPrank(address(facticeUser1));

	// 	USDC.approve(address(eclypseVault), 100_000 ether);
	// 	WETH.approve(address(eclypseVault), 100_000 ether);

	// 	uint256 amountIn = 1 ether;
	// 	console.log("INSIDE");
	// 	bytes memory path = abi.encode("0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2", "500");
	// 	console.log("ABI ENCODE SUCCESS");
	// 	(uint256 amountOut, uint160[] memory sqrtPriceX96AfterList, uint32[] memory initializedTicksCrossedList, uint256 gasEstimate) = quoter
	// 		.quoteExactInput(path, amountIn);
	// 	console.log(amountOut);

	// 	uint128 initialLiquidity = positionsManager.getPosition(facticeUser1_tokenId).liquidity;

	// 	userInteractions.deposit(amountIn, amountOut, facticeUser1_tokenId);
	// 	vm.stopPrank();

	// 	uint128 endLiquidity = positionsManager.getPosition(facticeUser1_tokenId).liquidity;
	// 	assertGt(endLiquidity, initialLiquidity, "Adding collateral should increase liquidity");
	// }

	function testAddCollateral() public {
		vm.startPrank(address(facticeUser1));

		USDC.approve(address(eclypseVault), 100_000 ether);
		WETH.approve(address(eclypseVault), 100_000 ether);

		uint128 initialLiquidity = positionsManager.getPosition(facticeUser1_tokenId).liquidity;

		userInteractions.deposit(10 ether, 10 ether, facticeUser1_tokenId);
		vm.stopPrank();

		uint128 endLiquidity = positionsManager.getPosition(facticeUser1_tokenId).liquidity;
		assertGt(endLiquidity, initialLiquidity, "Adding collateral should increase liquidity");
	}

	function testAdd0Collateral() public {
		vm.expectRevert(Errors.AmountShouldBePositive.selector);
		vm.startPrank(address(facticeUser1));

		userInteractions.deposit(0, 0, facticeUser1_tokenId);
		vm.stopPrank();
	}

	function testRemoveCollateral() public {
		vm.startPrank(address(facticeUser1));

		uint128 initialLiquidity = positionsManager.getPosition(facticeUser1_tokenId).liquidity;

		userInteractions.withdraw(1_000_000_000_000, facticeUser1_tokenId); //initial liquidity = 35_814_000_398_394
		vm.stopPrank();

		uint128 endLiquidity = positionsManager.getPosition(facticeUser1_tokenId).liquidity;
		assertLt(endLiquidity, initialLiquidity, "removing collateral should decrease liquidity");
	}

	// function testRemoveCollateralWithUnactivePosition() public {
	//     vm.startPrank(address(facticeUser1));
	//     borrowerOperation.closePosition(facticeUser1_tokenId);

	//     vm.expectRevert();
	//     borrowerOperation.removeCollateral(facticeUser1_tokenId, 1_000_000_000_000);
	// }

	// function testRemoveMoreThanActualLiquidity() public {
	// 	vm.startPrank(address(facticeUser1));

	// 	uint128 initialLiquidity = positionsManager.getPosition(facticeUser1_tokenId).liquidity;

	// 	uint128 liquidityToRemove = initialLiquidity + 1_000_000_000_000;
	// 	vm.expectRevert(abi.encodeWithSelector(Errors.MustRemoveLessLiquidity.selector, liquidityToRemove, initialLiquidity));
	// 	userInteractions.withdraw(liquidityToRemove, facticeUser1_tokenId);
	// 	vm.stopPrank();
	// }

	// function testRemoveCollateralMakesLiquidatable() public {
	//     vm.startPrank(deployer);
	//     uint256 _minCR = Math.mulDiv(16, FixedPoint96.Q96, 10);
	//     lpPositionsManager.updateRiskConstants(address(uniPoolUsdcETHAddr), _minCR);
	//     vm.stopPrank();

	//     vm.startPrank(address(facticeUser1));
	//     borrowerOperation.borrowGHO(100 * TOKEN18, facticeUser1_tokenId);

	//     uint128 initialLiquidity = lpPositionsManager.getPosition(facticeUser1_tokenId).liquidity;

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

		userInteractions.closePosition(facticeUser1_tokenId);

		vm.stopPrank();

		uint256 endBalanceUsdc = USDC.balanceOf(facticeUser1);
		uint256 endBalanceWeth = WETH.balanceOf(facticeUser1);

		assertEq(initBalanceUsdc, endBalanceUsdc);
		assertEq(initBalanceWeth, endBalanceWeth);
	}

	function testBorrow() public {
		uint256 initialBalance = ghoToken.balanceOf(facticeUser1);
		vm.startPrank(address(facticeUser1));

		userInteractions.borrow(10 * TOKEN18, facticeUser1_tokenId);

		vm.stopPrank();
		assertEq(ghoToken.balanceOf(facticeUser1), initialBalance + 10 * TOKEN18);
	}

	function testRepay() public {
		uint256 initialBalance = ghoToken.balanceOf(facticeUser1);
		vm.startPrank(address(facticeUser1));
		userInteractions.borrow(10 * TOKEN18, facticeUser1_tokenId);
		vm.stopPrank();
		vm.startPrank(address(facticeUser1));
		userInteractions.repay(10 * TOKEN18, facticeUser1_tokenId);
		assertEq(ghoToken.balanceOf(facticeUser1), initialBalance);
		vm.stopPrank();
	}

	function testBorrowAndRepayGHO_wrongUserBorrow() public {
		vm.startPrank(address(facticeUser2));
		vm.expectRevert(abi.encodeWithSelector(Errors.NotOwnerOfPosition.selector, facticeUser1_tokenId));
		userInteractions.borrow(10 * TOKEN18, facticeUser1_tokenId);
		vm.stopPrank();
	}

	function testBorrowAndRepayGHO_wrongUserRepay() public {
		vm.startPrank(address(facticeUser1));
		userInteractions.borrow(10 * TOKEN18, facticeUser1_tokenId);
		vm.stopPrank();
		vm.startPrank(address(facticeUser2));
		vm.expectRevert(abi.encodeWithSelector(Errors.NotOwnerOfPosition.selector, facticeUser1_tokenId));
		userInteractions.repay(10 * TOKEN18, facticeUser1_tokenId);
		vm.stopPrank();
	}

	function testBorrowAndRepayGHO_checkDebtEvolution() public {
		vm.startPrank(address(facticeUser1));

		uint256 initialDebt = positionsManager.debtOf(facticeUser1_tokenId);

		userInteractions.borrow(TOKEN18, facticeUser1_tokenId);
		uint256 currentDebt = positionsManager.debtOf(facticeUser1_tokenId);
		assertGt(currentDebt, initialDebt, "Borrowing GHO should increase the debt.");
		vm.warp(block.timestamp + 365 days);
		uint256 afterYearDebt = positionsManager.debtOf(facticeUser1_tokenId);

		assertGt(afterYearDebt, currentDebt, "Borrowing GHO should increase the debt.");

		deal(address(ghoToken), facticeUser1, (currentDebt * 51) / 50 + 1); // deal ourselves the interest to pay : 2% per year
		userInteractions.repay(afterYearDebt, facticeUser1_tokenId);
		uint256 finalDebt = positionsManager.debtOf(facticeUser1_tokenId);
		assertLt(finalDebt, afterYearDebt, "Repaying GHO should decrease the debt.");
		assertEq(finalDebt, initialDebt, "Repaying GHO should decrease the debt to the initial debt.");
		vm.stopPrank();
	}

	function testBorrowAndRepayGHO_borrow0GHO() public {
		uint256 initialBalance = ghoToken.balanceOf(facticeUser1);
		vm.startPrank(address(facticeUser1));
		vm.expectRevert(Errors.AmountShouldBePositive.selector);
		userInteractions.borrow(0, facticeUser1_tokenId);
		assertEq(ghoToken.balanceOf(facticeUser1), initialBalance);
		vm.stopPrank();
	}

	function testBorrowAndRepayGHO_repay0GHO() public {
		vm.startPrank(address(facticeUser1));
		userInteractions.borrow(10 * TOKEN18, facticeUser1_tokenId);
		vm.expectRevert(Errors.AmountShouldBePositive.selector);
		userInteractions.repay(0, facticeUser1_tokenId);
		vm.stopPrank();
	}

	function testBorrowAndRepayGHO_repayMoreThanDebt() public {
		vm.startPrank(address(facticeUser1));
		userInteractions.borrow(10 * TOKEN18, facticeUser1_tokenId);
		//vm.expectRevert(bytes("Cannot repay more GHO than the position's debt."));
		userInteractions.repay(11 * TOKEN18, facticeUser1_tokenId);
		assertEq(positionsManager.debtOf(facticeUser1_tokenId), 0);
		vm.stopPrank();
	}

	function testBorrowGHO_borrowMultipleTimes() public {
		vm.startPrank(address(facticeUser1));
		userInteractions.borrow(10 * TOKEN18, facticeUser1_tokenId);
		assertEq(positionsManager.debtOf(facticeUser1_tokenId), 10 * TOKEN18);
		userInteractions.borrow(10 * TOKEN18, facticeUser1_tokenId);
		assertEq(positionsManager.debtOf(facticeUser1_tokenId), 20 * TOKEN18);
		vm.stopPrank();
	}

	function testBorrowGHO_repayMultipleTimesExactAmounts() public {
		vm.startPrank(address(facticeUser1));
		userInteractions.borrow(10, facticeUser1_tokenId);
		assertEq(positionsManager.debtOf(facticeUser1_tokenId), 10);
		userInteractions.borrow(10, facticeUser1_tokenId);
		assertEq(positionsManager.debtOf(facticeUser1_tokenId), 20);
		userInteractions.repay(10, facticeUser1_tokenId);

		assertEq(positionsManager.debtOf(facticeUser1_tokenId), 10);
		userInteractions.repay(10, facticeUser1_tokenId);
		assertEq(positionsManager.debtOf(facticeUser1_tokenId), 0);
		vm.stopPrank();
	}

	function testBorrowGHO_repayMultipleTimesNotExactAmounts() public {
		vm.startPrank(address(facticeUser1));
		userInteractions.borrow(10 * TOKEN18, facticeUser1_tokenId);
		console.log("Debt after first borrow: %s", positionsManager.debtOf(facticeUser1_tokenId));
		assertEq(positionsManager.debtOf(facticeUser1_tokenId), 10 * TOKEN18, "Debt should be 10 GHO.");

		assertEq(positionsManager.getAssetsValues(address(ghoToken)).totalBorrowedStableCoin, 10 * TOKEN18, "GHO debt should be 10 GHO.");
		userInteractions.borrow(10 * TOKEN18, facticeUser1_tokenId);
		assertEq(positionsManager.debtOf(facticeUser1_tokenId), 20 * TOKEN18, "Debt should be 20 GHO.");
		assertEq(positionsManager.getAssetsValues(address(ghoToken)).totalBorrowedStableCoin, 20 * TOKEN18, "GHO debt should be 20 GHO.");
		userInteractions.repay(5 * TOKEN18, facticeUser1_tokenId);
		assertEq(positionsManager.debtOf(facticeUser1_tokenId), 15 * TOKEN18, "Debt should be 15 GHO.");
		vm.stopPrank();
	}

	function testBorrowGHO_borrowMultiplePositions() public {
		vm.startPrank(address(facticeUser1));
		userInteractions.borrow(10 * TOKEN18, facticeUser1_tokenId);
		assertEq(positionsManager.debtOf(facticeUser1_tokenId), 10 * TOKEN18);
		userInteractions.borrow(10 * TOKEN18, facticeUser1_tokenId2);
		assertEq(positionsManager.debtOf(facticeUser1_tokenId2), 10 * TOKEN18);
		vm.stopPrank();
	}

	function testBorrowGHO_repayMultiplePositions() public {
		vm.startPrank(address(facticeUser1));
		userInteractions.borrow(10 * TOKEN18, facticeUser1_tokenId);
		assertEq(positionsManager.debtOf(facticeUser1_tokenId), 10 * TOKEN18);
		userInteractions.borrow(10 * TOKEN18, facticeUser1_tokenId2);
		assertEq(positionsManager.debtOf(facticeUser1_tokenId2), 10 * TOKEN18);
		userInteractions.repay(10 * TOKEN18, facticeUser1_tokenId);
		assertEq(positionsManager.debtOf(facticeUser1_tokenId), 0);
		userInteractions.repay(10 * TOKEN18, facticeUser1_tokenId2);
		assertEq(positionsManager.debtOf(facticeUser1_tokenId2), 0);
		vm.stopPrank();
	}

	function testLiquidatePositionUnderThreshold() public {
		vm.startPrank(address(deployer));
		fakePriceFeed.setEthUsdPrice(1200 * FixedPoint96.Q96);
		positionsManager.initialize(
			uniswapFactoryAddr,
			uniswapPositionsNFTAddr,
			address(userInteractions),
			address(eclypseVault),
			address(fakePriceFeed) // for testing purposes
		);
		vm.stopPrank();

		vm.startPrank(address(facticeUser1));
		uint256 positionValueInEth = positionsManager.positionValueInETH(facticeUser1_tokenId);
		userInteractions.borrow(750 * positionValueInEth, facticeUser1_tokenId);
		uint256 collRatio = (positionsManager.collRatioOf(facticeUser1_tokenId) * 100) / FixedPoint96.Q96;
		console.log("collRatio*100 : ", collRatio);
		vm.stopPrank();

		uint256 debt = positionsManager.debtOf(facticeUser1_tokenId);
		deal(address(ghoToken), address(facticeUser2), debt);

		vm.startPrank(address(facticeUser2));
		ghoToken.approve(address(positionsManager), debt);
		fakePriceFeed.setEthUsdPrice(300 * FixedPoint96.Q96); // set eth's price to 1$
		uint256 newCollRatio = (positionsManager.collRatioOf(facticeUser1_tokenId) * 100) / FixedPoint96.Q96;
		console.log("collRatioOf*100 after price change : ", newCollRatio);

		uint256 wethBal = WETH.balanceOf(address(facticeUser2));
		uint256 usdcBal = USDC.balanceOf(address(facticeUser2));
		uint256 ghoBal = ghoToken.balanceOf(address(facticeUser2));

		positionsManager.liquidatePosition(facticeUser1_tokenId, debt);
		// print balance of weth and gho

		uint256 newWethBal = WETH.balanceOf(address(facticeUser2));
		uint256 newUsdcBal = USDC.balanceOf(address(facticeUser2));
		uint256 newGhoBal = ghoToken.balanceOf(address(facticeUser2));

		assertGt(newWethBal, wethBal, "WETH balance should be greater than before.");
		assertGt(newUsdcBal, usdcBal, "USDC balance should be greater than before.");
		assertLt(newGhoBal, ghoBal, "GHO balance should be less than before.");

		if (newCollRatio >= 125) {
			// meaning we could only liquidate at most half of the position's debt.
			assertEq(positionsManager.debtOf(facticeUser1_tokenId), debt - debt / 2, "Debt should be half of the original debt.");
		} else {
			// meaning we could liquidate any amount of the position's debt, so the position should be closed.
			assertEq(positionsManager.debtOf(facticeUser1_tokenId), 0, "Debt should be 0.");
			assertEq(
				uint(positionsManager.getPosition(facticeUser1_tokenId).status),
				uint(IPositionsManager.Status.closedByLiquidation),
				"Position should be closed."
			);
		}
		vm.stopPrank();
	}

	function testLiquidatePositionAboveThreshold() public {
		vm.startPrank(address(deployer));
		fakePriceFeed.setEthUsdPrice(1200 * FixedPoint96.Q96);
		positionsManager.initialize(
			uniswapFactoryAddr,
			uniswapPositionsNFTAddr,
			address(userInteractions),
			address(eclypseVault),
			address(fakePriceFeed) // for testing purposes
		);
		vm.stopPrank();

		vm.startPrank(address(facticeUser1));
		uint256 positionValueInEth = positionsManager.positionValueInETH(facticeUser1_tokenId);
		userInteractions.borrow(750 * positionValueInEth, facticeUser1_tokenId);
		uint256 collRatio = (positionsManager.collRatioOf(facticeUser1_tokenId) * 100) / FixedPoint96.Q96;
		console.log("collRatio*100 : ", collRatio);
		vm.stopPrank();

		uint256 debt = positionsManager.debtOf(facticeUser1_tokenId);
		deal(address(ghoToken), address(facticeUser2), debt);

		vm.startPrank(address(facticeUser2));
		ghoToken.approve(address(positionsManager), debt);
		fakePriceFeed.setEthUsdPrice(800 * FixedPoint96.Q96); // set eth's price to 1$
		uint256 newCollRatio = (positionsManager.collRatioOf(facticeUser1_tokenId) * 100) / FixedPoint96.Q96;
		console.log("collRatioOf*100 after price change : ", newCollRatio);

		uint256 wethBal = WETH.balanceOf(address(facticeUser2));
		uint256 usdcBal = USDC.balanceOf(address(facticeUser2));
		uint256 ghoBal = ghoToken.balanceOf(address(facticeUser2));

		positionsManager.liquidatePosition(facticeUser1_tokenId, debt);
		// print balance of weth and gho

		uint256 newWethBal = WETH.balanceOf(address(facticeUser2));
		uint256 newUsdcBal = USDC.balanceOf(address(facticeUser2));
		uint256 newGhoBal = ghoToken.balanceOf(address(facticeUser2));

		assertGt(newWethBal, wethBal, "WETH balance should be greater than before.");
		assertGt(newUsdcBal, usdcBal, "USDC balance should be greater than before.");
		assertLt(newGhoBal, ghoBal, "GHO balance should be less than before.");

		if (newCollRatio >= 125) {
			// meaning we could only liquidate at most half of the position's debt.
			assertEq(positionsManager.debtOf(facticeUser1_tokenId), debt - debt / 2, "Debt should be half of the original debt.");
		} else {
			// meaning we could liquidate any amount of the position's debt, so the position should be closed.
			assertEq(positionsManager.debtOf(facticeUser1_tokenId), 0, "Debt should be 0.");
			assertEq(
				uint(positionsManager.getPosition(facticeUser1_tokenId).status),
				uint(IPositionsManager.Status.closedByLiquidation),
				"Position should be closed."
			);
		}
		vm.stopPrank();
	}

	function testLiquidateBadDebtRepayByMultipleLiquidators() public {
		vm.startPrank(address(deployer));
		fakePriceFeed.setEthUsdPrice(1200 * FixedPoint96.Q96);
		positionsManager.initialize(
			uniswapFactoryAddr,
			uniswapPositionsNFTAddr,
			address(userInteractions),
			address(eclypseVault),
			address(fakePriceFeed) // for testing purposes
		);
		vm.stopPrank();

		// 1 - FacticeUser1 creates a position and borrows GHO

		vm.startPrank(address(facticeUser1));
		uint256 positionValueInEth = positionsManager.positionValueInETH(facticeUser1_tokenId);
		userInteractions.borrow(750 * positionValueInEth, facticeUser1_tokenId);
		uint256 collRatio = (positionsManager.collRatioOf(facticeUser1_tokenId) * 100) / FixedPoint96.Q96;
		console.log("collRatio*100 : ", collRatio);
		vm.stopPrank();

		uint256 debt = positionsManager.debtOf(facticeUser1_tokenId);
		deal(address(ghoToken), address(facticeUser2), debt / 2); // This first liquidator will liquidate half of the debt

		// 2 - ETH price drops, FacticeUser1's position is liquidatable

		fakePriceFeed.setEthUsdPrice(300 * FixedPoint96.Q96);

		// 3 - FacticeUser2 starts liquidating half of the debt

		vm.startPrank(address(facticeUser2));
		ghoToken.approve(address(positionsManager), debt / 2);

		uint256 wethBalOfFacticeUser2 = WETH.balanceOf(address(facticeUser2));
		uint256 usdcBalOfFacticeUser2 = USDC.balanceOf(address(facticeUser2));
		uint256 ghoBalOfFacticeUser2 = ghoToken.balanceOf(address(facticeUser2));

		(uint256 usdcBeforeLiquidation1, uint256 wethBeforeLiquidation1) = positionsManager.positionAmounts(facticeUser1_tokenId);

		positionsManager.liquidatePosition(facticeUser1_tokenId, debt / 2);

		(uint256 usdcAfterLiquidation1, uint256 wethAfterLiquidation1) = positionsManager.positionAmounts(facticeUser1_tokenId);

		vm.stopPrank();

		//Verifying that FacticeUser2 got some WETH and USDC and lost some GHO
		assertGt(WETH.balanceOf(address(facticeUser2)), wethBalOfFacticeUser2, "WETH balance of FacticeUser2 should be greater than before.");
		assertGt(USDC.balanceOf(address(facticeUser2)), usdcBalOfFacticeUser2, "USDC balance of FacticeUser2 should be greater than before.");
		assertLt(ghoToken.balanceOf(address(facticeUser2)), ghoBalOfFacticeUser2, "GHO balance of FacticeUser2 should be less than before.");

		// Verifying that the position's debt is half of the original debt
		assertEq(positionsManager.debtOf(facticeUser1_tokenId), debt - debt / 2, "Debt should be half of the original debt.");

		// Verifying that the difference between its amount of USDC before the liquidation and its amount of USDC after the liquidation is < 0.1% as
		// expected. Meaning he lost half of the USDC he had in the position. The formula for a price difference < 0.1% is: Math.abs(a - b) * 1000 / a < 1
		assertTrue(
			(SignedMath.abs(SafeCast.toInt256(usdcBeforeLiquidation1 / 2) - SafeCast.toInt256(usdcAfterLiquidation1)) /
				(usdcBeforeLiquidation1 / 2)) *
				1000 <
				1
		);

		// Verifying that the difference between its amount of WETH before the liquidation and its amount of WETH after the liquidation is < 0.1% as
		// expected. Meaning he lost half of the WETH he had in the position. The formula for a price difference < 0.1% is: Math.abs(a - b) * 1000 / a < 1
		assertTrue(
			(SignedMath.abs(SafeCast.toInt256(wethBeforeLiquidation1 / 2) - SafeCast.toInt256(wethAfterLiquidation1)) /
				(wethBeforeLiquidation1 / 2)) *
				1000 <
				1
		);

		// 4 - FacticeUser3 starts liquidating the orther half of the debt

		vm.startPrank(address(facticeUser3));
		ghoToken.approve(address(positionsManager), debt / 2);

		uint256 wethBalOfFacticeUser3 = WETH.balanceOf(address(facticeUser3));
		uint256 usdcBalOfFacticeUser3 = USDC.balanceOf(address(facticeUser3));
		uint256 ghoBalOfFacticeUser3 = ghoToken.balanceOf(address(facticeUser3));

		positionsManager.liquidatePosition(facticeUser1_tokenId, debt / 2);

		//Verifying that FacticeUser3 got some WETH and USDC and lost some GHO
		assertGt(WETH.balanceOf(address(facticeUser3)), wethBalOfFacticeUser3, "WETH balance of FacticeUser3 should be greater than before.");
		assertGt(USDC.balanceOf(address(facticeUser3)), usdcBalOfFacticeUser3, "USDC balance of FacticeUser3 should be greater than before.");
		assertLt(ghoToken.balanceOf(address(facticeUser3)), ghoBalOfFacticeUser3, "GHO balance of FacticeUser3 should be less than before.");

		vm.stopPrank();

		// Verifying that the position's debt is 0
		assertEq(positionsManager.debtOf(facticeUser1_tokenId), 0, "Debt should be 0.");

		assertEq(
			uint(positionsManager.getPosition(facticeUser1_tokenId).status),
			uint(IPositionsManager.Status.closedByLiquidation),
			"Position should be closed."
		);
	}

	function testUpdateTicks() public {
		// test the updateTicks function
		
		// 1 - FacticeUser1 creates a position and borrows GHO

		vm.startPrank(address(facticeUser1));
		uint256 positionValueInEth = positionsManager.positionValueInETH(facticeUser1_tokenId);
		userInteractions.borrow(100 * positionValueInEth, facticeUser1_tokenId);

		// 2 - FacticeUser1 updates the ticks of their position
		// get the position
		IPositionsManager.Position memory position = positionsManager.getPosition(facticeUser1_tokenId);
		// get the current ticks
		int24 lowerTick = position.tickLower;
		int24 upperTick = position.tickUpper;
		// update the ticks
		userInteractions.updateTicks(facticeUser1_tokenId, lowerTick-10, upperTick+100);
	}
}
