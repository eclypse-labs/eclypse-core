// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IPositionsManager } from "./interfaces/IPositionsManager.sol";
import { IEclypseVault } from "./interfaces/IEclypseVault.sol";
import { IPriceFeed } from "./interfaces/IPriceFeed.sol";
import { Errors } from "./utils/Errors.sol";

import { Denominations } from "@chainlink/Denominations.sol";

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { FixedPoint96 } from "@uniswap-core/libraries/FixedPoint96.sol";
import { FullMath } from "@uniswap-core/libraries/FullMath.sol";
import { TickMath } from "@uniswap-core/libraries/TickMath.sol";
import { TransferHelper } from "@uniswap-periphery/libraries/TransferHelper.sol";
import { LiquidityAmounts } from "@uniswap-periphery/libraries/LiquidityAmounts.sol";
import { OracleLibrary } from "@uniswap-periphery/libraries/OracleLibrary.sol";
import { IUniswapV3Factory } from "@uniswap-core/interfaces/IUniswapV3Factory.sol";
import { INonfungiblePositionManager } from "@uniswap-periphery/interfaces/INonfungiblePositionManager.sol";

/**
 * @title PositionManager contract
 * @author Eclypse Labs
 * @notice Stores all the mappings needed to keep track of the user and their position, containes the logic for
 * oppening a borrower position and borrowing a stablecoin, contains the logic for the collateral valiue of the position
 * and the liquidations.
 * Backend intermediate between the User interactions contract and the Vault and PriceFeed contracts.
 * Transfers all the NFT logic to the Vault contract and the fetching of the price to PriceFeed.
 */

