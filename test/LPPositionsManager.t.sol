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
        borrowerOperation.repayGHO(10, facticeUser1_tokenId);
        assertEq(lpPositionsManager.debtOf(facticeUser1_tokenId), 0);
        vm.stopPrank();
    }

    function testBorrowAndRepayGHO_checkDebtEvolution() public {
        vm.startPrank(address(facticeUser1));
        uint256 initialDebt = lpPositionsManager.debtOf(facticeUser1_tokenId);

        borrowerOperation.borrowGHO(10**18, facticeUser1_tokenId);
        uint256 currentDebt = lpPositionsManager.debtOf(facticeUser1_tokenId);
        assertGt(
            currentDebt,
            initialDebt,
            "Borrowing GHO should increase the debt."
        );
        vm.warp(block.timestamp + 365 days);
        uint256 afterYearDebt = lpPositionsManager.debtOf(facticeUser1_tokenId);
        deal(address(ghoToken), facticeUser1, currentDebt * 51/50 + 1); // deal ourselves the interest to pay : 2% per year
        borrowerOperation.repayGHO(afterYearDebt, facticeUser1_tokenId);
        uint256 finalDebt = lpPositionsManager.debtOf(facticeUser1_tokenId);
        assertLt(
            finalDebt,
            afterYearDebt,
            "Repaying GHO should decrease the debt."
        );
        assertEq(
            finalDebt,
            initialDebt,
            "Repaying GHO should decrease the debt to the initial debt."
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
        //vm.expectRevert(bytes("Cannot repay more GHO than the position's debt."));
        borrowerOperation.repayGHO(11, facticeUser1_tokenId);
        assertEq(lpPositionsManager.debtOf(facticeUser1_tokenId), 0);
        vm.stopPrank();
    }

    function testPositionStatus_changeToCurrentOne() public {
        assertEq(
            uint256(
                lpPositionsManager.getPosition(facticeUser1_tokenId).status
            ),
            1,
            "Position should be active."
        );
        vm.startPrank(address(borrowerOperation));
        vm.expectRevert(bytes("A position status cannot be changed to its current one."));
        lpPositionsManager.changePositionStatus(facticeUser1_tokenId, ILPPositionsManager.Status.active);
        vm.stopPrank();
    }

    function testPositionStatus_closeByOwner() public {
        assertEq(
            uint256(
                lpPositionsManager.getPosition(facticeUser1_tokenId).status
            ),
            1,
            "Position should be active."
        );
        vm.startPrank(address(facticeUser1));
        borrowerOperation.closePosition(facticeUser1_tokenId);
        vm.stopPrank();
        assertEq(
            uint256(
                lpPositionsManager.getPosition(facticeUser1_tokenId).status
            ),
            2,
            "Position should be closed by owner."
        );
    }

    function testPositionStatus_closeByOwnerDebtNotRepaid() public {
        assertEq(
            uint256(
                lpPositionsManager.getPosition(facticeUser1_tokenId).status
            ),
            1,
            "Position should be active."
        );
        vm.startPrank(address(facticeUser1));
        borrowerOperation.borrowGHO(10, facticeUser1_tokenId);
        vm.expectRevert(bytes("Debt is not repaid."));
        borrowerOperation.closePosition(facticeUser1_tokenId);
        vm.stopPrank();
        assertEq(
            uint256(
                lpPositionsManager.getPosition(facticeUser1_tokenId).status
            ),
            1,
            "Position should be active."
        );
    }

    function testPositionStatus_closeByOwnerDebtRepaid() public {
        assertEq(
            uint256(
                lpPositionsManager.getPosition(facticeUser1_tokenId).status
            ),
            1,
            "Position should be active."
        );
        vm.startPrank(address(facticeUser1));
        borrowerOperation.borrowGHO(10, facticeUser1_tokenId);
        borrowerOperation.repayGHO(10, facticeUser1_tokenId);
        borrowerOperation.closePosition(facticeUser1_tokenId);
        vm.stopPrank();
        assertEq(
            uint256(
                lpPositionsManager.getPosition(facticeUser1_tokenId).status
            ),
            2,
            "Position should be closed by owner."
        );
    }

    function testPositionStatus_notExistent() public {
        assertEq(
            uint256(lpPositionsManager.getPosition(0).status),
            0,
            "Position should not exist."
        );
    }

    function testRiskConstant_increase() public {
        uint256 newMinRC = FullMath.mulDiv(15, FixedPoint96.Q96, 10);
        lpPositionsManager.updateRiskConstants(
            address(uniPoolUsdcETHAddr),
            newMinRC
        );

        assertEq(
            lpPositionsManager.getRiskConstants(address(uniPoolUsdcETHAddr)),
            newMinRC,
            "Risk constant should be updated."
        );
    }

    function testRiskConstant_decrease() public {
        uint256 setInitialRC = FullMath.mulDiv(2, FixedPoint96.Q96, 1);
        uint256 setNewMinRC = FullMath.mulDiv(15, FixedPoint96.Q96, 10);

        lpPositionsManager.updateRiskConstants(
            address(uniPoolUsdcETHAddr),
            setInitialRC
        );
        uint256 initialRC = lpPositionsManager.getRiskConstants(
            address(uniPoolUsdcETHAddr)
        );

        lpPositionsManager.updateRiskConstants(
            address(uniPoolUsdcETHAddr),
            setNewMinRC
        );
        uint256 newMinRC = lpPositionsManager.getRiskConstants(
            address(uniPoolUsdcETHAddr)
        );

        assertLt(
            newMinRC,
            initialRC,
            "Risk constant should be updated and decreased."
        );
    }

    function testRiskConstant_setTo1() public {
        vm.expectRevert(
            bytes("The minimum collateral ratio must be greater than 1.")
        );
        uint256 newMinRC = FullMath.mulDiv(1, FixedPoint96.Q96, 1);
        lpPositionsManager.updateRiskConstants(
            address(uniPoolUsdcETHAddr),
            newMinRC
        );
    }

    function testRiskConstant_setToLessThan1() public {
        vm.expectRevert(
            bytes("The minimum collateral ratio must be greater than 1.")
        );
        uint256 newMinRC = FullMath.mulDiv(1, FixedPoint96.Q96, 10);
        lpPositionsManager.updateRiskConstants(
            address(uniPoolUsdcETHAddr),
            newMinRC
        );
    }

    function testRiskConstantsAreCorrectlyUpdated() public {
        uint256 _minCR = Math.mulDiv(17, 1 << 96, 10);
        lpPositionsManager.updateRiskConstants(
            address(uniPoolUsdcETHAddr),
            _minCR
        );

        assertEq(
            lpPositionsManager.getRiskConstants(address(uniPoolUsdcETHAddr)),
            _minCR,
            "Risk constants are not updated correctly."
        );
    }

    function testLiquidatablePosition() public {
        vm.startPrank(deployer);
        uint256 _minCR = Math.mulDiv(15, 1 << 96, 10);
        lpPositionsManager.updateRiskConstants(
            address(uniPoolUsdcETHAddr),
            _minCR
        );
        vm.stopPrank();
        vm.startPrank(address(facticeUser1));
        borrowerOperation.borrowGHO(10**18 * 633, facticeUser1_tokenId);
        vm.stopPrank();

        uint256 cr = lpPositionsManager.computeCR(facticeUser1_tokenId);
        assertTrue(cr > _minCR);
    }

    function testLiquidate() public {
        vm.startPrank(address(facticeUser1));
        borrowerOperation.borrowGHO(10**18 * 1000, facticeUser1_tokenId);
        vm.stopPrank();

        vm.startPrank(deployer);
        uint256 _minCR = Math.mulDiv(15, 1 << 96, 10);
        lpPositionsManager.updateRiskConstants(
            address(uniPoolUsdcETHAddr),
            _minCR
        );
        vm.stopPrank();

        assertTrue(lpPositionsManager.liquidatable(
            facticeUser1_tokenId
        ));

        vm.startPrank(address(facticeUser2));

        uint256 initialUSDCBalanceFacticeUser2 = USDC.balanceOf(address(facticeUser2));
        uint256 initialWETHBalanceFacticeUser2  = WETH.balanceOf(address(facticeUser2));

        uint256 initialUSDCBalanceActivePool = USDC.balanceOf(address(activePool));
        uint256 initialWETHBalanceActivePool = WETH.balanceOf(address(activePool));

        uint256 amountToRepay = lpPositionsManager.totalDebtOf(facticeUser1);
        assertGe(ghoToken.balanceOf(address(facticeUser2)), amountToRepay);
        lpPositionsManager.liquidate(facticeUser1_tokenId, amountToRepay);
        vm.stopPrank();

        assertEq(
            uint256(lpPositionsManager.getPosition(facticeUser1_tokenId).status),
            3,
            "Position should be closed by liquidation."
        );

        uint256 finalUSDCBalanceFacticeUser2  = USDC.balanceOf(address(facticeUser2));
        uint256 finalWETHBalanceFacticeUser2  = WETH.balanceOf(address(facticeUser2));

        uint256 finalUSDCBalanceActivePool = USDC.balanceOf(address(activePool));
        uint256 finalWETHBalanceActivePool = WETH.balanceOf(address(activePool));

        assertGe(finalUSDCBalanceFacticeUser2 , initialUSDCBalanceActivePool );
        assertGe(finalWETHBalanceFacticeUser2 , initialWETHBalanceActivePool );

        assertGe(finalUSDCBalanceActivePool , initialUSDCBalanceFacticeUser2 );
        assertGe(finalWETHBalanceActivePool , initialWETHBalanceFacticeUser2 );
    }


    function testLiquidate_swap() public {
        vm.startPrank(deployer);
        uint256 _minCR = Math.mulDiv(15, 1 << 96, 10);
        lpPositionsManager.updateRiskConstants(
            address(uniPoolUsdcETHAddr),
            _minCR
        );
        vm.stopPrank();

        vm.startPrank(address(facticeUser1));
        borrowerOperation.borrowGHO(10**18 * 633, facticeUser1_tokenId);
        vm.stopPrank();


        console.log("Pass 1");
        assertFalse(lpPositionsManager.liquidatable(facticeUser1_tokenId));

        console.log("Pass 2");
        vm.startPrank(deployer);

        deal(address(USDC), deployer, 10**18 * 1_000_000 * 2);
        deal(deployer, 300_000 ether);

        USDC.approve(swapRouterAddr, 10**18 * 1_000_000 * 2);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: usdcAddr,
                tokenOut: wethAddr,
                fee: 500,
                recipient: deployer,
                deadline: block.timestamp + 5 minutes,
                amountIn: 10**18 * 1000000,
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

        console.log("Pass 3");
        assertTrue(lpPositionsManager.liquidatable(facticeUser1_tokenId));
        console.log("Pass 4");

        vm.startPrank(address(facticeUser2));

        uint256 initialUSDCBalanceFacticeUser2 = USDC.balanceOf(address(facticeUser2));
        uint256 initialWETHBalanceFacticeUser2  = WETH.balanceOf(address(facticeUser2));

        uint256 initialUSDCBalanceActivePool = USDC.balanceOf(address(activePool));
        uint256 initialWETHBalanceActivePool = WETH.balanceOf(address(activePool));

        uint256 amountToRepay = lpPositionsManager.debtOf(facticeUser1_tokenId);
        console.log("Pass 5");
        assertGe(ghoToken.balanceOf(address(facticeUser2)), amountToRepay);
        console.log("Pass 6");

        lpPositionsManager.liquidate(facticeUser1_tokenId, amountToRepay);
        vm.stopPrank();

        console.log("Pass 7");
        assertEq(
            uint256(lpPositionsManager.getPosition(facticeUser1_tokenId).status),
            3,
            "Position should be closed by liquidation."
        );
        console.log("Pass 8");

        uint256 finalUSDCBalanceFacticeUser2  = USDC.balanceOf(address(facticeUser2));
        uint256 finalWETHBalanceFacticeUser2  = WETH.balanceOf(address(facticeUser2));

        uint256 finalUSDCBalanceActivePool = USDC.balanceOf(address(activePool));
        uint256 finalWETHBalanceActivePool = WETH.balanceOf(address(activePool));

        console.log("Pass 9");
        assertGe(finalUSDCBalanceFacticeUser2 , initialUSDCBalanceActivePool );
        console.log("Pass 10");
        assertGe(finalWETHBalanceFacticeUser2 , initialWETHBalanceActivePool );
        console.log("Pass 11");
        assertGe(finalUSDCBalanceActivePool , initialUSDCBalanceFacticeUser2 );
        console.log("Pass 12");
        assertGe(finalWETHBalanceActivePool , initialWETHBalanceFacticeUser2 );

    }

    function testChangeTicks() public {
        
        int24 initialLowerTick = lpPositionsManager.getPosition(facticeUser1_tokenId).tickLower;
        int24 initialUpperTick = lpPositionsManager.getPosition(facticeUser1_tokenId).tickUpper;

        int24 newLowerTick = initialLowerTick + 10;
        int24 newUpperTick = initialUpperTick + 10;
        vm.startPrank(address(facticeUser1));
        uint256 _newTokenId = borrowerOperation.changeTick(facticeUser1_tokenId, newLowerTick, newUpperTick);
        vm.stopPrank();

        assertEq(
            uint256(lpPositionsManager.getPosition(_newTokenId).status),
            1,
            "Position should be active."
        );
        assertEq(
            lpPositionsManager.getPosition(_newTokenId).tickLower,
            newLowerTick,
            "Position should have new lower tick."
        );
        assertEq(
            lpPositionsManager.getPosition(_newTokenId).tickUpper,
            newUpperTick,
            "Position should have new upper tick."
        );
        assertEq(
            uint256(
                lpPositionsManager.getPosition(facticeUser1_tokenId).status
            ),
            2,
            "Position should be closed by owner."
        );

        assertEq(
            lpPositionsManager.getPosition(facticeUser1_tokenId).debt,
            lpPositionsManager.getPosition(_newTokenId).debt,
            "Position should have same debt."
        );

    }

    function testDecreaseLiquidity() public {
        vm.startPrank(address(facticeUser1));
        activePool.decreaseLiquidity(facticeUser1_tokenId, lpPositionsManager.getPosition(facticeUser1_tokenId).liquidity / 2);
        vm.stopPrank();
    }

    



}

