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

    function testGetPositionsCount() public {
        assertEq(lpPositionsManager.getPositionsCount(), 1, "There should be 1 position.");
    }

    function testAmounts() public {
        (uint256 amount0, uint256 amount1) = lpPositionsManager.positionAmounts(facticeUser1_tokenId);
        console.log("amount0: %s", amount0);
        console.log("amount1: %s", amount1);
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
        borrowerOperation.borrowGHO( 1300 * TOKEN18, facticeUser1_tokenId);
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
        borrowerOperation.borrowGHO(10 * TOKEN18, facticeUser1_tokenId);
        borrowerOperation.repayGHO(10 * TOKEN18, facticeUser1_tokenId);
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

    function testPositionStatus_closedByLiquidation() public {
        vm.startPrank(address(facticeUser1));
        borrowerOperation.borrowGHO(1000 * TOKEN18, facticeUser1_tokenId);
        vm.stopPrank();

        vm.startPrank(deployer);
        uint256 _minCR = Math.mulDiv(15, FixedPoint96.Q96, 10);
        lpPositionsManager.updateRiskConstants(
            address(uniPoolUsdcETHAddr),
            _minCR
        );
        vm.stopPrank();

        assertTrue(lpPositionsManager.liquidatable(
            facticeUser1_tokenId
        ));

        vm.startPrank(address(facticeUser2));

        uint256 amountToRepay = lpPositionsManager.totalDebtOf(facticeUser1);
        assertGe(ghoToken.balanceOf(address(facticeUser2)), amountToRepay);
        lpPositionsManager.liquidate(facticeUser1_tokenId, amountToRepay);
        vm.stopPrank();

        assertEq(
            uint256(lpPositionsManager.getPosition(facticeUser1_tokenId).status),
            3,
            "Position should be closed by liquidation."
        );

    }

    function testRiskConstantsAreCorrectlyUpdated() public {
        uint256 _minCR = Math.mulDiv(17, FixedPoint96.Q96, 10);
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
    function testRiskConstant_increase() public {
        uint256 minRC = FullMath.mulDiv(13, FixedPoint96.Q96, 10);
        lpPositionsManager.updateRiskConstants(
            address(uniPoolUsdcETHAddr),
            minRC
        );

        uint256 initialMinRC = lpPositionsManager.getRiskConstants(address(uniPoolUsdcETHAddr));

        assertEq(
            lpPositionsManager.getRiskConstants(address(uniPoolUsdcETHAddr)),
            minRC,
            "Risk constant should be updated."
        );

        uint256 newMinRC = FullMath.mulDiv(15, FixedPoint96.Q96, 10);
        lpPositionsManager.updateRiskConstants(
            address(uniPoolUsdcETHAddr),
            newMinRC
        );

        uint256 EndMinRC = lpPositionsManager.getRiskConstants(address(uniPoolUsdcETHAddr));
    

        assertEq(
            lpPositionsManager.getRiskConstants(address(uniPoolUsdcETHAddr)),
            newMinRC,
            "Risk constant should be updated."
        );

        assertGt(
            EndMinRC,
            initialMinRC,
            "Risk constant should be updated and increased.");

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

    function testLiquidatable_positionNotLiquidatable() public {
        vm.startPrank(deployer);
        uint256 _minCR = Math.mulDiv(15, FixedPoint96.Q96, 10);
        lpPositionsManager.updateRiskConstants(
            address(uniPoolUsdcETHAddr),
            _minCR
        );
        vm.stopPrank();
        vm.startPrank(address(facticeUser1));
        borrowerOperation.borrowGHO(633 * TOKEN18, facticeUser1_tokenId);
        vm.stopPrank();

        uint256 cr = lpPositionsManager.computeCR(facticeUser1_tokenId);
        assertTrue(cr > _minCR);
    }

    function testLiquidate() public {
        vm.startPrank(address(facticeUser1));
        borrowerOperation.borrowGHO(1000 * TOKEN18, facticeUser1_tokenId);
        vm.stopPrank();

        vm.startPrank(deployer);
        uint256 _minCR = Math.mulDiv(15, FixedPoint96.Q96, 10);
        lpPositionsManager.updateRiskConstants(
            address(uniPoolUsdcETHAddr),
            _minCR
        );
        vm.stopPrank();

        assertTrue(lpPositionsManager.liquidatable(
            facticeUser1_tokenId
        ));

        vm.startPrank(address(facticeUser2));

        uint256 amountToRepay = lpPositionsManager.totalDebtOf(facticeUser1);
        assertGe(ghoToken.balanceOf(address(facticeUser2)), amountToRepay);
        lpPositionsManager.liquidate(facticeUser1_tokenId, amountToRepay);
        vm.stopPrank();

        assertEq(
            uint256(lpPositionsManager.getPosition(facticeUser1_tokenId).status),
            3,
            "Position should be closed by liquidation."
        );

        uniswapPositionsNFT.positions(facticeUser1_tokenId);

        assertEq(uniswapPositionsNFT.ownerOf(facticeUser1_tokenId), facticeUser2);
        }


    function testLiquidate_swap() public {
        vm.startPrank(deployer);
        uint256 _minCR = Math.mulDiv(15, FixedPoint96.Q96, 10);
        lpPositionsManager.updateRiskConstants(
            address(uniPoolUsdcETHAddr),
            _minCR
        );
        vm.stopPrank();

        vm.startPrank(address(facticeUser1));
        borrowerOperation.borrowGHO(633 * TOKEN18, facticeUser1_tokenId);
        vm.stopPrank();

        assertFalse(lpPositionsManager.liquidatable(facticeUser1_tokenId));

        vm.startPrank(deployer);

        deal(address(USDC), deployer, 1_000_000_000_000 * 2 * TOKEN6);
        deal(deployer, 300_000 ether);

        USDC.approve(swapRouterAddr, 1_000_000_000_000 * 2 * TOKEN6);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: usdcAddr,
                tokenOut: wethAddr,
                fee: 500,
                recipient: deployer,
                deadline: block.timestamp + 5 minutes,
                amountIn: 1_000_000_000_000 * TOKEN6,
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

        uint256 amountToRepay = lpPositionsManager.debtOf(facticeUser1_tokenId);
        assertGe(ghoToken.balanceOf(address(facticeUser2)), amountToRepay);

        lpPositionsManager.liquidate(facticeUser1_tokenId, amountToRepay);
        vm.stopPrank();

        assertEq(
            uint256(lpPositionsManager.getPosition(facticeUser1_tokenId).status),
            3,
            "Position should be closed by liquidation."
        );

        assertEq(uniswapPositionsNFT.ownerOf(facticeUser1_tokenId), facticeUser2);

    }

    function testPositionIsLiquidatableWhenMinCRIsReached() public {

        vm.startPrank(deployer);
        uint256 minCRNum = 15;
        uint256 minCRDen = 10;
        uint256 _minCR = Math.mulDiv(minCRNum, FixedPoint96.Q96, minCRDen);
        lpPositionsManager.updateRiskConstants(
            address(uniPoolUsdcETHAddr),
            _minCR
        );
        vm.stopPrank();

        uint256 ghoInETH = lpPositionsManager.priceInETH(address(ghoToken));

        uint256 positionInGHO = 2**96 * lpPositionsManager.positionValueInETH(facticeUser1_tokenId)  / ghoInETH;

        vm.startPrank(address(facticeUser1));
        console.log("GHO:", convertDecimals18(positionInGHO));
        borrowerOperation.borrowGHO(
            (FullMath.mulDiv(positionInGHO, minCRDen, minCRNum) - 1000), // Trying to borrow exatcly the amount needed to reach minCR might result in an error due to some computation approximation.
                                                                                    // Since GHO has 18 decimals, we can just round down to the nearest thousandth.
        facticeUser1_tokenId
        );

        vm.stopPrank();
        uint256 cr = lpPositionsManager.computeCR(facticeUser1_tokenId);
        assertTrue(cr > _minCR);
    }



}

