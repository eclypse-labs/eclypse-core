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

    function setUp() public {
        uniswapTest();
    }

   /* function testPriceInETH() public {
        lpPositionsManager.addTokenETHpoolAddress(
            usdcAddr,
            uniPoolUsdcETHAddr,
            false
        );
        uint256 price = lpPositionsManager.priceInETH(usdcAddr);
        console.log("price in ETH of USDC: ", price);
    }*/

    function testPositionValueInETH() public {
        lpPositionsManager.addTokenETHpoolAddress(
            usdcAddr,
            uniPoolUsdcETHAddr,
            false
        );
    
    }


    function testBorrowGHO() public {
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
        borrowerOperation.borrowGHO(1, 549666);
        vm.stopPrank();
    }

    /*function testComputeCR() public {
        console.log("CR of user1 is ", lpPositionsManager.computeCR(549666));
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
    }*/
}

//TODO: test deposit

//TODO: test deposit + withdraw

//TODO: test deposit + borrow + check health factor

//TODO: test deposit + borrow + can't withdraw if it would liquidate the position

//TODO: test liquidation (change oracle price)
