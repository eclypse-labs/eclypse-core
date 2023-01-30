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

contract BorrowerOperationsTest is UniswapTest {
    uint256 public fee;

    function setUp() public {
        uniswapTest();
    }

    function testAddCollateral() public {
        vm.startPrank(address(facticeUser1));

        USDC.approve(address(activePool), 100_000 ether);
        WETH.approve(address(activePool), 100_000 ether);

        uint128 initialLiquidity = lpPositionsManager
            .getPosition(facticeUser1_tokenId)
            .liquidity;

        borrowerOperation.addCollateral(
            facticeUser1_tokenId,
            10 ether,
            10 ether
        );
        vm.stopPrank();

        uint128 endLiquidity = lpPositionsManager
            .getPosition(facticeUser1_tokenId)
            .liquidity;
        assertGt(
            endLiquidity,
            initialLiquidity,
            "adding collateral should increase liquidity"
        );
    }

    function testRemoveCollateral() public {
        vm.startPrank(address(facticeUser1));

        uint128 initialLiquidity = lpPositionsManager
            .getPosition(facticeUser1_tokenId)
            .liquidity;

        borrowerOperation.removeCollateralToUser(
            facticeUser1_tokenId,
            1_000_000_000_000
        );
        vm.stopPrank();

        uint128 endLiquidity = lpPositionsManager
            .getPosition(facticeUser1_tokenId)
            .liquidity;
        assertLt(
            endLiquidity,
            initialLiquidity,
            "removing collateral should decrease liquidity"
        );
    }

    function testRemoveCollateralWithUnactivePosition() public {
        vm.startPrank(address(facticeUser1));
        borrowerOperation.closePosition(facticeUser1_tokenId);

        vm.expectRevert();
        borrowerOperation.removeCollateralToUser(
            facticeUser1_tokenId,
            1_000_000_000_000
        );
    }

    function testRemoveMoreThanActualLiquidity() public {
        vm.startPrank(address(facticeUser1));

        uint128 initialLiquidity = lpPositionsManager
            .getPosition(facticeUser1_tokenId)
            .liquidity;

        vm.expectRevert(bytes("You can't remove more liquidity than you have"));
        borrowerOperation.removeCollateralToUser(
            facticeUser1_tokenId,
            initialLiquidity + 1_000_000_000_000
        );
        vm.stopPrank();
    }

    function testRemoveCollateralMakesLiquidatable() public {
        vm.startPrank(deployer);
        uint256 _minCR = Math.mulDiv(16, 1 << 96, 10);
        lpPositionsManager.updateRiskConstants(
            address(uniPoolUsdcETHAddr),
            _minCR
        );
        vm.stopPrank();

        vm.startPrank(address(facticeUser1));
        borrowerOperation.borrowGHO(10**18 * 100, facticeUser1_tokenId);

        uint128 initialLiquidity = lpPositionsManager
            .getPosition(facticeUser1_tokenId)
            .liquidity;

    
        vm.expectRevert(bytes("Collateral Ratio cannot be lower than the minimum collateral ratio."));
        borrowerOperation.removeCollateralToUser(
            facticeUser1_tokenId,
            initialLiquidity - 1_000_000_000_000
        );

        vm.stopPrank();
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
}
