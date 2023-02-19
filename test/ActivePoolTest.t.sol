//SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

import "./UniswapTest.sol";


contract ActivePoolTest is UniswapTest {
    function setUp() public {
        uniswapTest();
    }

    function testMaxSupply_GetMaxSupply() public {
        assertEq(activePool.getMaxSupply(), 2**256 - 1, "Max supply should be 2**256 - 1");
    }

    function testMaxSupply_SetNewMaxSupply() public {
        vm.startPrank(address(deployer));
        activePool.setNewMaxSupply(10 * TOKEN18);
        assertEq(activePool.getMaxSupply(), 10 * TOKEN18);
        vm.stopPrank();
    }

    function testGHOAmount_MultiplePositions() public {
        vm.startPrank(address(facticeUser1));
        borrowerOperation.borrowGHO(10 * TOKEN18, facticeUser1_tokenId);
        assertEq(activePool.getMintedSupply(), 10 * TOKEN18);
        borrowerOperation.borrowGHO(10 * TOKEN18, facticeUser1_tokenId2);
        assertEq(activePool.getMintedSupply(), 20 * TOKEN18);
        borrowerOperation.repayGHO(10 * TOKEN18, facticeUser1_tokenId);
        assertEq(activePool.getMintedSupply(), 10 * TOKEN18);
        borrowerOperation.repayGHO(10 * TOKEN18, facticeUser1_tokenId2);
        assertEq(activePool.getMintedSupply(), 0);
        vm.stopPrank();
    }

    function testMaxSupply_BorrowMoreThanMaxSupply() public {
        vm.startPrank(address(deployer));
        activePool.setNewMaxSupply(10 * TOKEN18);
        vm.stopPrank();
        vm.expectRevert();
        vm.startPrank(address(facticeUser1));
        borrowerOperation.borrowGHO(11 * TOKEN18, facticeUser1_tokenId);
        vm.stopPrank();
        vm.stopPrank();
    }

    function testMaxSupply_OnePositionMultipleBorrow() public {
        vm.startPrank(address(deployer));
        activePool.setNewMaxSupply(10 * TOKEN18);
        vm.stopPrank();
        vm.startPrank(address(facticeUser1));
        borrowerOperation.borrowGHO(5 * TOKEN18, facticeUser1_tokenId);
        assertEq(activePool.getMintedSupply(), 5 * TOKEN18);
        vm.expectRevert();
        borrowerOperation.borrowGHO(6 * TOKEN18, facticeUser1_tokenId);
        vm.stopPrank();
    }

    function testMaxSupply_MultiplePositionsOneBorrowEach() public {
        vm.startPrank(address(deployer));
        activePool.setNewMaxSupply(10 * TOKEN18);
        vm.stopPrank();
        vm.startPrank(address(facticeUser1));
        borrowerOperation.borrowGHO(5 * TOKEN18, facticeUser1_tokenId);
        assertEq(activePool.getMintedSupply(), 5 * TOKEN18);
        borrowerOperation.borrowGHO(5 * TOKEN18, facticeUser1_tokenId2);
        assertEq(activePool.getMintedSupply(), 10 * TOKEN18);
        vm.expectRevert();
        borrowerOperation.borrowGHO(1 * TOKEN18, facticeUser1_tokenId);
        vm.stopPrank();
    }

    function testMaxSupply_MultiplePositionsMultipleBorrowEach() public {
        vm.startPrank(address(deployer));
        activePool.setNewMaxSupply(10 * TOKEN18);
        vm.stopPrank();
        vm.startPrank(address(facticeUser1));
        borrowerOperation.borrowGHO(4 * TOKEN18, facticeUser1_tokenId);
        assertEq(activePool.getMintedSupply(), 4 * TOKEN18);
        borrowerOperation.borrowGHO(2 * TOKEN18, facticeUser1_tokenId2);
        assertEq(activePool.getMintedSupply(), 6 * TOKEN18);
        borrowerOperation.borrowGHO(2 * TOKEN18, facticeUser1_tokenId);
        assertEq(activePool.getMintedSupply(), 8 * TOKEN18);
        borrowerOperation.borrowGHO(1 * TOKEN18, facticeUser1_tokenId2);
        assertEq(activePool.getMintedSupply(), 9 * TOKEN18);
        vm.expectRevert();
        borrowerOperation.borrowGHO(2 * TOKEN18, facticeUser1_tokenId);
        vm.stopPrank();
    }

    function testDecreaseLiquidity() public {
        uint128 previousLiquidity = lpPositionsManager.getPosition(facticeUser1_tokenId).liquidity;
        vm.startPrank(address(borrowerOperation));
        activePool.decreaseLiquidity(facticeUser1_tokenId, lpPositionsManager.getPosition(facticeUser1_tokenId).liquidity / 2, facticeUser1);
        vm.stopPrank();
        assertEq(lpPositionsManager.getPosition(facticeUser1_tokenId).liquidity, previousLiquidity / 2, "Position should have half liquidity.");
        }
}
