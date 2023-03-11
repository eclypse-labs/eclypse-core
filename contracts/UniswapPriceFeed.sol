// SPDX-License-Identifier: MIT

pragma solidity >=0.6.11;

import "./interfaces/IPriceFeed.sol";

import "@uniswap-core/libraries/FixedPoint96.sol";
import "@uniswap-periphery/libraries/OracleLibrary.sol";

import "@openzeppelin/contracts/access/Ownable.sol";

contract UniswapPriceFeed is IPriceFeed, Ownable {
    uint32 private TWAP_LENGTH = 60;
    mapping(address => mapping(address => address)) public pairToPool;

    // Returns the price of toToken denominated in fromToken, as a fixedpoint96 number.
    function fetchPrice(address fromToken, address toToken) public view returns (uint256 priceX96) {
        address token0 = fromToken;
        address token1 = toToken;
        if (token0 > token1) {
            (token0, token1) = (token1, token0);
        }
        address poolAddress = pairToPool[token0][token1];

        (int24 twappedTick,) = OracleLibrary.consult(poolAddress, TWAP_LENGTH);
        uint160 sqrtRatioX96 = TickMath.getSqrtRatioAtTick(twappedTick);
        priceX96 = FullMath.mulDiv(sqrtRatioX96, sqrtRatioX96, FixedPoint96.Q96);
        if (fromToken < toToken) {
            priceX96 = FullMath.mulDiv(FixedPoint96.Q96, FixedPoint96.Q96, priceX96);
        }
    }

    function fetchDollarPrice(address token) public view returns (uint256 priceX96) {

    }
}
