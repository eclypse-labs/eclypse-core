//SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

import "./UniswapTest.sol";

contract ActivePoolTest is UniswapTest {
    function setUp() public {
        uniswapTest();
    }

    function testDecreaseLiquidity() public {
        uint128 previousLiquidity = lpPositionsManager.getPosition(facticeUser1_tokenId).liquidity;
        vm.startPrank(address(borrowerOperation));
        activePool.decreaseLiquidity(facticeUser1_tokenId, lpPositionsManager.getPosition(facticeUser1_tokenId).liquidity / 2, facticeUser1);
        vm.stopPrank();
        assertEq(lpPositionsManager.getPosition(facticeUser1_tokenId).liquidity, previousLiquidity / 2, "Position should have half liquidity.");
        }
}
