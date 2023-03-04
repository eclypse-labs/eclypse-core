//SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

import "forge-std/Test.sol";
import "@uniswap-core/interfaces/IUniswapV3Factory.sol";
import "@uniswap-core/interfaces/IUniswapV3Pool.sol";
import "@uniswap-periphery/interfaces/INonfungiblePositionManager.sol";
import "./UniswapTest.sol";
//import "../contracts/GHOToken.sol";


contract EclypseTest is UniswapTest {
    uint256 public fee;

    function setUp() public {
        uniswapTest();
    }


    function testGetPositionsCount() public {
        assertEq(eclypse.getPositionsCount(), 2, "There should be 2 position.");
    }

    function testPositionStatus_changeToCurrentOne() public {
        assertEq(
            uint256(
                eclypse.getPosition(facticeUser1_tokenId).status
            ),
            1,
            "Position should be active."
        );
        vm.startPrank(address(borrowerOperation));
        vm.expectRevert(bytes("A position status cannot be changed to its current one."));
        eclypse.changePositionStatus(facticeUser1_tokenId, IEclypse.Status.active);
        vm.stopPrank();
    }

    function testDebtWhenNoDebt() public {
        assertEq(
            eclypse.getPosition(facticeUser1_tokenId).debtPrincipal,
            0,
            "Position should have no debt."
        );
    }
    function testDebtWhenNoDebt1() public{
        
        uint256 currentDebt = eclypse.debtOf(facticeUser1_tokenId);
        console.log(currentDebt);
        assertEq(currentDebt, 0, "Position should have no debt.");
        
    }

    function testDebtWhenDebt1() public {
        assertEq(
            eclypse.getPosition(facticeUser1_tokenId).debtPrincipal,
            0,
            "Position should have no debt."
        );
        vm.startPrank(address(facticeUser1));
        borrowerOperation.borrowGHO( 300 * TOKEN18, facticeUser1_tokenId);
        vm.stopPrank();
        assertEq(
            eclypse.getPosition(facticeUser1_tokenId).debtPrincipal,
            300 * TOKEN18,
            "Position should have 300 GHO debt."
        );
        uint256 currentDebt = eclypse.debtOf(facticeUser1_tokenId);
        console.log(currentDebt);
        assertEq(currentDebt, 300 * TOKEN18, "Position should have 300 GHO debt.");
    }

    function testPositionStatus_closeByOwner() public {
        // (uint256 interestRate,
        // uint256 totalBorrowedGho,
        // uint256 interestFactor,
        // uint256 lastFactorUpdate,
        // uint32 twapLength) = eclypse.getProtocolValues();

        // console.log("interestRate: ", interestRate);
        // console.log("totalBorrowedGho: ", totalBorrowedGho);
        // console.log("interestFactor: ", interestFactor);
        // console.log("lastFactorUpdate: ", lastFactorUpdate);
        // console.log("twapLength: ", twapLength);

        console.log(eclypse.getProtocolValues().interestRate);
        console.log(eclypse.getProtocolValues().totalBorrowedGho);
        console.log(eclypse.getProtocolValues().interestFactor);
        console.log(eclypse.getProtocolValues().lastFactorUpdate);
        console.log(eclypse.getProtocolValues().twapLength);

        assertEq(
            uint256(
                eclypse.getPosition(facticeUser1_tokenId).status
            ),
            1,
            "Position should be active."
        );
        vm.startPrank(address(facticeUser1));
        borrowerOperation.closePosition(facticeUser1_tokenId);
        vm.stopPrank();
        assertEq(
            uint256(
                eclypse.getPosition(facticeUser1_tokenId).status
            ),
            2,
            "Position should be closed by owner."
        );
    }

    function testPositionStatus_closeByOwnerDebtNotRepaid() public {
        assertEq(
            uint256(
                eclypse.getPosition(facticeUser1_tokenId).status
            ),
            1,
            "Position should be active."
        );
        vm.startPrank(address(facticeUser1));
        borrowerOperation.borrowGHO( 300 * TOKEN18, facticeUser1_tokenId);
        uint256 currentDebt = eclypse.debtOf(facticeUser1_tokenId);
        console.log(currentDebt);
        console.log(300 * TOKEN18);
        vm.expectRevert(abi.encodeWithSelector(Errors.DebtIsNotPaid.selector,  300 * TOKEN18));
        borrowerOperation.closePosition(facticeUser1_tokenId);
        vm.stopPrank();
        assertEq(
            uint256(
                eclypse.getPosition(facticeUser1_tokenId).status
            ),
            1,
            "Position should be active."
        );
    }

    function testPositionStatus_closeByOwnerDebtRepaid() public {
        assertEq(
            uint256(
                eclypse.getPosition(facticeUser1_tokenId).status
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
                eclypse.getPosition(facticeUser1_tokenId).status
            ),
            2,
            "Position should be closed by owner."
        );
    }

    function testPositionStatus_notExistent() public {
        assertEq(
            uint256(eclypse.getPosition(0).status),
            0,
            "Position should not exist."
        );
    }

    // function testPositionStatus_closedByLiquidation() public {
    //     vm.startPrank(address(facticeUser1));
    //     borrowerOperation.borrowGHO(800 * TOKEN18, facticeUser1_tokenId);
    //     vm.stopPrank();

    //     vm.startPrank(deployer);
    //     uint256 _minCR = Math.mulDiv(2, FixedPoint96.Q96, 1);
    //     eclypse.updateRiskConstants(
    //         address(uniPoolUsdcETHAddr),
    //         _minCR
    //     );
    //     vm.stopPrank();

    //     assertTrue(eclypse.liquidatable(
    //         facticeUser1_tokenId
    //     ));

    //     vm.startPrank(address(facticeUser2));

    //     uint256 amountToRepay = eclypse.totalDebtOf(facticeUser1);
    //     assertGe(ghoToken.balanceOf(address(facticeUser2)), amountToRepay);
    //     eclypse.liquidatePosition(facticeUser1_tokenId, amountToRepay);
    //     vm.stopPrank();

    //     assertEq(
    //         uint256(eclypse.getPosition(facticeUser1_tokenId).status),
    //         3,
    //         "Position should be closed by liquidation."
    //     );

    // }

    function testRiskConstantsAreCorrectlyUpdated() public {
        uint256 _minCR = Math.mulDiv(17, FixedPoint96.Q96, 10);
        eclypse.updateRiskConstants(
            address(uniPoolUsdcETHAddr),
            _minCR
        );

        assertEq(
            eclypse.getRiskConstants(address(uniPoolUsdcETHAddr)),
            _minCR,
            "Risk constants are not updated correctly."
        );
    }
    function testRiskConstant_increase() public {
        uint256 minRC = FullMath.mulDiv(13, FixedPoint96.Q96, 10);
        eclypse.updateRiskConstants(
            address(uniPoolUsdcETHAddr),
            minRC
        );

        uint256 initialMinRC = eclypse.getRiskConstants(address(uniPoolUsdcETHAddr));

        assertEq(
            eclypse.getRiskConstants(address(uniPoolUsdcETHAddr)),
            minRC,
            "Risk constant should be updated."
        );

        uint256 newMinRC = FullMath.mulDiv(15, FixedPoint96.Q96, 10);
        eclypse.updateRiskConstants(
            address(uniPoolUsdcETHAddr),
            newMinRC
        );

        uint256 EndMinRC = eclypse.getRiskConstants(address(uniPoolUsdcETHAddr));
    

        assertEq(
            eclypse.getRiskConstants(address(uniPoolUsdcETHAddr)),
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

        eclypse.updateRiskConstants(
            address(uniPoolUsdcETHAddr),
            setInitialRC
        );
        uint256 initialRC = eclypse.getRiskConstants(
            address(uniPoolUsdcETHAddr)
        );

        eclypse.updateRiskConstants(
            address(uniPoolUsdcETHAddr),
            setNewMinRC
        );
        uint256 newMinRC = eclypse.getRiskConstants(
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
        eclypse.updateRiskConstants(
            address(uniPoolUsdcETHAddr),
            newMinRC
        );
    }

    function testRiskConstant_setToLessThan1() public {
        vm.expectRevert(
            bytes("The minimum collateral ratio must be greater than 1.")
        );
        uint256 newMinRC = FullMath.mulDiv(1, FixedPoint96.Q96, 10);
        eclypse.updateRiskConstants(
            address(uniPoolUsdcETHAddr),
            newMinRC
        );
    }

    function testLiquidatable_positionNotLiquidatable() public {
        vm.startPrank(deployer);
        uint256 _minCR = Math.mulDiv(15, FixedPoint96.Q96, 10);
        eclypse.updateRiskConstants(
            address(uniPoolUsdcETHAddr),
            _minCR
        );
        vm.stopPrank();
        vm.startPrank(address(facticeUser1));
        borrowerOperation.borrowGHO(633 * TOKEN18, facticeUser1_tokenId);
        vm.stopPrank();

        uint256 cr = eclypse.computeCR(facticeUser1_tokenId);
        assertTrue(cr > _minCR);
    }

    function testliquidatePosition() public {
        vm.startPrank(address(facticeUser1));
        borrowerOperation.borrowGHO(800 * TOKEN18, facticeUser1_tokenId);
        vm.stopPrank();

        vm.startPrank(deployer);
        uint256 _minCR = Math.mulDiv(2, FixedPoint96.Q96, 1);
        eclypse.updateRiskConstants(
            address(uniPoolUsdcETHAddr),
            _minCR
        );
        vm.stopPrank();

        assertTrue(eclypse.liquidatable(
            facticeUser1_tokenId
        ));

        vm.startPrank(address(facticeUser2));

        uint256 amountToRepay = eclypse.totalDebtOf(facticeUser1);
        assertGe(ghoToken.balanceOf(address(facticeUser2)), amountToRepay);
        eclypse.liquidatePosition(facticeUser1_tokenId, amountToRepay);
        vm.stopPrank();

        assertEq(
            uint256(eclypse.getPosition(facticeUser1_tokenId).status),
            3,
            "Position should be closed by liquidation."
        );

        assertEq(uniswapPositionsNFT.ownerOf(facticeUser1_tokenId), facticeUser2);
        }


    // function testLiquidate_swap() public {
    //     vm.startPrank(deployer);
    //     uint256 _minCR = Math.mulDiv(15, FixedPoint96.Q96, 10);
    //     eclypse.updateRiskConstants(
    //         address(uniPoolUsdcETHAddr),
    //         _minCR
    //     );
    //     vm.stopPrank();

    //     vm.startPrank(address(facticeUser1));
    //     borrowerOperation.borrowGHO(633 * TOKEN18, facticeUser1_tokenId);
    //     vm.stopPrank();

    //     assertFalse(eclypse.liquidatable(facticeUser1_tokenId));

    //     vm.startPrank(deployer);

    //     deal(address(USDC), deployer, 1_000_000_000_000 * 2 * TOKEN6);
    //     deal(deployer, 300_000 ether);

    //     USDC.approve(swapRouterAddr, 1_000_000_000_000 * 2 * TOKEN6);

    //     ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
    //         .ExactInputSingleParams({
    //             tokenIn: usdcAddr,
    //             tokenOut: wethAddr,
    //             fee: 500,
    //             recipient: deployer,
    //             deadline: block.timestamp + 5 minutes,
    //             amountIn: 1_000_000_000_000 * TOKEN6,
    //             amountOutMinimum: 0,
    //             sqrtPriceLimitX96: 0
    //         });

    //     vm.roll(block.number + 1);
    //     vm.warp(block.timestamp + 1 minutes);
    //     swapRouter.exactInputSingle(params);
    //     vm.roll(block.number + 2);
    //     vm.warp(block.timestamp + 90 seconds);
    //     swapRouter.exactInputSingle(params);
    //     vm.stopPrank();
    //     assertTrue(eclypse.liquidatable(facticeUser1_tokenId));
    //     vm.startPrank(address(facticeUser2));

    //     uint256 amountToRepay = eclypse.debtOf(facticeUser1_tokenId);
    //     assertGe(ghoToken.balanceOf(address(facticeUser2)), amountToRepay);

    //     eclypse.liquidatePosition(facticeUser1_tokenId, amountToRepay);
    //     vm.stopPrank();

    //     assertEq(
    //         uint256(eclypse.getPosition(facticeUser1_tokenId).status),
    //         3,
    //         "Position should be closed by liquidation."
    //     );

    //     assertEq(uniswapPositionsNFT.ownerOf(facticeUser1_tokenId), facticeUser2);

    // }

    function testPositionIsLiquidatableWhenMinCRIsReached() public {

        vm.startPrank(deployer);
        uint256 minCRNum = 15;
        uint256 minCRDen = 10;
        uint256 _minCR = Math.mulDiv(minCRNum, FixedPoint96.Q96, minCRDen);
        eclypse.updateRiskConstants(
            address(uniPoolUsdcETHAddr),
            _minCR
        );
        vm.stopPrank();

        uint256 ghoInETH = eclypse.priceInETH(address(ghoToken));

        uint256 positionInGHO = 2**96 * eclypse.positionValueInETH(facticeUser1_tokenId)  / ghoInETH;

        vm.startPrank(address(facticeUser1));
        console.log("GHO:", convertDecimals18(positionInGHO));
        borrowerOperation.borrowGHO(
            (FullMath.mulDiv(positionInGHO, minCRDen, minCRNum) - 1000), // Trying to borrow exatcly the amount needed to reach minCR might result in an error due to some computation approximation.
                                                                                    // Since GHO has 18 decimals, we can just round down to the nearest thousandth.
        facticeUser1_tokenId
        );

        vm.stopPrank();
        uint256 cr = eclypse.computeCR(facticeUser1_tokenId);
        assertTrue(cr > _minCR);
    }

    // function testLiquidate_Undelying() public {
    //     vm.startPrank(address(facticeUser1));
    //     borrowerOperation.borrowGHO(800 * TOKEN18, facticeUser1_tokenId);
    //     vm.stopPrank();

    //     vm.startPrank(deployer);
    //     uint256 _minCR = Math.mulDiv(2, FixedPoint96.Q96, 1);
    //     eclypse.updateRiskConstants(
    //         address(uniPoolUsdcETHAddr),
    //         _minCR
    //     );
    //     vm.stopPrank();

    //     assertTrue(eclypse.liquidatable(
    //         facticeUser1_tokenId
    //     ));

    //     vm.startPrank(address(facticeUser2));
    //     uint256 initialAmount0 = USDC.balanceOf(address(facticeUser2));
    //     uint256 initialAmount1 = WETH.balanceOf(address(facticeUser2));

    //     uint256 amountToRepay = eclypse.totalDebtOf(facticeUser1);
    //     assertGe(ghoToken.balanceOf(address(facticeUser2)), amountToRepay);
    //     eclypse.liquidateUnderlyings(facticeUser1_tokenId, amountToRepay);
    //     vm.stopPrank();

    //     assertGt(
    //         USDC.balanceOf(address(facticeUser2)),
    //         initialAmount0,
    //         "USDC should be transferred to liquidator."
    //     );

    //     assertGt(
    //         WETH.balanceOf(address(facticeUser2)),
    //         initialAmount1,
    //         "WETH should be transferred to liquidator."
    //     );

    //     console.log(address(facticeUser2).balance);

    //     assertEq(
    //         uint256(eclypse.getPosition(facticeUser1_tokenId).status),
    //         3,
    //         "Position should be closed by liquidation."
    //     );
    // }



}

