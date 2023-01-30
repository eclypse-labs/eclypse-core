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

        assertFalse(lpPositionsManager.liquidatable(facticeUser1_tokenId));

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
        assertTrue(lpPositionsManager.liquidatable(facticeUser1_tokenId));
        vm.startPrank(address(facticeUser2));

        uint256 initialUSDCBalanceFacticeUser2 = USDC.balanceOf(address(facticeUser2));
        uint256 initialWETHBalanceFacticeUser2  = WETH.balanceOf(address(facticeUser2));

        uint256 initialUSDCBalanceActivePool = USDC.balanceOf(address(activePool));
        uint256 initialWETHBalanceActivePool = WETH.balanceOf(address(activePool));

        uint256 amountToRepay = lpPositionsManager.debtOf(facticeUser1_tokenId);
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

}

