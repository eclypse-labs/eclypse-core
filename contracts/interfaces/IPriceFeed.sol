// SPDX-License-Identifier: MIT

pragma solidity >=0.6.11;

interface IPriceFeed {
	// --- Function ---
	function initialize(address _feedRegistryAddr) external;

	/**
	 * @notice Returns the price of a token in _quote, as a fixed point Q96 number.
	 * @param _tokenAddress The address of the token to get the price of.
	 * @param _quote The address of the token to quote the token in.
	 * @return The price of the token in _quote, as a fixed point Q96 number.
	 */
	function getPrice(address _tokenAddress, address _quote) external view returns (uint256);
}
