// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IPriceFeed } from "./interfaces/IPriceFeed.sol";

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { FixedPoint96 } from "@uniswap-core/libraries/FixedPoint96.sol";
import {FullMath} from "@uniswap-core/libraries/FullMath.sol";
import { AggregatorV3Interface } from "@chainlink/interfaces/AggregatorV3Interface.sol";
import { FeedRegistryInterface } from "@chainlink/interfaces/FeedRegistryInterface.sol";
import { Denominations } from "@chainlink/Denominations.sol";

/**
 * @title PriceFeed contract
 * @author Eclypse Labs
 * @notice Contains the Chainlink PriceFeed aggregator.The feedRegistry contract is used to fetch the prices
 */

contract PriceFeed is IPriceFeed, Ownable {
	// -- Addresses --
	address userInteractionAddress;
	address positionManagerAddress;
	address constant WETHAddress = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;

	mapping(address => mapping => AggregatorV3Interface) tokenToQuoteFeed;

	struct ChainlinkResponse {
		uint80 roundId;
		int256 answer;
		uint256 timestamp;
		bool success;
		uint8 decimals;
	}

	/**
	 * @notice Set the addresses of various contracts and emit events to indicate that these addresses have been modified.
	 * @param _initialFeeds The address of the borrower operations contract.
	 * @param _initialToken The address of the borrower operations contract.
	 * @param _initialQuote The address of the borrower operations contract.
	 * @dev This function can only be called by the contract owner.
	 */
	function initialize(address[] _initialFeeds, address[] _initialToken, address[] _initialQuote) external onlyOwner {
		for (int i = 0; i < _initialFeeds.length; i++) {
			tokenToQuoteFeed[initialToken[i]][initialQuote[i]] = AggregatorV3Interface(_initialFeeds[i]);
		}

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
		if (_tokenAddress == WETHAddress && _quote == Denominations.ETH) {
			return FixedPoint96.Q96;
		}
		
		AggregatorV3Interface feed = tokenToQuoteFeed[_tokenAddress][_quote];
		(, int256 answer, , , ) = feed.latestRoundData();

		return FullMath.mulDiv(uint256(answer), FixedPoint96.Q96, 10 ** feed.decimals());
	}

	//-------------------------------------------------------------------------------------------------------------------------------------------------------//
	// Values in ETH Functions
	//-------------------------------------------------------------------------------------------------------------------------------------------------------//
}