contract PositionsManager is Ownable, IPositionsManager {
	uint256 constant MAX_UINT256 = 2 ** 256 - 1;
	address constant WETHAddress = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

	ProtocolContracts public protocolContracts;

	mapping(address => bool) private whiteListedPools;
	mapping(address => RiskConstants) private riskConstantsFromPool;

	mapping(address => UserPositions) private positionsFromAddress;

	mapping(uint256 => Position) private positionFromTokenId;

	mapping(address => AssetsValues) private assetsValues;

	modifier onlyBorrower() {
		require(msg.sender == address(protocolContracts.userInteractions));
		_;
	}

	modifier onlyBorrowerOrSelf() {
		require(msg.sender == address(protocolContracts.userInteractions) || msg.sender == address(this));
		_;
	}

	//TODO not needed
	modifier onlyVault() {
		require(msg.sender == address(protocolContracts.eclypseVault));
		_;
	}

	/**
	 * @notice Set the addresses of various contracts and emit events to indicate that these addresses have been modified.
	 * @param _uniFactory The address of the Uniswap V3 factory contract.
	 * @param _uniPosNFT The address of the Uniswap V3 positions NFT contract.
	 * @param _userInteractionsAddress The address of the userInteractions contract.
	 * @param _eclypseVaultAddress The address of the EclypseVault contract.
	 * @param _priceFeedAddress The address of the PriceFeed contract.
	 * @dev This function can only be called by the contract owner.
	 */
	function initialize(
		address _uniFactory,
		address _uniPosNFT,
		address _userInteractionsAddress,
		address _eclypseVaultAddress,
		address _priceFeedAddress
	) external onlyOwner {
		protocolContracts.userInteractions = _userInteractionsAddress;
		protocolContracts.eclypseVault = IEclypseVault(_eclypseVaultAddress);
		protocolContracts.uniswapFactory = IUniswapV3Factory(_uniFactory);
		protocolContracts.uniswapPositionsManager = INonfungiblePositionManager(_uniPosNFT);
		protocolContracts.priceFeed = IPriceFeed(_priceFeedAddress);
	}

	/**
	 * @notice Adds a pair of tokens to the protocol.
	 * @dev Adds the pool address to the accepted pool addresses, maps the token addresses to their corresponding WETH pool information, and emits events for each added token.
	 * @param _poolAddress The address of the pool to add to the protocol.
	 */
	function addPoolToProtocol(
		address _poolAddress
	) external onlyOwner {
		whiteListedPools[_poolAddress] = true;
	}

	/**
	 * @notice Add information about borrowable assets.
	 * @param _assetAddress The address of the borrowable asset to add.
	 * @param _assetValue The information abou the borrowable asset we want to add.
	 */
	function addAssetsValuesToProtocol(address _assetAddress, AssetsValues calldata _assetValue) external onlyOwner {
		assetsValues[_assetAddress] = _assetValue;
	}

	/**
	 * @notice Opens a new position for the given token ID and owner.
	 * @dev The position is added to the array of positions owned by the owner, and the position is added to the array of all positions.
	 * @param _owner The address of the position owner.
	 * @param _tokenId The ID of the Uniswap NFT representing the position.
	 * @param _assetAddress The address of the borrowable asset.
	 */
	function openPosition(address _owner, uint256 _tokenId, address _assetAddress) external onlyBorrower {
		protocolContracts.uniswapPositionsManager.safeTransferFrom(_owner, address(protocolContracts.eclypseVault), _tokenId);

		(, , address token0, address token1, uint24 fee, int24 tickLower, int24 tickUpper, uint128 liquidity, , , , ) = protocolContracts
			.uniswapPositionsManager
			.positions(_tokenId);

		address poolAddress = protocolContracts.uniswapFactory.getPool(token0, token1, fee);
		require(whiteListedPools[poolAddress], "This pool is not accepted by the protocol.");

		Position memory position = Position(
			_owner,
			token0,
			token1,
			fee,
			tickLower,
			tickUpper,
			liquidity,
			poolAddress,
			_tokenId,
			Status.active,
			0,
			assetsValues[_assetAddress].interestFactor,
			_assetAddress
		);

		UserPositions storage userPositions = positionsFromAddress[_owner];
		userPositions.positions[userPositions.counter] = position;
		userPositions.counter++;
		positionFromTokenId[_tokenId] = position;
	}

	/**
	 * @notice Closes a position.
	 * @param _owner The owner of the position.
	 * @param _tokenId The ID of the Uniswap V3 NFT representing the position.
	 * @dev The caller must have approved the transfer of the Uniswap V3 NFT from the BorrowerOperations contract to their wallet.
	 */
	function closePosition(address _owner, uint256 _tokenId) external onlyBorrower {
		uint256 debt = debtOf(_tokenId);
		if (debt > 0) {
			repay(_owner, _tokenId, debt);
		}

		protocolContracts.eclypseVault.transferPosition(_owner, _tokenId);
		positionFromTokenId[_tokenId].status = Status.closedByOwner;
	}

	/**
	 * @notice Retrieves the position of a given token
	 * @param _tokenId The token to retrieve the position for
	 * @return position The position of the given token
	 */
	function getPosition(uint256 _tokenId) public view returns (Position memory position) {
		return positionFromTokenId[_tokenId];
	}

	function getUserActivePositions(address _owner) public view returns (uint256 count, Position[] memory) {
		count = positionsFromAddress[_owner].counter;
		Position[] memory positions = new Position[](count);
		for (uint256 i = 0; i < count; i++) {
			if (positionsFromAddress[_owner].positions[i].status == Status.active) {
				positions[i] = positionsFromAddress[_owner].positions[i];
			}
		}
		return (count, positions);
	}

	/**
	 * @notice Returns the amount of tokens 0 and 1 of a position.
	 * @dev The amounts of tokens are calculated using the UniswapV3 TWAP Oracle mechanism.
	 * @param _tokenId The token ID to retrieve the amounts for.
	 * @return amountToken0 The amount of tokens 0.
	 * @return amountToken1 The amount of tokens 1.
	 */
	function positionAmounts(uint256 _tokenId) public view returns (uint256 amountToken0, uint256 amountToken1) {
		Position memory _position = positionFromTokenId[_tokenId];
		(int24 twappedTick, ) = OracleLibrary.consult(_position.poolAddress, assetsValues[_position.assetAddress].twapLength);

		uint160 sqrtRatioX96 = TickMath.getSqrtRatioAtTick(twappedTick);
		uint160 sqrtRatio0X96 = TickMath.getSqrtRatioAtTick(_position.tickLower);
		uint160 sqrtRatio1X96 = TickMath.getSqrtRatioAtTick(_position.tickUpper);
		(amountToken0, amountToken1) = LiquidityAmounts.getAmountsForLiquidity(sqrtRatioX96, sqrtRatio0X96, sqrtRatio1X96, _position.liquidity);
		(, , , , , , , , , , uint128 fee0, uint128 fee1) = protocolContracts.uniswapPositionsManager.positions(_tokenId);
		return (amountToken0 + fee0, amountToken1 + fee1);
	}

	//TODO add comment of function
	function refreshDebtTracking(address assetAddress) public {
		AssetsValues storage assetValues = assetsValues[assetAddress];
		uint256 newInterestFactor = power(assetValues.interestRate, block.timestamp - assetValues.lastFactorUpdate);
		assetValues.interestFactor = FullMath.mulDivRoundingUp(assetsValues[assetAddress].interestFactor, newInterestFactor, FixedPoint96.Q96);
		assetValues.lastFactorUpdate = block.timestamp;
	}

	/**
	 * @notice Returns the value of a position in ETH.
	 * @dev The value is calculated using the price of the tokens in ETH.
	 * @param _tokenId The ID of the position to get the value of.
	 * @return value The value of the position in ETH.
	 */
	function positionValueInETH(uint256 _tokenId) public view returns (uint256 value) {
		(uint256 amount0, uint256 amount1) = positionAmounts(_tokenId);
		address token0 = positionFromTokenId[_tokenId].token0;
		address token1 = positionFromTokenId[_tokenId].token1;
		IERC20Metadata token0Metadata = IERC20Metadata(token0);
		IERC20Metadata token1Metadata = IERC20Metadata(token1);
		value =
			FullMath.mulDiv(
				amount0,
				protocolContracts.priceFeed.getPrice(token0, Denominations.ETH) * 10 ** 18,
				FixedPoint96.Q96 * 10 ** token0Metadata.decimals()
			) +
			FullMath.mulDiv(
				amount1,
				protocolContracts.priceFeed.getPrice(token1, Denominations.ETH) * 10 ** 18,
				FixedPoint96.Q96 * 10 ** token1Metadata.decimals()
			);
		return value;
	}

	/**
	 * @notice Returns the total value of all active positions of a user in ETH.
	 * @dev The value is calculated using the price of the tokens in ETH.
	 * @param _user The address of the user to get the total value of.
	 * @return totalValue The total value of all active positions of the user in ETH.
	 */
	function totalPositionsValueInETH(address _user) public view returns (uint256 totalValue) {
		UserPositions storage userPositions = positionsFromAddress[_user];
		for (uint32 i = 0; i < userPositions.counter; i++) {
			if (userPositions.positions[i].status == Status.active) {
				totalValue += positionValueInETH(userPositions.positions[i].tokenId);
			}
		}
	}

	/**
	 * @notice Returns the total debt of a position, including interest.
	 * @dev The debt is calculated using the interest rate and the last update timestamp of the position.
	 * @param _tokenId The ID of the position to get the debt of.
	 * @return currentDebt The total debt of the position, including interest.
	 */
	function debtOf(uint256 _tokenId) public view returns (uint256 currentDebt) {
		Position memory position = positionFromTokenId[_tokenId];
		AssetsValues memory assetValues = assetsValues[position.assetAddress];
		uint256 debtPrincipal = position.debtPrincipal;
		currentDebt = FullMath.mulDivRoundingUp(debtPrincipal, assetValues.interestFactor, position.interestConstant);
		uint256 newInterestFactor = power(assetValues.interestRate, block.timestamp - assetValues.lastFactorUpdate);
		currentDebt = FullMath.mulDivRoundingUp(currentDebt, newInterestFactor, FixedPoint96.Q96);
	}

	function allDebtComponentsOf(uint256 _tokenId) public view returns (uint256 currentDebt, uint256 debtPrincipal, uint256 interest) {
		Position memory _position = positionFromTokenId[_tokenId];
		AssetsValues memory assetValues = assetsValues[_position.assetAddress];
		debtPrincipal = getPosition(_tokenId).debtPrincipal;
		currentDebt = FullMath.mulDivRoundingUp(debtPrincipal, assetValues.interestFactor, getPosition(_tokenId).interestConstant);
		uint256 newInterestFactor = power(assetValues.interestRate, block.timestamp - assetValues.lastFactorUpdate);
		currentDebt = FullMath.mulDivRoundingUp(currentDebt, newInterestFactor, FixedPoint96.Q96);
		interest = currentDebt - debtPrincipal;
	}

	/**
	 * @notice Returns the total debt of a user, including interest.
	 * @dev The debt is calculated using the interest rate and the last update timestamp of the position.
	 * @param _user The address of the user to get the debt of.
	 * @return totalDebt The total debt of the user, including interest.
	 */
	function totalDebtOf(address _user) external view returns (uint256 totalDebt) {
		UserPositions storage userPositions = positionsFromAddress[_user];
		for (uint32 i = 0; i < userPositions.counter; i++) {
			if (userPositions.positions[i].status == Status.active) {
				totalDebt += debtOf(userPositions.positions[i].tokenId);
			}
		}
	}

	/**
	 * @notice Returns the debt of a position in ETH.
	 * @dev The debt is calculated using the price of the token in ETH.
	 * @param _tokenId The ID of the position to get the debt of.
	 * @return debtInETH The debt of the position in ETH. - 18 decimals
	 */
	function debtOfInETH(uint256 _tokenId) public view returns (uint256) {
		uint256 ethUsdPrice = protocolContracts.priceFeed.getPrice(Denominations.ETH, Denominations.USD);
		IERC20Metadata asset = IERC20Metadata(positionFromTokenId[_tokenId].assetAddress);
		// FixedPoint96.Q96 from the PriceFeed, 18 decimals for ETH, asset decimals for <asset> (the stablecoin)
		uint factorNumerator = FixedPoint96.Q96 * 10 ** 18 > asset.decimals() ? FixedPoint96.Q96 * 10 ** (18 - asset.decimals()) : 1;
		uint factorDenominator = FixedPoint96.Q96 * 10 ** 18 < asset.decimals() ? 10 ** (asset.decimals() - 18) / FixedPoint96.Q96 : 1;
		return FullMath.mulDivRoundingUp(debtOf(_tokenId), factorNumerator, ethUsdPrice * factorDenominator);
	}

	/**
	 * @notice Increases the debt of a position by a given amount.
	 * @dev The debt is increased by the given amount, and the last update timestamp is set to the current block timestamp.
	 * @param sender The address of the user that is increasing its debt.
	 * @param _tokenId The ID of the position to increase the debt of.
	 * @param _amount The amount to increase the debt of the position by.
	 */
	function borrow(address sender, uint256 _tokenId, uint256 _amount) external onlyBorrower {
		require(_amount > 0, "A debt cannot be increased by 0.");

		refreshDebtTracking(positionFromTokenId[_tokenId].assetAddress);

		// From here, the interestFactor is up-to-date.
		(uint256 totalDebt, uint256 debtPrincipal, ) = allDebtComponentsOf(_tokenId);
		Position storage position = positionFromTokenId[_tokenId];
		AssetsValues storage assetValues = assetsValues[position.assetAddress];

		protocolContracts.eclypseVault.mint(position.assetAddress, sender, _amount);
		assetValues.totalBorrowedStableCoin += _amount;

		position.interestConstant = FullMath.mulDiv(assetValues.interestFactor, debtPrincipal + _amount, totalDebt + _amount);
		position.debtPrincipal += _amount;

		if (liquidatable(_tokenId)) {
			revert("The position can't be liquidatable!");
		}
	}

	/**
	 * @notice Decreases the debt of a position by a given amount.
	 * @dev The debt is decreased by the given amount, and the last update timestamp is set to the current block timestamp.
	 * @param _tokenId The ID of the position to decrease the debt of.
	 * @param _amount The amount to decrease the debt of the position by.
	 */
	function repay(address sender, uint256 _tokenId, uint256 _amount) public onlyBorrowerOrSelf {
		require(_amount > 0, "A debt cannot be decreased by 0.");

		Position storage position = positionFromTokenId[_tokenId];

		_repay(sender, _tokenId, _amount, position);
	}

	function _repay(address sender, uint256 _tokenId, uint256 _amount, Position storage position) internal {
		AssetsValues storage assetValues = assetsValues[position.assetAddress];
		refreshDebtTracking(position.assetAddress);

		// From here, the interestFactor is up-to-date.
		(uint256 currentDebt, uint256 debtPrincipal, uint256 accumulatedInterest) = allDebtComponentsOf(_tokenId);

		_amount = _amount < currentDebt ? _amount : currentDebt;

		uint256 interestRepayment = _amount < accumulatedInterest ? _amount : accumulatedInterest;
		uint256 principalRepayment = _amount - interestRepayment;

		IERC20(position.assetAddress).transferFrom(sender, address(protocolContracts.eclypseVault), principalRepayment + interestRepayment);

		if (principalRepayment > 0) {
			protocolContracts.eclypseVault.burn(position.assetAddress, principalRepayment);
			assetValues.totalBorrowedStableCoin -= principalRepayment;
		}

		uint256 newDebt = currentDebt - _amount;
		uint256 newDebtPrincipal = debtPrincipal - principalRepayment;
		if (newDebt > 0) {
			position.interestConstant = FullMath.mulDivRoundingUp(assetValues.interestFactor, newDebtPrincipal, newDebt);
		} else {
			position.interestConstant = assetValues.interestFactor;
		}
		position.debtPrincipal = newDebtPrincipal;
	}

	/**
	 * @notice Increases the liquidity of an LP position.
	 * @param sender The address of the account that is increasing the liquidity of the LP position.
	 * @param tokenId The ID of the LP position to be increased.
	 * @param amountAdd0 The amount of token0 to be added to the LP position.
	 * @param amountAdd1 The amount of token1 to be added to the LP position.
	 * @return liquidity The amount of liquidity added to the LP position.
	 * @return amount0 The amount of token0 added to the LP position.
	 * @return amount1 The amount of token1 added to the LP position.
	 * @dev Only the Borrower Operations contract can call this function.
	 */
	function deposit(
		address sender,
		uint256 tokenId,
		uint256 amountAdd0,
		uint256 amountAdd1
	) external onlyBorrower returns (uint128 liquidity, uint256 amount0, uint256 amount1) {
		Position storage position = positionFromTokenId[tokenId];
		address token0 = position.token0;
		address token1 = position.token1;

		(liquidity, amount0, amount1) = protocolContracts.eclypseVault.increaseLiquidity(sender, tokenId, token0, token1, amountAdd0, amountAdd1);

		position.liquidity = liquidity;
	}

	/**
	 * @notice Decreases the liquidity of an LP position.
	 * @param tokenId The ID of the LP position to be decreased.
	 * @param liquidityToRemove The amount of liquidity to be removed from the LP position.
	 * @return amount0 The amount of token0 removed from the LP position.
	 * @return amount1 The amount of token1 removed from the LP position.
	 * @dev Only the Borrower Operations contract can call this function.
	 */
	function withdraw(address sender, uint256 tokenId, uint128 liquidityToRemove) external onlyBorrower returns (uint256 amount0, uint256 amount1) {
		Position storage position = positionFromTokenId[tokenId];
		liquidityToRemove = liquidityToRemove > position.liquidity ? position.liquidity : liquidityToRemove;

		(amount0, amount1) = protocolContracts.eclypseVault.decreaseLiquidity(sender, tokenId, liquidityToRemove);

		position.liquidity -= liquidityToRemove;
	}

	function updateTicks(
		address _sender,
		uint256 _tokenId,
		int24 _newTickLower,
		int24 _newTickUpper
	) external onlyBorrower returns (uint256 newTokenId) {
		Position memory position = positionFromTokenId[_tokenId];
		uint128 newLiquidity;
		(newTokenId, newLiquidity) = protocolContracts.eclypseVault.updateTicks(_sender, _tokenId, _newTickLower, _newTickUpper, position);
		position.tokenId = newTokenId;
		position.tickLower = _newTickLower;
		position.tickUpper = _newTickUpper;
		position.liquidity = newLiquidity;

		positionFromTokenId[newTokenId] = position;
		positionFromTokenId[_tokenId].status = Status.nonExistent;


		if (liquidatable(newTokenId)) {
			revert("The position can't be liquidatable!");
		}

		return newTokenId;
	}

	/**
	 * @notice Returns the collateral ratio of a position.
	 * @param _tokenId The ID of the position to get the collateral ratio of.
	 * @return collRatio The collateral ratio of the position.
	 */
	function collRatioOf(uint256 _tokenId) public view returns (uint256) {
		uint256 debt = debtOfInETH(_tokenId);
		uint256 collValue = positionValueInETH(_tokenId);
		return debt > 0 ? FullMath.mulDiv(collValue, FixedPoint96.Q96, debt) : MAX_UINT256;
	}

	/**
	 * @notice Returns the risk constants of a pool.
	 * @dev The risk constants are the minimum collateral ratio of the pool.
	 * @param _pool The address of the pool to get the risk constants of.
	 * @return riskConstants The risk constants ratio of the pool.
	 */
	function getRiskConstants(address _pool) public view returns (uint256 riskConstants) {
		return riskConstantsFromPool[_pool].minCR;
	}

	/**
	 * @notice Updates the risk constants of a pool.
	 * @dev The risk constants are the minimum collateral ratio of the pool.
	 * @param _pool The address of the pool to update the risk constants of.
	 * @param _riskConstants The new risk constants ratio of the pool.
	 */
	function updateRiskConstants(address _pool, uint256 _riskConstants) public onlyOwner {
		require(_riskConstants > FixedPoint96.Q96, "The minimum collateral ratio must be greater than 1.");
		riskConstantsFromPool[_pool].minCR = _riskConstants;
	}

	/**
	 * @notice Checks if a position is liquidatable.
	 * @dev A position is liquidatable if its collateral ration is less than the minimum collateral ratio of the pool it is in.
	 * @param _tokenId The ID of the position to check.
	 * @return isLiquidatable, true if the position is liquidatable and false otherwise.
	 */
	function liquidatable(uint256 _tokenId) public view returns (bool) {
		Position memory position = positionFromTokenId[_tokenId];
		return _liquidatable(positionValueInETH(_tokenId), debtOfInETH(_tokenId), riskConstantsFromPool[position.poolAddress].minCR);
	}

	function _liquidatable(uint256 collateralValueInETH, uint256 debtInETH, uint256 minCR) internal pure returns (bool) {
		return collateralValueInETH * FixedPoint96.Q96 < debtInETH * minCR;
	}

	/**
	 * @notice Liquidates a position.
	 * @dev Given that the caller has enough GHO to reimburse the position's debt, the position is liquidated, the GHO is burned and the NFT is transfered to the caller.
	 * @param _tokenId The ID of the position to liquidate.
	 * @param _maxPayment The largest amount of stablecoin to repay to reimburse the debt of the position.
	 */
	function liquidatePosition(uint256 _tokenId, uint256 _maxPayment) public {
		require(_tokenId > 0, "Invalid tokenId");
		require(_maxPayment > 0, "Invalid maxPayment");

		Position storage position = positionFromTokenId[_tokenId];
		uint256 collateralValueInETH = positionValueInETH(_tokenId);
		uint256 debt = debtOf(_tokenId);
		uint256 debtInETH = debtOfInETH(_tokenId);
		uint256 minCR = riskConstantsFromPool[position.poolAddress].minCR;
		require(_liquidatable(collateralValueInETH, debtInETH, minCR), "The position is not liquidatable.");

		// half of (minCR-1) is bonus for the liquidator [THIS IS ARBITRARY, TO BE DISCUSSED]
		uint liquidationBonusRatio = ((minCR - FixedPoint96.Q96) / 2 + FixedPoint96.Q96);
		uint128 liquidityToRepay;
		uint256 eclypseLiquidationBonus = 0;

		// if the positionValue is less than or equal to the debt * liquidationBonusRatio, the liquidator will no longer have the 50% restriction
		// because it's impossible to improve the collateral ratio of the position back to "healthy" levels, so we just want to get rid of it.
		if (collateralValueInETH * FixedPoint96.Q96 <= debtInETH * liquidationBonusRatio) {
			_maxPayment = Math.min(_maxPayment, debt);
			liquidityToRepay = uint128(FullMath.mulDiv(position.liquidity, _maxPayment, debt));
		} else {
			// if the positionValue is greater than the debt * liquidationBonusRatio, the liquidator will have the 50% restriction
			// because it's possible to improve the collateral ratio of the position back to "healthy" levels
			_maxPayment = Math.min(_maxPayment, debt / 2);
			uint256 liquidityOfDebt = FullMath.mulDiv(position.liquidity, debtInETH, collateralValueInETH);
			// liquidator gets his share of the position's liquidity (at most 50% of the "scaled" liquidity, i.e. the liquidity that represents the debt)
			// and additionally gets the bonus for liquidating the position (scaled liquidity * (liquidationBonusRatio - 1))
			liquidityToRepay = uint128(
				FullMath.mulDiv(liquidityOfDebt, _maxPayment, debt) +
					FullMath.mulDiv(liquidityOfDebt, liquidationBonusRatio - FixedPoint96.Q96, FixedPoint96.Q96)
			);
			eclypseLiquidationBonus = FullMath.mulDiv(liquidityOfDebt, liquidationBonusRatio - FixedPoint96.Q96, FixedPoint96.Q96) / 5; // Eclypse gets 20% of the liquidation bonus.
		}

		if (liquidityToRepay == position.liquidity) {
			position.status = Status.closedByLiquidation;
		}

		position.liquidity -= liquidityToRepay;

		//IERC20(position.assetAddress).transferFrom(msg.sender, address(protocolContracts.eclypseVault), _maxPayment);
		_repay(msg.sender, _tokenId, _maxPayment, position);
		protocolContracts.eclypseVault.burn(position.assetAddress, _maxPayment - eclypseLiquidationBonus); // Eclypse keeps 20% of the liquidation bonus.
		protocolContracts.eclypseVault.decreaseLiquidity(msg.sender, _tokenId, liquidityToRepay);
	}

	/**
	 * @notice Liquidates multiple positions.
	 * @dev Given that the callers have enough stablecoin to reimburse the positions' debt, the positions are liquidated, the stablecoin is burned, and the NFTs are transferred to the callers.
	 * @param _tokenIds The IDs of the positions to liquidate, using calldata to save gas.
	 * @param _amountRepays The amounts of stablecoin to repay to reimburse the debt of the positions, using calldata to save gas.
	 */
	function batchliquidate(uint256[] calldata _tokenIds, uint256[] calldata _amountRepays) public {
		require(_tokenIds.length == _amountRepays.length, "Input arrays must have the same length");
		for (uint256 i = 0; i < _tokenIds.length; i++) {
			liquidatePosition(_tokenIds[i], _amountRepays[i]);
		}
	}

	/**
	 * @notice Getter for the AssetsValues (information) of a given borrowable asset.
	 */
	function getAssetsValues(address _assets) external view returns (AssetsValues memory) {
		return assetsValues[_assets];
	}

	/**
	 * @notice Computes the power of a fixedpoint96 number.
	 */
	function power(uint256 _base, uint256 _exponent) public pure returns (uint256 result) {
		// do fast exponentiation by checking parity of exponent
		if (_exponent == 0) {
			result = FixedPoint96.Q96;
		} else if (_exponent == 1) {
			result = _base;
		} else {
			result = power(_base, _exponent / 2);
			// calculate the square of the square root with FullMath.mulDiv
			result = FullMath.mulDiv(result, result, FixedPoint96.Q96);
			if (_exponent % 2 == 1) {
				// calculate the square of the square root with FullMath.mulDiv and multiply by base once
				result = FullMath.mulDiv(result, _base, FixedPoint96.Q96);
			}
		}
	}
}
