// SPDX-License-Identifier: MIT

pragma solidity >=0.6.11;

interface IPriceFeed {
   
    // --- Function ---

    // Returns the price of toToken denominated in fromToken.
    function fetchPrice(address fromToken, address toToken) external returns (uint);
    function fetchDollarPrice(address token) external returns (uint);
}
