// SPDX-License-Identifier: MIT

pragma solidity <0.9.0;

import "./interfaces/IActivePool.sol";
import "contracts/utils/CheckContract.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import "gho-core/src/contracts/gho/GHOToken.sol";

import "@uniswap-core/libraries/FullMath.sol";
import "@uniswap-periphery/libraries/TransferHelper.sol";

import "./interfaces/ILPPositionsManager.sol";
import "./LPPositionsManager.sol";

/**
 * @title ActivePool contract
 * @notice Contains the logic for the Active Pool which holds the ownership of the LP positions.
 * @dev The contract is owned by the Eclypse system, and is called by the LPPositionManager and the BorrowerOperations contracts.
 */

contract ActivePool is Ownable, CheckContract, IActivePool, IERC721Receiver {
	// -- Datas --

	//The liquidation Fee (in %).
	uint256 internal liquidationFees = 5;

	string public constant NAME = "ActivePool";

	// -- Addresses --
	address public borrowerOperationsAddress;
	address public lpPositionsManagerAddress;

	// -- Interfaces --

	INonfungiblePositionManager constant uniswapPositionsNFT =
		INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
	LPPositionsManager lpPositionsManager;

	GhoToken public GHO;

	// -- Methods --

	//-------------------------------------------------------------------------------------------------------------------------------------------------------//
	// Constructors
	//-------------------------------------------------------------------------------------------------------------------------------------------------------//

	/**
	 * @notice Sets the addresses for the Borrower Operations and LP Positions Manager contracts.
	 * @param _borrowerOperationsAddress The address of the Borrower Operations contract.
	 * @param _lpPositionsManagerAddress The address of the LP Positions Manager contract.
	 * @dev The function also sets the lpPositionsManager variable to the LP Positions Manager contract and emits an event to notify of the change in the Borrower Operations address.
	 * @dev Only the contract owner can call this function.
	 */
	function setAddresses(address _borrowerOperationsAddress, address _lpPositionsManagerAddress, address _GhoAddress)
		external
		override
		onlyOwner
	{
		borrowerOperationsAddress = _borrowerOperationsAddress;
		lpPositionsManagerAddress = _lpPositionsManagerAddress;
		GHO = GhoToken(_GhoAddress);

		lpPositionsManager = LPPositionsManager(lpPositionsManagerAddress);

		emit BorrowerOperationsAddressChanged(_borrowerOperationsAddress);
		emit LPPositionsManagerAddressChanged(_lpPositionsManagerAddress);

		//renounceOwnership(); //too early to renounce ownership of the contract yet
	}

	//-------------------------------------------------------------------------------------------------------------------------------------------------------//
	// Getters
	//-------------------------------------------------------------------------------------------------------------------------------------------------------//

	/**
	 * @notice Returns the total amount of ETH collateral in the Active Pool.
	 * @return sum The total amount of ETH collateral in the Active Pool.
	 */
	function getCollateralValue() public view override returns (uint256 sum) {
		for (uint32 i = 0; i < uniswapPositionsNFT.balanceOf(address(this)); i++) {
			sum += lpPositionsManager.positionValueInETH(uniswapPositionsNFT.tokenOfOwnerByIndex(address(this), i));
		}
		return sum;
	}

	/**
	 * @notice Returns the total amount of GHO minted by the protocol.
	 * @return mintedSupply The total amount of GHO minted by the protocol.
	 */
	function getMintedSupply() public view override returns (uint256) {
		(, uint256 bucketLevel) = GHO.getFacilitatorBucket(address(this));
		return bucketLevel;
	}

	/**
	 * @notice Returns the maximum amount of GHO the protocol can mint.
	 * @return MAX_SUPPLY The maximum amount of GHO the protocol can mint.
	 */
	function getMaxSupply() external view override returns (uint256) {
		(uint256 bucketCapacity, ) = GHO.getFacilitatorBucket(address(this));
		return bucketCapacity;
	}

	/**
	 * @notice Returns the total amount of tokens owed to a position.
	 * @param params The parameters for the position.
	 * @return amount0 The amount of token0 owed to the position.
	 * @return amount1 The amount of token1 owed to the position.
	 */
	function feesOwed(INonfungiblePositionManager.CollectParams memory params)
		public
		override
		onlyBOorLPPM
		returns (uint256 amount0, uint256 amount1)
	{
		(amount0, amount1) = uniswapPositionsNFT.collect(params);
		return (amount0, amount1);
	}

	//-------------------------------------------------------------------------------------------------------------------------------------------------------//
	// Positions interaction
	//-------------------------------------------------------------------------------------------------------------------------------------------------------//

	/**
	 * @notice Mints a new LP position.
	 * @param params The parameters for the LP position to be minted.
	 * @dev Only the Borrower Operations contract or the LP Positions Manager contract can call this function.
	 * @return tokenId The ID of the newly minted LP position.
	 */
	function mintPosition(INonfungiblePositionManager.MintParams memory params)
		public
		override
		onlyBOorLPPM
		returns (uint256 tokenId)
	{
		TransferHelper.safeApprove(params.token0, address(uniswapPositionsNFT), params.amount0Desired);
		TransferHelper.safeApprove(params.token1, address(uniswapPositionsNFT), params.amount1Desired);
		(tokenId, , , ) = uniswapPositionsNFT.mint(params);

		emit PositionMinted(tokenId);
		return tokenId;
	}

	/**
	 * @notice Burns an LP position.
	 * @param tokenId The ID of the LP position to be burned.
	 * @dev Only the Borrower Operations contract or the LP Positions Manager contract can call this function.
	 */
	function burnPosition(uint256 tokenId) public override onlyBOorLPPM {
		uniswapPositionsNFT.burn(tokenId);
		emit PositionBurned(tokenId);
	}

	/**
	 * @notice Increases the liquidity of an LP position.
	 * @param sender The address of the account that is increasing the liquidity of the LP position.
	 * @param _tokenId The ID of the LP position to be increased.
	 * @param amountAdd0 The amount of token0 to be added to the LP position.
	 * @param amountAdd1 The amount of token1 to be added to the LP position.
	 * @return liquidity The amount of liquidity added to the LP position.
	 * @return amount0 The amount of token0 added to the LP position.
	 * @return amount1 The amount of token1 added to the LP position.
	 * @dev Only the Borrower Operations contract can call this function.
	 */
	function increaseLiquidity(
		address sender,
		uint256 _tokenId,
		uint256 amountAdd0,
		uint256 amountAdd1
	)
		public
		override
		onlyBorrowerOperations
		returns (
			uint128 liquidity,
			uint256 amount0,
			uint256 amount1
		)
	{
		address token0 = lpPositionsManager.getPosition(_tokenId).token0;
		address token1 = lpPositionsManager.getPosition(_tokenId).token1;

		TransferHelper.safeTransferFrom(token0, sender, address(this), amountAdd0);
		TransferHelper.safeTransferFrom(token1, sender, address(this), amountAdd1);

		TransferHelper.safeApprove(token0, address(uniswapPositionsNFT), amountAdd0);
		TransferHelper.safeApprove(token1, address(uniswapPositionsNFT), amountAdd1);

		(liquidity, amount0, amount1) = uniswapPositionsNFT.increaseLiquidity(
			INonfungiblePositionManager.IncreaseLiquidityParams({
				tokenId: _tokenId,
				amount0Desired: amountAdd0,
				amount1Desired: amountAdd1,
				amount0Min: 0,
				amount1Min: 0,
				deadline: block.timestamp
			})
		);

		TransferHelper.safeTransfer(token0, sender, amountAdd0 - amount0);
		TransferHelper.safeTransfer(token1, sender, amountAdd1 - amount1);

		emit LiquidityIncreased(_tokenId, liquidity);
	}

	/**
	 * @notice Decreases the liquidity of an LP position.
	 * @param _tokenId The ID of the LP position to be decreased.
	 * @param _liquidityToRemove The amount of liquidity to be removed from the LP position.
	 * @return amount0 The amount of token0 removed from the LP position.
	 * @return amount1 The amount of token1 removed from the LP position.
	 * @dev Only the Borrower Operations contract can call this function.
	 */
	function decreaseLiquidity(
		uint256 _tokenId,
		uint128 _liquidityToRemove,
		address sender
	) public override returns (uint256 amount0, uint256 amount1) {
		// amount0Min and amount1Min are price slippage checks

		uniswapPositionsNFT.decreaseLiquidity(
			INonfungiblePositionManager.DecreaseLiquidityParams({
				tokenId: _tokenId,
				liquidity: _liquidityToRemove,
				amount0Min: 0,
				amount1Min: 0,
				deadline: block.timestamp
			})
		);

		(amount0, amount1) = uniswapPositionsNFT.collect(
			INonfungiblePositionManager.CollectParams({
				tokenId: _tokenId,
				recipient: address(this),
				amount0Max: type(uint128).max,
				amount1Max: type(uint128).max
			})
		);

		TransferHelper.safeTransfer(lpPositionsManager.getPosition(_tokenId).token0, sender, amount0);
		TransferHelper.safeTransfer(lpPositionsManager.getPosition(_tokenId).token1, sender, amount1);

		lpPositionsManager.setNewLiquidity(
			_tokenId,
			lpPositionsManager.getPosition(_tokenId).liquidity - _liquidityToRemove
		);

		emit LiquidityDecreased(_tokenId, _liquidityToRemove);
	}

	//-------------------------------------------------------------------------------------------------------------------------------------------------------//
	// Protocol Debt
	//-------------------------------------------------------------------------------------------------------------------------------------------------------//

	/**
	 * @notice Increases the protocol debt.
	 * @param _amount The amount of minted supply to be added to the protocol.
	 * @dev Only the Borrower Operations contract or the LP Positions Manager contract can call this function.
	 */
	function increaseMintedSupply(
		uint256 _amount,
		address sender,
		uint256 tokenId
	) external override onlyBOorLPPM {
		GHO.mint(sender, _amount);

		emit MintedSupplyUpdated(getMintedSupply());
	}

	/**
	 * @notice Decreases the protocol debt.
	 * @param _amount The amount of minted supply to be removed from the protocol.
	 * @dev Only the Borrower Operations contract or the LP Positions Manager contract can call this function.
	 */
	function decreaseMintedSupply(uint256 _amount, address sender) external override onlyBOorLPPM {
		GHO.transferFrom(sender, address(this), _amount);
		GHO.burn(_amount);

		emit MintedSupplyUpdated(getMintedSupply());
	}

	/**
	 * @notice Repays the interest of a user.
	 * @param sender The address of the user that will repay the interest.
	 * @param amount The amount of interest to be repaid.
	 * @dev Only the Borrower Operations contract or the LP Positions Manager contract can call this function.
	 */
	function repayInterestFromUserToProtocol(
		address sender,
		uint256 amount,
		uint256 tokenId
	) external override onlyBOorLPPM {
		require(amount > 0, "ActivePool: Amount must be greater than 0");

		amount = Math.min(lpPositionsManager.debtOf(tokenId), amount);
		GHO.transferFrom(sender, address(this), amount);
		GHO.burn(amount);

		emit InterestRepaid(sender, amount);
	}

	//-------------------------------------------------------------------------------------------------------------------------------------------------------//
	// Assets transfer
	//-------------------------------------------------------------------------------------------------------------------------------------------------------//

	/**
	 * @notice Sends an LP Position to an account.
	 * @param _account The address of the account that will receive the LP Position.
	 * @param _tokenId The ID of the LP Position to be sent.
	 * @dev Only the Borrower Operations contract or the LP Positions Manager contract can call this function.
	 */
	function sendPosition(address _account, uint256 _tokenId) public override onlyBOorLPPM {
		uniswapPositionsNFT.transferFrom(address(this), _account, _tokenId);
		emit PositionSent(_account, _tokenId);
	}

	/**
	 * @notice Sends a Posit to an account.
	 * @param _token The address of the token to be sent.
	 * @param _account The address of the account that will receive the token.
	 * @param _amount The amount of token to be sent.
	 * @dev Only the Borrower Operations contract or the LP Positions Manager contract can call this function.
	 */
	// function sendToken(
	//     address _token,
	//     address _account,
	//     uint256 _amount
	// ) public onlyBOorLPPMorSP onlyBOorLPPM override{
	//     uint256 amountToSend = FullMath.mulDiv(
	//         _amount,
	//         100 - liquidationFees,
	//         100
	//     );
	//     IERC20(_token).transfer(_account, amountToSend);
	//     emit TokenSent(_token, _account, _amount);
	// }

	//-------------------------------------------------------------------------------------------------------------------------------------------------------//
	// Interfaces implementation
	//-------------------------------------------------------------------------------------------------------------------------------------------------------//

	/**
	 * @notice Returns the address of the contract that implements the IERC721Receiver interface.
	 * @return selector The Selector of the IERC721Receiver interface.
	 */
	function onERC721Received(
		address,
		address,
		uint256,
		bytes calldata
	) external pure returns (bytes4) {
		return IERC721Receiver.onERC721Received.selector;
	}

	//-------------------------------------------------------------------------------------------------------------------------------------------------------//
	// Modifiers & Require functions
	//-------------------------------------------------------------------------------------------------------------------------------------------------------//

	/**
	 * @notice Checks if the caller is the Borrower Operations contract.
	 * @dev Reverts if the caller is not the Borrower Operations contract.
	 */
	modifier onlyBorrowerOperations() {
		require(msg.sender == borrowerOperationsAddress);
		_;
	}

	/**
	 * @notice Checks if the caller is the LP Positions Manager contract or the Borrower Operations contract.
	 * @dev Reverts if the caller is not the LP Positions Manager contract or the Borrower Operations contract.
	 */
	modifier onlyBOorLPPM() {
		require(msg.sender == borrowerOperationsAddress || msg.sender == lpPositionsManagerAddress);
		_;
	}
}
