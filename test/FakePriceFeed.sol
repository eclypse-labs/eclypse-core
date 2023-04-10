// SPDX-License-Identifier: MIT

pragma solidity <0.9.0;

import { IPriceFeed } from "../contracts/interfaces/IPriceFeed.sol";

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
//import {Math} from "@oppenzeppelin/contracts/utils/math/Math.sol";

import { FixedPoint96 } from "@uniswap-core/libraries/FixedPoint96.sol";
import { FullMath } from "@uniswap-core/libraries/FullMath.sol";

import "forge-std/Test.sol";

/*
 * The PriceFeed uses UniswaTWAP as primary oracle, and Chainlink as fallback. It changes when the
 * difference in price of the two oracles is more than 5%
 */
contract FakePriceFeed is IPriceFeed, Ownable {
	// -- State --
	uint256 public ethUsdPrice;

	/**
	 * @notice Set the addresses of various contracts and emit events to indicate that these addresses have been modified.
	 * @param _feedRegistryAddr The address of the borrower operations contract.
	 * @dev This function can only be called by the contract owner.
	 */
	function initialize(address _feedRegistryAddr) external onlyOwner {
		// renounceOwnership();
	}

	//-------------------------------------------------------------------------------------------------------------------------------------------------------//
	// get price
	//-------------------------------------------------------------------------------------------------------------------------------------------------------//

	/**
	 * @notice Returns the price of a token in _quote.
	 * @param _tokenAddress The address of the token.
	 * @param _quote The address of the quote token.
	 * @return The price of the token in _quote, as a Q96 fixed point number.
	 */
	function getPrice(address _tokenAddress, address _quote) external view returns (uint256) {
        if (_tokenAddress == 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2 && _quote == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE) {
            return FixedPoint96.Q96;
        } else if (_tokenAddress == 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48) {
            return FullMath.mulDiv(FixedPoint96.Q96, FixedPoint96.Q96, ethUsdPrice);
        } else {
            return ethUsdPrice;
        }
	}

    function setEthUsdPrice(uint256 _price) external {
        ethUsdPrice = _price;
    }
}