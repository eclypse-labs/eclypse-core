// SPDX-License-Identifier: MIT

pragma solidity >=0.6.11;

interface IPriceFeed {
	// --- Function ---
	function initialize(address _feedRegistryAddr) external;

	function getPrice(address _tokenAddress, address _quote) external view returns (uint256);
}
