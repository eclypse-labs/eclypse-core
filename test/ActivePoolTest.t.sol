//SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

import "./UniswapTest.sol";

contract ActivePoolTest is UniswapTest {
    function setUp() public {
        uniswapTest();
    }

<<<<<<< HEAD
    function testGetCollateralValue() public {
        console.log(activePool.getCollateralValue());       
    }
}
=======

function setUp() public {
    uniswapTest();
}

function testGetCollateralValue() public{
    console.log(activePool.getCollateralValue());
    
}
}
>>>>>>> 13995ae35a7836b3729de97cc5fd515dbef31c72
