// SPDX-License-Identifier: MIT

pragma solidity >=0.6.11;

import { IPriceFeed } from "./interfaces/IPriceFeed.sol";

import "@uniswap-core/libraries/FixedPoint96.sol";
import "@uniswap-periphery/libraries/OracleLibrary.sol";

import "@openzeppelin/contracts/access/Ownable.sol";

import "@chainlink/src/v0.8/interfaces/AggregatorV3Interface.sol";

/*
 * The PriceFeed uses UniswaTWAP as primary oracle, and Chainlink as fallback. It changes when the
 * difference in price of the two oracles is more than 5%
 */
contract UniswapPriceFeed is IPriceFeed, Ownable {
	// -- Constants --
	uint32 private TWAP_LENGTH = 60;
	uint256 public constant MAX_PRICE_DIFFERENCE_BETWEEN_ORACLES = 5e16; // 5%

	// -- Addresses --
	address userInteractionAddress;
	address positionManagerAddress;
	address constant WETHAddress = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

	// -- State --
	AggregatorV3Interface internal priceFeedChainLink;

	// Retrieves the address of the pool associated with the pair (token/ETH) where given the token's address.
	mapping(address => PoolPricingInfo) private _tokenToWETHPoolInfo;

	// Is this pool accepted by the protocol?
	mapping(address => bool) private _acceptedPoolAddresses;

	//Squaaa´s Implementation
	mapping(address => mapping(address => address)) public pairToPool;

	uint public lastGoodPrice;

	struct ChainlinkResponse {
		uint80 roundId;
		int256 answer;
		uint256 timestamp;
		bool success;
		uint8 decimals;
	}

	struct UniV3TWAPResponse {
		int256 answer;
		uint256 timestamp;
		bool success;
	}

	/**
	 * @notice Set the addresses of various contracts and emit events to indicate that these addresses have been modified.
	 * @param _borrowerOperationsAddress The address of the borrower operations contract.
	 * @dev This function can only be called by the contract owner.
	 */
	function initialize(address _userInteractionAddress) external onlyOwner {
		userInteractionAddress = _userInteractionAddress;

		oracleStatus = OracleStatus.UniV3TWAPworking;

		// renounceOwnership();
	}

	function fetchPrice(_tokenAddress) external returns (uint256) {
		uint256 price = lastGoodPrice;

		UniV3TWAPResponse memory univ3TWAPResponse = _getUniv3TWAPResponse(_tokenAddress);
		ChainlinkResponse memory chainLinkResponse = _getChainlinkResponse(_tokenAddress);

		if (oracleStatus == OracleStatus.UniV3TWAPworking) {
			if (calculatePriceDifference(univ3TWAPResponse, chainLinkResponse) <= MAX_PRICE_DIFFERENCE_BETWEEN_ORACLES) {
				price = univ3TWAPResponse.answer;
			} else {
				oracleStatus = OracleStatus.chainlinkWorking;
				price = chainLinkResponse.answer;
			}
		}

		if (oracleStatus = OracleStatus.chainlinkWorking) {
			if (calculatePriceDifference(univ3TWAPResponse, chainLinkResponse) <= MAX_PRICE_DIFFERENCE_BETWEEN_ORACLES) {
				oracleStatus = OracleStatus.UniV3TWAPworking;
				price = univ3TWAPResponse.answer;
			} else {
				price = chainLinkResponse.answer;
			}
		}
		return price;
	}

	// Returns the price of toToken denominated in fromToken, as a fixedpoint96 number.
	// function fetchPrice(address fromToken, address toToken) public view returns (uint256 priceX96) {
	//     address token0 = fromToken;
	//     address token1 = toToken;
	//     if (token0 > token1) {
	//         (token0, token1) = (token1, token0);
	//     }
	//     address poolAddress = pairToPool[token0][token1];

	//     (int24 twappedTick,) = OracleLibrary.consult(poolAddress, TWAP_LENGTH);
	//     uint160 sqrtRatioX96 = TickMath.getSqrtRatioAtTick(twappedTick);
	//     priceX96 = FullMath.mulDiv(sqrtRatioX96, sqrtRatioX96, FixedPoint96.Q96);
	//     if (fromToken < toToken) {
	//         priceX96 = FullMath.mulDiv(FixedPoint96.Q96, FixedPoint96.Q96, priceX96);
	//     }
	// }

	//-------------------------------------------------------------------------------------------------------------------------------------------------------//
	// Values in ETH Functions
	//-------------------------------------------------------------------------------------------------------------------------------------------------------//

	/**
	 * @notice Returns the value of a token in WETH.
	 * @dev The value is calculated using the TWAP on the TOKEN/WETH's pool.
	 * @param _tokenAddress The address of the token.
	 * @return uniV3TWAPResponse The UniV3TWAPResponse struct containing the value of the token in WETH.
	 */
	function _getUniv3TWAPResponse(address _tokenAddress) public view returns (UniV3TWAPResponse memory uniV3TWAPResponse) {
		//processes the fact that the WETH address can be given
		if (_tokenAddress == WETHAddress) {
			uniV3TWAPResponse.answer = int256(FixedPoint96.Q96); //wrong, can't do this type of conversion
			uniV3TWAPResponse.success = true;
			uniV3TWAPResponse.timestamp = block.timestamp;
			return uniV3TWAPResponse;
		}

		(int24 twappedTick, ) = OracleLibrary.consult(_tokenToWETHPoolInfo[_tokenAddress].poolAddress, TWAP_LENGTH);
		uint160 sqrtRatioX96 = TickMath.getSqrtRatioAtTick(twappedTick);
		uint256 ratio = FullMath.mulDiv(sqrtRatioX96, sqrtRatioX96, FixedPoint96.Q96);
		if (_tokenToWETHPoolInfo[_tokenAddress].inv) ratio = FullMath.mulDiv(FixedPoint96.Q96, FixedPoint96.Q96, ratio);

		uniV3TWAPResponse.answer = int256(ratio);
		uniV3TWAPResponse.success = true;
		uniV3TWAPResponse.timestamp = block.timestamp;
		return uniV3TWAPResponse;
	}

	/**
	 * @notice Returns the value of a token in WETH.
	 * @dev The value is calculated using Chainlink PriceFeed Oracle on the TOKEN/ETH's pool.
	 * @param _tokenAddress The address of the token.
	 * @return chainlinkResponse The ChainlinkResponse struct containing the response from the Chainlink Oracle.
	 */
	function _getChainlinkResponse(address _tokenAddress) public returns (ChainlinkResponse memory chainlinkResponse) {
		priceFeedChainLink = AggregatorV3Interface(_tokenToWETHPoolInfo[_tokenAddress].poolAddress);
		(uint80 roundId, int256 price, , uint256 timestamp, ) = priceFeedChainLink.latestRoundData();

		if (_tokenAddress == WETHAddress) {
			price = int256(FixedPoint96.Q96);
		}

		chainlinkResponse.roundId = roundId;
		chainlinkResponse.answer = price;
		chainlinkResponse.timestamp = timestamp;
		chainlinkResponse.success = true;
		chainlinkResponse.decimals = priceFeedChainLink.decimals();

		return chainlinkResponse;
	}

	function fetchDollarPrice(address token) public view returns (uint256 priceX96) {}

	//-------------------------------------------------------------------------------------------------------------------------------------------------------//
	// Helper functions
	//-------------------------------------------------------------------------------------------------------------------------------------------------------//

	function _getChainlinkPrice(ChainlinkResponse memory chainlinkResponse) internal pure returns (uint256) {
		return uint256(chainlinkResponse.answer) * 10 ** 10; //convert to 18 decimals
	}

	function _getUniv3TWAPPrice(UniV3TWAPResponse memory uniV3TWAPResponse) internal pure returns (uint256) {
		return uint256(uniV3TWAPResponse.answer); //check with how many decimals
	}

	function calculatePriceDifference(
		UniV3TWAPResponse memory _uniV3TWAPResponse,
		ChainlinkResponse memory _chainlinkResponse
	) internal returns (uint256) {
		uint256 uniswapTWAPPrice = _univ3TWAPResponse.answer;
		uint256 chainlinkPrice = _chainLinkResponse.answer;
		uint256 finalPriceDifference = 0;

		if (uniswapTWAPPrice < chainlinkPrice) {
			finalPriceDifference = chainlinkPrice - uniswapTWAPPrice;
		} else if (chainlinkPrice < uniswapTWAPPrice) {
			finalPriceDifference = uniswapTAPPrice - chainlinkPrice;
		}
		uint256 pricePercentage = FullMath.mulDiv(finalPriceDifference, FixedPoint96.Q96, uniswapTWAPPrice);
	}
}
