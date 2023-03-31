// SPDX-License-Identifier: MIT

pragma solidity <0.9.0;

import { IPriceFeed } from "./interfaces/IPriceFeed.sol";

import { FixedPoint96 } from "@uniswap-core/libraries/FixedPoint96.sol";

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
//import {Math} from "@oppenzeppelin/contracts/utils/math/Math.sol";

import { AggregatorV3Interface } from "@chainlink/interfaces/AggregatorV3Interface.sol";
import { FeedRegistryInterface } from "@chainlink/interfaces/FeedRegistryInterface.sol";
import { Denominations } from "@chainlink/Denominations.sol";

import "@uniswap-core/libraries/FullMath.sol";
import "@uniswap-core/libraries/FixedPoint96.sol";
import "forge-std/Test.sol";

/*
 * The PriceFeed uses UniswaTWAP as primary oracle, and Chainlink as fallback. It changes when the
 * difference in price of the two oracles is more than 5%
 */
contract PriceFeed is IPriceFeed, Ownable {
	// -- Addresses --
	address userInteractionAddress;
	address positionManagerAddress;
	address constant WETHAddress = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

	// -- State --
	AggregatorV3Interface private priceFeedChainLink;
	FeedRegistryInterface private feedRegistry;

	uint public lastGoodPrice;

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

	function getPrice(address _tokenAddress, address _quote) external view returns (uint256) {
		if (_tokenAddress == WETHAddress && _quote == Denominations.ETH) {
			return 1e18;
		}
		ChainlinkResponse memory chainlinkResponse = _getChainlinkResponse(_tokenAddress, _quote);
		//muldiv ou muldivRoundingUp a voir
		//uint8 decimals = chainlinkResponse.decimals;
		//return FullMath.mulDiv(uint256(chainlinkResponse.answer), 1, 10 ** (decimals));
		return uint256(chainlinkResponse.answer);
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
