//SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

import "forge-std/Test.sol";
import "./UniswapTest.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "../src/GHOToken.sol";
import "../src/BorrowerOperations.sol";
import "../src/ActivePool.sol";
import "../src/LPPositionsManager.sol";
import "@uniswap-core/interfaces/IUniswapV3Factory.sol";
import "@uniswap-core/interfaces/IUniswapV3Pool.sol";
import "@uniswap-periphery/interfaces/INonfungiblePositionManager.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";

contract LPPositionsManagerTest is UniswapTest {
    using SafeMath for uint256;
    uint256 public constant tokenIdUser1 = 549666;

    function setUp() public {
        uniswapTest();
    }

    function testPriceInETH() public {
        lpPositionsManager.addTokenETHpoolAddress(
            usdcAddr,
            uniPoolUsdcETHAddr,
            false
        );
        uint256 price = lpPositionsManager.priceInETH(usdcAddr);
        console.log("price in ETH of USDC: ", price);
        // TODO : check assert eq
    }

    function testPositionValueInETH() public {
        lpPositionsManager.addTokenETHpoolAddress(
            usdcAddr,
            uniPoolUsdcETHAddr,
            false
        );
    }

    function testBorrowGHOAndTotalDebtOf() public {
        uint256 _minCR = Math.mulDiv(17, 1 << 96, 10);
        console.log("minCR calculated: ", _minCR);
        lpPositionsManager.updateRiskConstants(
            address(uniPoolUsdcETHAddr),
            _minCR
        );
        console.log(
            "updated risk constant: ",
            lpPositionsManager.getRiskConstants(address(uniPoolUsdcETHAddr))
        );
        vm.startPrank(address(user1));
        borrowerOperation.borrowGHO(10, 549666);
        vm.stopPrank();
        console.log(
            "borrowed GHO of user1: ",
            ghoToken.balanceOf(address(user1))
        );
        console.log(
            "debt of the user : ",
            lpPositionsManager.totalDebtOf(user1)
        );
        //console.log("borrowed GHO of borrowerOp :" , ghoToken.balanceOf(address(borrowerOperation)));
        console.log("total supply of GHO: ", ghoToken.totalSupply());
    }

    function testRepayGho() public {
        console.log(
            "debt of the user before borrowing operation",
            lpPositionsManager.totalDebtOf(user1)
        );
        assertEq(lpPositionsManager.totalDebtOf(user1), 0);

        vm.startPrank(user1);
        borrowerOperation.borrowGHO(1 ether, tokenIdUser1);

        console.log(
            "debt after borrowing",
            lpPositionsManager.totalDebtOf(user1)
        );
        console.log(ghoToken.balanceOf(user1));
        borrowerOperation.repayGHO(1, tokenIdUser1);
        vm.stopPrank();

        assertEq(99, lpPositionsManager.totalDebtOf(user1));

    }

    function testLiquidatablePosition() public {

    }

    function testTotalDebtOf() public {
        console.log(
            "debt of the user1 before borrow : ",
            lpPositionsManager.totalDebtOf(user1)
        );
        assertEq(lpPositionsManager.totalDebtOf(user1), 0);

        vm.startPrank(address(user1));
        borrowerOperation.borrowGHO(100, 549666);
        vm.stopPrank();
        console.log(
            "debt of the user1 after borrow : ",
            lpPositionsManager.totalDebtOf(user1)
        );
        assertEq(lpPositionsManager.totalDebtOf(user1), 100);
    }

    function testComputeCR() public {
        console.log("CR of user1 is ", lpPositionsManager.computeCR(549666));
        // TODO : assert check with correct type conversion
    }

    function testRiskConstantsAreCorrectlyUpdated() public {
        console.log(
            "initial risk constant: ",
            lpPositionsManager.getRiskConstants(address(uniPoolUsdcETHAddr))
        );
        uint256 _minCR = Math.mulDiv(17, 1 << 96, 10);
        console.log("minCR calculated: ", _minCR);
        lpPositionsManager.updateRiskConstants(
            address(uniPoolUsdcETHAddr),
            _minCR
        );
        console.log(
            "updated risk constant: ",
            lpPositionsManager.getRiskConstants(address(uniPoolUsdcETHAddr))
        );
        assertEq(
            lpPositionsManager.getRiskConstants(address(uniPoolUsdcETHAddr)),
            _minCR,
            "risk constants are not updated correctly"
        );
    }
}

//TODO: test deposit + withdraw

//TODO: test deposit + borrow + check health factor

//TODO: test deposit + borrow + can't withdraw if it would liquidate the position

//TODO: test liquidation (change oracle price)
