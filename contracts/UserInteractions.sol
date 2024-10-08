// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IUserInteractions } from "./interfaces/IUserInteractions.sol";
import { IPositionsManager } from "./interfaces/IPositionsManager.sol";
import { PositionsManager } from "./PositionsManager.sol";
import { Errors } from "./utils/Errors.sol";

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { INonfungiblePositionManager } from "@uniswap-periphery/interfaces/INonfungiblePositionManager.sol";

/**
 * @title UserInteractions contract
 * @author Eclypse Labs
 * @notice Contains the functions for position operations performed by users of Eclypse protocol including opening a position,
 * closing it, adding collateral, removing it.
 * @dev The contract is owned by the Eclypse system, and serves as a link between the Frontend and the Backend.
 */

contract UserInteractions is Ownable, IUserInteractions, ReentrancyGuard {
	INonfungiblePositionManager internal uniswapV3NFPositionsManager;
	PositionsManager internal manager;

	/**
	 * @notice Set the addresses of various contracts and emit events to indicate that these addresses have been modified.
	 * @param _uniPosNFT The address of the uniswapV3 NonfungiblePositionManager contract.
	 * @param _PositionManagerAddress The address of the PositionsManager contract.
	 * @dev This function can only be called by the contract owner.
	 */
	function initialize(address _uniPosNFT, address _PositionManagerAddress) external onlyOwner {
		uniswapV3NFPositionsManager = INonfungiblePositionManager(_uniPosNFT);
		manager = PositionsManager(_PositionManagerAddress);
		//renounceOwnership();
	}

	/**
	 * @notice Opens a new position.
	 * @param _tokenId The ID of the Uniswap V3 NFT representing the position.
	 * @param _asset The address of the asset which will be borrowed with this position.
	 * @dev The caller must have approved the transfer of the Uniswap V3 NFT from their wallet to the BorrowerOperations contract.
	 */
	function openPosition(uint256 _tokenId, address _asset, uint256 _borrowAmount) external positionNotInitiated(_tokenId) {
		manager.openPosition(msg.sender, _tokenId, _asset);

		if (_borrowAmount > 0) {
			manager.borrow(msg.sender, _tokenId, _borrowAmount);
		}
	}

	/**
	 * @notice Closes a position.
	 * @param _tokenId The ID of the Uniswap V3 NFT representing the position.
	 */
	function closePosition(uint256 _tokenId) external onlyActivePosition(_tokenId) onlyPositionOwner(_tokenId, msg.sender) {
		manager.closePosition(msg.sender, _tokenId);
	}

	/**
	 * @notice Borrow.
	 * @param _amount The amount of stablecoin to withdraw.
	 * @param _tokenId The ID of the Uniswap V3 NFT representing the position.
	 */
	function borrow(uint256 _amount, uint256 _tokenId) public nonReentrant onlyActivePosition(_tokenId) onlyPositionOwner(_tokenId, msg.sender) {
		if (!(_amount > 0)) {
			revert Errors.AmountShouldBePositive();
		}

		manager.borrow(msg.sender, _tokenId, _amount);
	}

	/**
	 * @notice Repay.
	 * @param _amount The amount of stablecoin to repay.
	 * @param _tokenId The ID of the Uniswap V3 NFT representing the position.
	 */
	function repay(uint256 _amount, uint256 _tokenId) public nonReentrant onlyActivePosition(_tokenId) onlyPositionOwner(_tokenId, msg.sender) {
		if (_amount <= 0) {
			revert Errors.AmountShouldBePositive();
		}

		manager.repay(msg.sender, _tokenId, _amount);
	}

	/**
	 * @notice Add collateral to a position.
	 * @param _amount0 The amount of token0 to add.
	 * @param _amount1 The amount of token1 to add.
	 * @param _tokenId The ID of the Uniswap V3 NFT representing the position.
	 * @return liquidity The amount of liquidity added.
	 * @return amount0 The amount of token0 added.
	 * @return amount1 The amount of token1 added.
	 */
	function deposit(
		uint256 _amount0,
		uint256 _amount1,
		uint256 _tokenId
	)
		public
		nonReentrant
		onlyActivePosition(_tokenId)
		onlyPositionOwner(_tokenId, msg.sender)
		returns (uint128 liquidity, uint256 amount0, uint256 amount1)
	{
		if (_amount0 <= 0 || _amount1 <= 0) {
			revert Errors.AmountShouldBePositive();
		}

		(liquidity, amount0, amount1) = manager.deposit(msg.sender, _tokenId, _amount0, _amount1);
	}

	/**
	 * @notice Remove collateral from a position.
	 * @param _liquidity The amount of liquidity to remove.
	 * @param _tokenId The ID of the Uniswap V3 NFT representing the position.
	 * @return amount0 The amount of token0 removed.
	 * @return amount1 The amount of token1 removed.
	 */
	function withdraw(
		uint128 _liquidity,
		uint256 _tokenId
	) public nonReentrant onlyActivePosition(_tokenId) onlyPositionOwner(_tokenId, msg.sender) returns (uint256 amount0, uint256 amount1) {
		(amount0, amount1) = manager.withdraw(msg.sender, _tokenId, _liquidity);

		require(!manager.liquidatable(_tokenId), "Collateral Ratio cannot be lower than the minimum collateral ratio.");
	}

	/**
	 * @notice Update the ticks of the position.
	 * @param _tokenId The ID of the Uniswap V3 NFT representing the position.
	 * @param _newLowerTick The new lower tick.
	 * @param _newUpperTick The new upper tick.
	 */
	function updateTicks(
		uint256 _tokenId,
		int24 _newLowerTick,
		int24 _newUpperTick
	) public onlyActivePosition(_tokenId) onlyPositionOwner(_tokenId, msg.sender) returns(uint256 _newTokenId) {
		_newTokenId = manager.updateTicks(msg.sender, _tokenId, _newLowerTick, _newUpperTick);
	}

	/**
	 * @notice Check if the position is active.
	 * @param _tokenId The ID of the Uniswap V3 NFT representing the position.
	 */
	modifier onlyActivePosition(uint256 _tokenId) {
		if (!(manager.getPosition(_tokenId).status == IPositionsManager.Status.active)) {
			revert Errors.PositionIsNotActiveOrIsClosed(_tokenId);
		}
		_;
	}

	modifier positionNotInitiated(uint256 _tokenId) {
		if ((manager.getPosition(_tokenId).status == IPositionsManager.Status.active)) {
			revert Errors.PositionIsAlreadyActive(_tokenId);
		}
		_;
	}

	/**
	 * @notice Check if the user is the owner of the position.
	 * @param _tokenId The ID of the Uniswap V3 NFT representing the position.
	 * @param _user The address of the user.
	 */
	modifier onlyPositionOwner(uint256 _tokenId, address _user) {
		if (!(manager.getPosition(_tokenId).user == _user)) {
			revert Errors.NotOwnerOfPosition(_tokenId);
		}
		_;
	}
}
