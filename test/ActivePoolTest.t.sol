//SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

import "./UniswapTest.sol";

contract ActivePoolTest is UniswapTest {
    function setUp() public {
        uniswapTest();
    }

    function testDecreaseLiquidity() public {
        console.log("Token0 Owed To User:", activePool.getTokensOwedToUser(facticeUser1, lpPositionsManager.getPosition(facticeUser1_tokenId).token0));
        console.log("Token1 Owed To User:", activePool.getTokensOwedToUser(facticeUser1, lpPositionsManager.getPosition(facticeUser1_tokenId).token1));
        uint128 previousLiquidity = lpPositionsManager.getPosition(facticeUser1_tokenId).liquidity;
        vm.startPrank(address(borrowerOperation));
        activePool.decreaseLiquidityToProtocol(facticeUser1_tokenId, lpPositionsManager.getPosition(facticeUser1_tokenId).liquidity / 2, facticeUser1);
        vm.stopPrank();
        assertEq(lpPositionsManager.getPosition(facticeUser1_tokenId).liquidity, previousLiquidity / 2, "Position should have half liquidity.");
        console.log("Token0 Owed To User:", activePool.getTokensOwedToUser(facticeUser1, lpPositionsManager.getPosition(facticeUser1_tokenId).token0));
        console.log("Token1 Owed To User:", activePool.getTokensOwedToUser(facticeUser1, lpPositionsManager.getPosition(facticeUser1_tokenId).token1));
    }
}
