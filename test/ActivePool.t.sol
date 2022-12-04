//SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

import "./UniswapTest.sol";

contract ActivePoolTest is UniswapTest {
    function setUp() public {
        uniswapTest();
    }

    function testGetCollateralValue() public {
        console.log(
            "Total collateral value: ",
            activePool.getCollateralValue()
        );

    }
}