// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IEclypseVault } from "./interfaces/IEclypseVault.sol";
import { IPositionsManager } from "./interfaces/IPositionsManager.sol";

import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { TransferHelper } from "@uniswap-periphery/libraries/TransferHelper.sol";
import { FullMath } from "@uniswap-core/libraries/FullMath.sol";
import { INonfungiblePositionManager } from "@uniswap-periphery/interfaces/INonfungiblePositionManager.sol";
import { IUniswapV3Pool } from "@uniswap-core/interfaces/IUniswapV3Pool.sol";
import { TickMath } from "@uniswap-core/libraries/TickMath.sol";
import { LiquidityAmounts } from "@uniswap-periphery/libraries/LiquidityAmounts.sol";



/**
 * @title EclypseVault contract
 * @author Eclypse Labs
 * @notice This contract has the ownership of the nfts deposited as collateral and can thus increase the liquidity of a position
 * as well as decrease it (with the known uniswap functions). Recieves instructions from the PositionManager contract.
 */

contract EclypseVault is Ownable, IEclypseVault, IERC721Receiver {
	uint256 internal LIQUIDATION_FEES;

	string public constant NAME = "Eclypse Vault";

	INonfungiblePositionManager internal uniswapV3NFPositionsManager;

	address public positionsManagerAddress;
	address public borrowerAddress;

	modifier onlyManager() {
		require(msg.sender == positionsManagerAddress);
		_;
	}

	/**
	 * @notice Set the addresses of various contracts and emit events to indicate that these addresses have been modified.
	 * @param _uniPosNFT The address of the Uniswap V3 NonfungiblePositionManager contract.
	 * @param _positionsManagerAddress The address of the PositionsManager contract.
	 * @dev This function can only be called by the contract owner.
	 */
	function initialize(address _uniPosNFT, address _positionsManagerAddress) external onlyOwner {
		uniswapV3NFPositionsManager = INonfungiblePositionManager(_uniPosNFT);
		positionsManagerAddress = _positionsManagerAddress;
		//renounceOwnership();
	}

	/**
	 * @notice Performs a call on the borrowable asset contract's mint function.
	 * @param _asset The address of the contract to call.
	 * @param _sender The address which will receive the minted tokens.
	 * @param _amount The amount of token to mint.
	 */
	function mint(address _asset, address _sender, uint256 _amount) public onlyManager returns (bool _ok) {
		(_ok, ) = _asset.call(abi.encodeWithSignature("mint(address,uint256)", _sender, _amount));
	}

	/**
	 * @notice Performs a call on the borrowable asset contract's burn function.
	 * @param _asset The address of the contract to call.
	 * @param _amount The amount of token to burn.
	 */
	function burn(address _asset, uint256 _amount) public onlyManager returns (bool _ok) {
		(_ok, ) = _asset.call(abi.encodeWithSignature("burn(uint256)", _amount));
	}

	/**
	 * @notice Increases the liquidity of an LP position.
	 * @param _sender The address of the account that is increasing the liquidity of the LP position.
	 * @param _tokenId The ID of the LP position to be increased.
	 * @param _token0 The address of token 0
	 * @param _token1 The address of token 1
	 * @param _amountAdd0 The amount of token0 to be added to the LP position.
	 * @param _amountAdd1 The amount of token1 to be added to the LP position.
	 * @return liquidity The amount of liquidity added to the LP position.
	 * @return amount0 The amount of token0 added to the LP position.
	 * @return amount1 The amount of token1 added to the LP position.
	 * @dev Only the PositionsManager contract can call this function.
	 */
	function increaseLiquidity(
		address _sender,
		uint256 _tokenId,
		address _token0,
		address _token1,
		uint256 _amountAdd0,
		uint256 _amountAdd1
	) public onlyManager returns (uint128 liquidity, uint256 amount0, uint256 amount1) {
		TransferHelper.safeTransferFrom(_token0, _sender, address(this), _amountAdd0);
		TransferHelper.safeTransferFrom(_token1, _sender, address(this), _amountAdd1);

		TransferHelper.safeApprove(_token0, address(uniswapV3NFPositionsManager), _amountAdd0);
		TransferHelper.safeApprove(_token1, address(uniswapV3NFPositionsManager), _amountAdd1);

		(liquidity, amount0, amount1) = uniswapV3NFPositionsManager.increaseLiquidity(
			INonfungiblePositionManager.IncreaseLiquidityParams({
				tokenId: _tokenId,
				amount0Desired: _amountAdd0,
				amount1Desired: _amountAdd1,
				amount0Min: 0,
				amount1Min: 0,
				deadline: block.timestamp
			})
		);

		if (amount0 < _amountAdd0) {
			TransferHelper.safeTransfer(_token0, _sender, _amountAdd0 - amount0);
		}
		if (amount1 < _amountAdd1) {
			TransferHelper.safeTransfer(_token1, _sender, _amountAdd1 - amount1);
		}
	}

	/**
	 * @notice Decreases the liquidity of an LP position.
	 * @param _sender The address of the position owner.
	 * @param _tokenId The ID of the LP position to be decreased.
	 * @param _liquidityToRemove The amount of liquidity to be removed from the LP position.
	 * @return amount0 The amount of token0 removed from the LP position.
	 * @return amount1 The amount of token1 removed from the LP position.
	 * @dev Only the PositionsManager contract can call this function.
	 */
	function decreaseLiquidity(
		address _sender,
		uint256 _tokenId,
		uint128 _liquidityToRemove
	) public onlyManager returns (uint256 amount0, uint256 amount1) {
		// amount0Min and amount1Min are price slippage checks
		uniswapV3NFPositionsManager.decreaseLiquidity(
			INonfungiblePositionManager.DecreaseLiquidityParams({
				tokenId: _tokenId,
				liquidity: _liquidityToRemove,
				amount0Min: 0,
				amount1Min: 0,
				deadline: block.timestamp
			})
		);

		(amount0, amount1) = uniswapV3NFPositionsManager.collect(
			INonfungiblePositionManager.CollectParams({
				tokenId: _tokenId,
				recipient: _sender,
				amount0Max: type(uint128).max,
				amount1Max: type(uint128).max
			})
		);
	}

	/**
	 * @notice Sends an Position to an account.
	 * @param _to The address of the account that will receive the LP Position.
	 * @param _tokenId The ID of the LP Position to be sent.
	 * @dev Only the PositionsManager contract or the LP Positions Manager contract can call this function.
	 */
	function transferPosition(address _to, uint256 _tokenId) public onlyManager {
		uniswapV3NFPositionsManager.transferFrom(address(this), _to, _tokenId);
	}

	function updateTicks(
		address _sender,
		uint256 _tokenId,
		int24 _newTickLower,
		int24 _newTickUpper,
		IPositionsManager.Position memory _position
	) public onlyManager returns(uint256 newTokenId, uint128 newLiquidity) {
		
		// Remove all the liquidity from the position by decreasing the liquidity to 0
		// This will return the tokens to the Eclypse contract
		uniswapV3NFPositionsManager.decreaseLiquidity(
			INonfungiblePositionManager.DecreaseLiquidityParams({
				tokenId: _tokenId,
				liquidity: _position.liquidity,
				amount0Min: 0,
				amount1Min: 0,
				deadline: block.timestamp
			})
		);

		(uint256 amount0, uint256 amount1) = uniswapV3NFPositionsManager.collect(
			INonfungiblePositionManager.CollectParams({
				tokenId: _tokenId,
				recipient: address(this),
				amount0Max: type(uint128).max,
				amount1Max: type(uint128).max
			})
		);

		// Approve the uniswap v3 positions manager to spend the tokens
		TransferHelper.safeApprove(_position.token0, address(uniswapV3NFPositionsManager), amount0);
		TransferHelper.safeApprove(_position.token1, address(uniswapV3NFPositionsManager), amount1);

		// Mint a new position with the same liquidity but with the new ticks
		uint256 actualAmount0;
		uint256 actualAmount1;
		(newTokenId, newLiquidity, actualAmount0, actualAmount1) = uniswapV3NFPositionsManager.mint(
			INonfungiblePositionManager.MintParams({
				token0: _position.token0,
				token1: _position.token1,
				fee: _position.fee,
				tickLower: _newTickLower,
				tickUpper: _newTickUpper,
				amount0Desired: amount0,
				amount1Desired: amount1,
				amount0Min: 0,
				amount1Min: 0,
				recipient: address(this),
				deadline: block.timestamp
			})
		);

		if (actualAmount0 < amount0) {
			TransferHelper.safeTransfer(_position.token0, address(_sender), amount0 - actualAmount0);
		}
		if (actualAmount1 < amount1) {
			TransferHelper.safeTransfer(_position.token1, address(_sender), amount1 - actualAmount1);
		}

		return (newTokenId, newLiquidity);
	}

	/**
	 * @notice Returns the address of the contract that implements the IERC721Receiver interface.
	 * @return selector The Selector of the IERC721Receiver interface.
	 */
	function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
		return IERC721Receiver.onERC721Received.selector;
	}
}
