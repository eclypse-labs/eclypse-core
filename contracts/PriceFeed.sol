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
	address constant WETHAddress = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

	FeedRegistryInterface private feedRegistry;

	struct ChainlinkResponse {
		uint80 roundId;
		int256 answer;
		uint256 timestamp;
		bool success;
		uint8 decimals;
	}

	/**
	 * @notice Set the addresses of various contracts and emit events to indicate that these addresses have been modified.
	 * @param _feedRegistryAddr The address of the borrower operations contract.
	 * @dev This function can only be called by the contract owner.
	 */
	function initialize(address _feedRegistryAddr) external onlyOwner {
		feedRegistry = FeedRegistryInterface(_feedRegistryAddr);

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
		ChainlinkResponse memory chainlinkResponse = _getChainlinkResponse(_tokenAddress, _quote);
		return FullMath.mulDiv(uint256(chainlinkResponse.answer), FixedPoint96.Q96, 10 ** (chainlinkResponse.decimals));
	}

	//-------------------------------------------------------------------------------------------------------------------------------------------------------//
	// Values in ETH Functions
	//-------------------------------------------------------------------------------------------------------------------------------------------------------//

	/**
	 * @notice Returns the value of a token in WETH.
	 * @dev The value is calculated using Chainlink PriceFeed Oracle on the TOKEN/ETH's pool.
	 * @param _tokenAddress The address of the token.
	 * @return chainlinkResponse The ChainlinkResponse struct containing the response from the Chainlink Oracle.
	 */
	function _getChainlinkResponse(address _tokenAddress, address _quote) internal view returns (ChainlinkResponse memory chainlinkResponse) {
		if (_quote == address(0) || !(_quote == Denominations.USD || _quote != Denominations.ETH || _quote != Denominations.BTC)) {
			revert();
		}
		(uint80 roundId, int256 price, , uint256 timestamp, ) = feedRegistry.latestRoundData(_tokenAddress, _quote);
		chainlinkResponse.roundId = roundId;
		chainlinkResponse.answer = price;
		chainlinkResponse.timestamp = timestamp;
		chainlinkResponse.success = true;
		if (_quote == Denominations.USD) {
			chainlinkResponse.decimals = 8;
		} else if (_quote == Denominations.ETH) {
			chainlinkResponse.decimals = 18;
		} else if (_quote == Denominations.BTC) {
			chainlinkResponse.decimals = 8;
		}
		return chainlinkResponse;
	}
}
