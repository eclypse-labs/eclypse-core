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
        console.log(initialLiquidity); //35_814_000_398_394

        borrowerOperation.removeCollateral(
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
        borrowerOperation.removeCollateral(
            facticeUser1_tokenId,
            1_000_000_000_000
        );
    }

    function testRemoveMoreThanActualLiquidity() public {
        vm.startPrank(address(facticeUser1));

        uint128 initialLiquidity = lpPositionsManager
            .getPosition(facticeUser1_tokenId)
            .liquidity;
        console.log(initialLiquidity); //35_814_000_398_394

        vm.expectRevert(bytes("You can't remove more liquidity than you have"));
        borrowerOperation.removeCollateral(
            facticeUser1_tokenId,
            initialLiquidity + 1_000_000_000_000
        );
        vm.stopPrank();
    }

    function testRemoveCollateralMakesLiquidatable() public {
        vm.startPrank(address(facticeUser1));

        uint128 initialLiquidity = lpPositionsManager
            .getPosition(facticeUser1_tokenId)
            .liquidity;
        console.log(initialLiquidity); //35_814_000_398_394

        vm.expectRevert(
            "Collateral Ratio cannot be lower than the minimum collateral ratio."
        );
        borrowerOperation.removeCollateral(
            facticeUser1_tokenId,
            initialLiquidity - 1_000_000_000_000
        );

        vm.stopPrank();
    }
}
