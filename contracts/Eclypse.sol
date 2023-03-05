// SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

import "./interfaces/IEclypse.sol";
import "./interfaces/IBorrowerOperations.sol";
import "forge-std/Test.sol";

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "@uniswap-core/libraries/TickMath.sol";
import "@uniswap-core/libraries/FullMath.sol";
import "@uniswap-core/libraries/FixedPoint96.sol";
import "@uniswap-core/interfaces/IUniswapV3Factory.sol";

import "@uniswap-periphery/interfaces/INonfungiblePositionManager.sol";
import "@uniswap-periphery/libraries/LiquidityAmounts.sol";
import "@uniswap-periphery/libraries/PoolAddress.sol";
import "@uniswap-periphery/libraries/OracleLibrary.sol";
import "@uniswap-periphery/libraries/TransferHelper.sol";

import "gho-core/src/contracts/gho/GHOToken.sol";

/**
 * @title LPPositionsManager contract
 * @notice Contains the logic for position operations performed by users.
 * @dev The contract is owned by the Eclypse system, and is called by the BorrowerOperations and ActivePool contracts.
 */

contract Eclypse is IEclypse, Ownable, Test {
    uint256 constant MAX_UINT256 = 2 ** 256 - 1;

    ProtocolValues public protocolValues;

    address constant WETHAddress = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    IUniswapV3Factory internal uniswapFactory; // = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    INonfungiblePositionManager internal uniswapPositionsNFT; // = INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
    GhoToken public GHO;
    IBorrowerOperations public borrowerOperations;

    mapping(address => bool) private whiteListedPools;
    mapping(address => RiskConstants) private riskConstantsFromPool;
    mapping(address => Position[]) private positionsFromAddress;
    mapping(uint256 => Position) private positionFromTokenId;
    mapping(address => PoolPricingInfo) private tokenToWETHPoolInfo;
    Position[] private allPositions;

    function setAddresses(address _uniFactory, address _uniPosNFT, address _GhoAddr, address _borrowerOpAddr)
        external
        onlyOwner
    {
        uniswapFactory = IUniswapV3Factory(_uniFactory);
        uniswapPositionsNFT = INonfungiblePositionManager(_uniPosNFT);

        GHO = GhoToken(_GhoAddr);
        borrowerOperations = IBorrowerOperations(_borrowerOpAddr);

        // renounceOwnership();
    }

    /**
     * @notice Adds a pair of tokens to the protocol.
     * @dev Adds the pool address to the accepted pool addresses, maps the token addresses to their corresponding WETH pool information, and emits events for each added token.
     * @param _poolAddress The address of the pool to add to the protocol.
     * @param _token0 The address of the first token in the pair.
     * @param _token1 The address of the second token in the pair.
     * @param _ETHpoolToken0 The address of the WETH pool for the first token.
     * @param _ETHpoolToken1 The address of the WETH pool for the second token.
     * @param _inv0 Whether the first token's price is inversed in the WETH pool.
     * @param _inv1 Whether the second token's price is inversed in the WETH pool.
     */
    function addPairToProtocol(
        address _poolAddress,
        address _token0,
        address _token1,
        address _ETHpoolToken0,
        address _ETHpoolToken1,
        bool _inv0,
        bool _inv1
    ) public override onlyOwner {
        whiteListedPools[_poolAddress] = true;
        if (_token0 != WETHAddress) {
            tokenToWETHPoolInfo[_token0] = PoolPricingInfo(_ETHpoolToken0, _inv0);
            emit TokenAddedToPool(_token0, _ETHpoolToken0);
        }
        if (_token1 != WETHAddress) {
            tokenToWETHPoolInfo[_token1] = PoolPricingInfo(_ETHpoolToken1, _inv1);
            emit TokenAddedToPool(_token1, _ETHpoolToken1);
        }
    }

    //-------------------------------------------------------------------------------------------------------------------------------------------------------//
    // Getters for positions
    //-------------------------------------------------------------------------------------------------------------------------------------------------------//

    /**
     * @notice Retrieves the position of a given token
     * @param _tokenId The token to retrieve the position for
     * @return position The position of the given token
     */
    function getPosition(uint256 _tokenId) public view returns (Position memory position) {
        return positionFromTokenId[_tokenId];
    }

    /**
     * @notice Returns the total number of positions owned by all users.
     * @return totalCount The number of positions owned by all users.
     */
    function getPositionsCount() external view returns (uint256) {
        return allPositions.length;
    }

    //for testing, delete afterwards - or maybe not - we may want to keep it for easier implementation
    function getProtocolValues() external view returns (ProtocolValues memory) {
        return protocolValues;
    }

    //for testing, delete afterwards - or maybe not - we may want to keep it for easier implementation
    function setProtocolValues(ProtocolValues memory _protocolValues) external {
        protocolValues = _protocolValues;
    }

    //-------------------------------------------------------------------------------------------------------------------------------------------------------//
    // Position Statuses
    //-------------------------------------------------------------------------------------------------------------------------------------------------------//

    /**
     * @notice Changes the status of a position with a given token ID.
     * @dev The position must have a different status than the one provided.
     * @param _tokenId The token ID of the position.
     * @param _status The new status of the position.
     */
    function changePositionStatus(uint256 _tokenId, Status _status) public onlyBorrowerOperations {
        require(
            positionFromTokenId[_tokenId].status != _status, "A position status cannot be changed to its current one."
        );
        positionFromTokenId[_tokenId].status = _status;
        emit PositionStatusChanged(_tokenId, _status);
    }

    /**
     * @notice Opens a new position for the given token ID and owner.
     * @dev The position is added to the array of positions owned by the owner, and the position is added to the array of all positions.
     * @param _owner The address of the position owner.
     * @param _tokenId The ID of the Uniswap NFT representing the position.
     */
    function openPosition(address _owner, uint256 _tokenId) public override onlyBorrowerOperations {
        (,, address token0, address token1, uint24 fee, int24 tickLower, int24 tickUpper, uint128 liquidity,,,,) =
            uniswapPositionsNFT.positions(_tokenId);

        address poolAddress = uniswapFactory.getPool(token0, token1, fee);
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
            protocolValues.interestFactor
        );

        allPositions.push(position);
        positionsFromAddress[_owner].push(position);
        positionFromTokenId[_tokenId] = position;

        emit DepositedLP(_owner, _tokenId);
    }

    //-------------------------------------------------------------------------------------------------------------------------------------------------------//
    // Position Amounts
    //-------------------------------------------------------------------------------------------------------------------------------------------------------//

    /**
     * @notice Returns the amount of tokens 0 and 1 of a position.
     * @dev The amounts of tokens are calculated using the UniswapV3 TWAP Oracle mechanism.
     * @param _tokenId The token ID to retrieve the amounts for.
     * @return amountToken0 The amount of tokens 0.
     * @return amountToken1 The amount of tokens 1.
     */
    function positionAmounts(uint256 _tokenId)
        public
        view
        override
        returns (uint256 amountToken0, uint256 amountToken1)
    {
        Position memory _position = positionFromTokenId[_tokenId];
        (int24 twappedTick,) = OracleLibrary.consult(_position.poolAddress, protocolValues.twapLength);

        uint160 sqrtRatioX96 = TickMath.getSqrtRatioAtTick(twappedTick);
        uint160 sqrtRatio0X96 = TickMath.getSqrtRatioAtTick(_position.tickLower);
        uint160 sqrtRatio1X96 = TickMath.getSqrtRatioAtTick(_position.tickUpper);
        (uint256 amount0, uint256 amount1) =
            LiquidityAmounts.getAmountsForLiquidity(sqrtRatioX96, sqrtRatio0X96, sqrtRatio1X96, _position.liquidity);

        return (amount0, amount1);
    }

    //-------------------------------------------------------------------------------------------------------------------------------------------------------//
    // Debt Functions
    //-------------------------------------------------------------------------------------------------------------------------------------------------------//

    /**
     * @notice Returns the total debt of a position, including interest.
     * @dev The debt is calculated using the interest rate and the last update timestamp of the position.
     * @param _tokenId The ID of the position to get the debt of.
     * @return currentDebt The total debt of the position, including interest.
     */
    function debtOf(uint256 _tokenId) public view override returns (uint256 currentDebt) {
        uint256 debtPrincipal = getPosition(_tokenId).debtPrincipal;
        currentDebt = FullMath.mulDivRoundingUp(
            debtPrincipal, protocolValues.interestFactor, getPosition(_tokenId).interestConstant
        );
        uint256 newInterestFactor =
            lessDumbPower(protocolValues.interestRate, block.timestamp - protocolValues.lastFactorUpdate);
        currentDebt = FullMath.mulDivRoundingUp(currentDebt, newInterestFactor, FixedPoint96.Q96);
    }

    /**
     * @notice Returns the total debt of a user, including interest.
     * @dev The debt is calculated using the interest rate and the last update timestamp of the position.
     * @param _user The address of the user to get the debt of.
     * @return totalDebtInGHO The total debt of the user, including interest.
     */
    function totalDebtOf(address _user) public view returns (uint256 totalDebtInGHO) {
        for (uint32 i = 0; i < positionsFromAddress[_user].length; i++) {
            if (positionsFromAddress[_user][i].status == Status.active) {
                totalDebtInGHO += debtOf(positionsFromAddress[_user][i].tokenId);
            }
        }
        return totalDebtInGHO;
    }

    /**
     * @notice Increases the debt of a position by a given amount.
     * @dev The debt is increased by the given amount, and the last update timestamp is set to the current block timestamp.
     * @param _tokenId The ID of the position to increase the debt of.
     * @param _amount The amount to increase the debt of the position by.
     */
    function increaseDebtOf(address sender, uint256 _tokenId, uint256 _amount)
        public
        override
        onlyBorrowerOperations
        onlyActivePosition(_tokenId)
    {
        require(_amount > 0, "A debt cannot be increased by a negative amount or by 0.");

        uint256 debtPrincipal = getPosition(_tokenId).debtPrincipal;
        uint256 currentDebt = FullMath.mulDivRoundingUp(
            debtPrincipal, protocolValues.interestFactor, getPosition(_tokenId).interestConstant
        );
        uint256 newInterestFactor =
            lessDumbPower(protocolValues.interestRate, block.timestamp - protocolValues.lastFactorUpdate);
        currentDebt = FullMath.mulDivRoundingUp(currentDebt, newInterestFactor, FixedPoint96.Q96);

        GHO.mint(sender, _amount);
        protocolValues.totalBorrowedGho += _amount;

        protocolValues.interestFactor =
            FullMath.mulDivRoundingUp(protocolValues.interestFactor, newInterestFactor, FixedPoint96.Q96);
        protocolValues.lastFactorUpdate = block.timestamp;

        positionFromTokenId[_tokenId].interestConstant =
            FullMath.mulDivRoundingUp(protocolValues.interestFactor, debtPrincipal + _amount, currentDebt + _amount);
        positionFromTokenId[_tokenId].debtPrincipal += _amount;

        emit IncreasedDebt(positionFromTokenId[_tokenId].user, _tokenId, currentDebt, currentDebt + _amount);
    }

    /**
     * @notice Decreases the debt of a position by a given amount.
     * @dev The debt is decreased by the given amount, and the last update timestamp is set to the current block timestamp.
     * @param _tokenId The ID of the position to decrease the debt of.
     * @param _amount The amount to decrease the debt of the position by.
     */
    function decreaseDebtOf(address sender, uint256 _tokenId, uint256 _amount)
        public
        override
        onlyBorrowerOperations
        onlyActivePosition(_tokenId)
    {
        require(_amount > 0, "A debt cannot be decreased by a negative amount or by 0.");

        uint256 debtPrincipal = getPosition(_tokenId).debtPrincipal;
        uint256 currentDebt = FullMath.mulDivRoundingUp(
            debtPrincipal, protocolValues.interestFactor, getPosition(_tokenId).interestConstant
        );
        uint256 newInterestFactor =
            lessDumbPower(protocolValues.interestRate, block.timestamp - protocolValues.lastFactorUpdate);
        currentDebt = FullMath.mulDivRoundingUp(currentDebt, newInterestFactor, FixedPoint96.Q96);

        uint256 oldDebt = currentDebt;
        uint256 accumulatedInterest = currentDebt - debtPrincipal;

        protocolValues.interestFactor =
            FullMath.mulDivRoundingUp(protocolValues.interestFactor, newInterestFactor, FixedPoint96.Q96);
        protocolValues.lastFactorUpdate = block.timestamp;

        _amount = Math.min(_amount, currentDebt);

        if (_amount > accumulatedInterest) {
            _amount -= accumulatedInterest;
            accumulatedInterest = 0;
        } else {
            accumulatedInterest -= _amount;
            _amount = 0;
        }

        currentDebt = debtPrincipal + accumulatedInterest;

        uint256 totalAmountChange = Math.min(_amount, protocolValues.totalBorrowedGho);
        GHO.transferFrom(sender, address(this), totalAmountChange);
        GHO.burn(totalAmountChange);
        protocolValues.totalBorrowedGho -= totalAmountChange;

        positionFromTokenId[_tokenId].interestConstant = currentDebt - _amount > 0
            ? FullMath.mulDivRoundingUp(protocolValues.interestFactor, debtPrincipal - _amount, currentDebt - _amount)
            : protocolValues.interestFactor;

        positionFromTokenId[_tokenId].debtPrincipal -= _amount;

        emit DecreasedDebt(
            positionFromTokenId[_tokenId].user, _tokenId, oldDebt, debtPrincipal + accumulatedInterest - _amount
            );
    }

    //-------------------------------------------------------------------------------------------------------------------------------------------------------//
    // Values in ETH Functions
    //-------------------------------------------------------------------------------------------------------------------------------------------------------//

    /**
     * @notice Returns the value of a token in ETH.
     * @dev The value is calculated using the TWAP on the TOKEN/ETH's pool.
     * @param _tokenAddress The address of the token.
     * @return priceX96 The value of the token in ETH.
     */
    function priceInETH(address _tokenAddress) public view override returns (uint256 priceX96) {
        if (_tokenAddress == WETHAddress) return FixedPoint96.Q96;
        (int24 twappedTick,) =
            OracleLibrary.consult(tokenToWETHPoolInfo[_tokenAddress].poolAddress, protocolValues.twapLength);
        uint160 sqrtRatioX96 = TickMath.getSqrtRatioAtTick(twappedTick);
        priceX96 = FullMath.mulDiv(sqrtRatioX96, sqrtRatioX96, FixedPoint96.Q96);
        if (tokenToWETHPoolInfo[_tokenAddress].inv) {
            priceX96 = FullMath.mulDiv(FixedPoint96.Q96, FixedPoint96.Q96, priceX96);
        }
    }

    /**
     * @notice Returns the debt of a position in ETH.
     * @dev The debt is calculated using the price of the token in ETH.
     * @param _tokenId The ID of the position to get the debt of.
     * @return debtInETH The debt of the position in ETH.
     */
    function debtOfInETH(uint256 _tokenId) public view override returns (uint256) {
        return FullMath.mulDivRoundingUp(debtOf(_tokenId), priceInETH(address(GHO)), FixedPoint96.Q96);
    }

    /**
     * @notice Returns the value of a position in ETH.
     * @dev The value is calculated using the price of the tokens in ETH.
     * @param _tokenId The ID of the position to get the value of.
     * @return value The value of the position in ETH.
     */
    function positionValueInETH(uint256 _tokenId) public view override returns (uint256 value) {
        (uint256 amount0, uint256 amount1) = positionAmounts(_tokenId);
        address token0 = positionFromTokenId[_tokenId].token0;
        address token1 = positionFromTokenId[_tokenId].token1;
        return FullMath.mulDiv(amount0, priceInETH(token0), FixedPoint96.Q96)
            + FullMath.mulDiv(amount1, priceInETH(token1), FixedPoint96.Q96);
    }

    /**
     * @notice Returns the total value of all active positions of a user in ETH.
     * @dev The value is calculated using the price of the tokens in ETH.
     * @param _user The address of the user to get the total value of.
     * @return totalValue The total value of all active positions of the user in ETH.
     */
    function totalPositionsValueInETH(address _user) public view override returns (uint256 totalValue) {
        totalValue = 0;
        for (uint32 i = 0; i < positionsFromAddress[_user].length; i++) {
            if (positionsFromAddress[_user][i].status == Status.active) {
                totalValue += positionValueInETH(positionsFromAddress[_user][i].tokenId);
            }
        }
        return totalValue;
    }

    //-------------------------------------------------------------------------------------------------------------------------------------------------------//
    // Collateral Ratio functions
    //-------------------------------------------------------------------------------------------------------------------------------------------------------//

    /**
     * @notice Returns the collateral ratio of a position.
     * @param _tokenId The ID of the position to get the collateral ratio of.
     * @return collRatio The collateral ratio of the position.
     */
    function collRatioOf(uint256 _tokenId) public view returns (uint256) {
        /*(uint256 fee0, uint256 fee1) = activePool.feesOwed(
            INonfungiblePositionManager.CollectParams(_tokenId, address(this), type(uint128).max, type(uint128).max)
        );*/
        (,,,,,,,,,, uint128 fee0, uint128 fee1) = uniswapPositionsNFT.positions(_tokenId);
        uint256 fees = FullMath.mulDiv(fee0, priceInETH(positionFromTokenId[_tokenId].token0), FixedPoint96.Q96)
            + FullMath.mulDiv(fee1, priceInETH(positionFromTokenId[_tokenId].token1), FixedPoint96.Q96);
        uint256 debt = debtOfInETH(_tokenId);
        uint256 collValue = positionValueInETH(_tokenId) + fees;
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
    function updateRiskConstants(address _pool, uint256 _riskConstants) public {
        require(_riskConstants > FixedPoint96.Q96, "The minimum collateral ratio must be greater than 1.");
        riskConstantsFromPool[_pool].minCR = _riskConstants;
    }

    //-------------------------------------------------------------------------------------------------------------------------------------------------------//
    // Position Attributes Modifier Functions
    //-------------------------------------------------------------------------------------------------------------------------------------------------------//

    /**
     * @notice Sets the liquidity of a position.
     * @param _tokenId The ID of the position to set the liquidity of.
     * @param _liquidity The new liquidity of the position.
     */
    function setNewLiquidity(uint256 _tokenId, uint128 _liquidity)
        public
        onlyBorrowerOperations
        onlyActivePosition(_tokenId)
    {
        Position storage _position = positionFromTokenId[_tokenId];
        _position.liquidity = _liquidity;
    }

    //-------------------------------------------------------------------------------------------------------------------------------------------------------//
    // Liquidation functions
    //-------------------------------------------------------------------------------------------------------------------------------------------------------//

    /**
     * @notice Checks if a position is liquidatable.
     * @dev A position is liquidatable if its collateral ration is less than the minimum collateral ratio of the pool it is in.
     * @param _tokenId The ID of the position to check.
     * @return isLiquidatable, true if the position is liquidatable and false otherwise.
     */
    function liquidatable(uint256 _tokenId) public view returns (bool) {
        Position memory position = positionFromTokenId[_tokenId];
        return collRatioOf(_tokenId) < riskConstantsFromPool[position.poolAddress].minCR;
    }

    /**
     * @notice Liquidates a position.
     * @dev Given that the caller has enough GHO to reimburse the position's debt, the position is liquidated, the GHO is burned and the NFT is transfered to the caller.
     * @param _tokenId The ID of the position to liquidate.
     * @param _GHOToRepay The amount of GHO to repay to reimburse the debt of the position.
     * @return hasBeenLiquidated, true if the position has been liquidated and false otherwise.
     */
    function liquidatePosition(uint256 _tokenId, uint256 _GHOToRepay) public returns (bool) {
        require(liquidatable(_tokenId), "The position is not liquidatable.");
        uint256 debt = debtOf(_tokenId);
        require(_GHOToRepay >= debt, "The amount of GHO to repay is not enough to reimburse the debt of the position.");

        // Burn GHO
        GHO.transferFrom(msg.sender, address(this), debt);
        GHO.burn(debt);
        protocolValues.totalBorrowedGho -= positionFromTokenId[_tokenId].debtPrincipal;

        uniswapPositionsNFT.transferFrom(address(this), msg.sender, _tokenId);
        emit PositionSent(msg.sender, _tokenId);

        positionFromTokenId[_tokenId].status = Status.closedByLiquidation;
        return true;
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
        onlyBorrowerOperations
        returns (uint256 tokenId)
    {
        TransferHelper.safeApprove(params.token0, address(uniswapPositionsNFT), params.amount0Desired);
        TransferHelper.safeApprove(params.token1, address(uniswapPositionsNFT), params.amount1Desired);
        (tokenId,,,) = uniswapPositionsNFT.mint(params);

        emit PositionMinted(tokenId);
        return tokenId;
    }

    /**
     * @notice Burns an LP position.
     * @param tokenId The ID of the LP position to be burned.
     * @dev Only the Borrower Operations contract or the LP Positions Manager contract can call this function.
     */
    function burnPosition(uint256 tokenId) public override onlyBorrowerOperations {
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
    function increaseLiquidity(address sender, uint256 _tokenId, uint256 amountAdd0, uint256 amountAdd1)
        public
        override
        onlyBorrowerOperations
        returns (uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        address token0 = getPosition(_tokenId).token0;
        address token1 = getPosition(_tokenId).token1;

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

        Position storage _position = positionFromTokenId[_tokenId];
        _position.liquidity = liquidity;

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
    function decreaseLiquidity(uint256 _tokenId, uint128 _liquidityToRemove, address sender)
        public
        override
        returns (uint256 amount0, uint256 amount1)
    {
        _liquidityToRemove =
            _liquidityToRemove > getPosition(_tokenId).liquidity ? getPosition(_tokenId).liquidity : _liquidityToRemove;
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

        TransferHelper.safeTransfer(getPosition(_tokenId).token0, sender, amount0);
        TransferHelper.safeTransfer(getPosition(_tokenId).token1, sender, amount1);

        Position storage _position = positionFromTokenId[_tokenId];
        _position.liquidity = getPosition(_tokenId).liquidity - _liquidityToRemove;

        emit LiquidityDecreased(_tokenId, _liquidityToRemove);
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
    function sendPosition(address _account, uint256 _tokenId) public override onlyBorrowerOperations {
        //uniswapPositionsNFT.approve(to, tokenId);

        uniswapPositionsNFT.transferFrom(address(this), _account, _tokenId);
        emit PositionSent(_account, _tokenId);
    }

    //-------------------------------------------------------------------------------------------------------------------------------------------------------//
    // Modifiers and Require functions
    //-------------------------------------------------------------------------------------------------------------------------------------------------------//

    /**
     * @notice Checks if a position is active.
     * @param _tokenId The ID of the position to check.
     */
    modifier onlyActivePosition(uint256 _tokenId) {
        require(positionFromTokenId[_tokenId].status == Status.active, "Position does not exist or is closed");
        _;
    }

    /**
     * @notice Checks if the caller is the borrower operations contract.
     * @dev This modifier is used to restrict access to the borrower operations contract.
     */
    modifier onlyBorrowerOperations() {
        require(msg.sender == address(borrowerOperations), "This operation is restricted");
        _;
    }

    // base is a fixedpoint96 number, exponent is a regular unsigned integer
    function lessDumbPower(uint256 _base, uint256 _exponent) public pure returns (uint256 result) {
        // do fast exponentiation by checking parity of exponent
        if (_exponent == 0) {
            result = FixedPoint96.Q96;
        } else if (_exponent == 1) {
            result = _base;
        } else {
            result = lessDumbPower(_base, _exponent / 2);
            // calculate the square of the square root with FullMath.mulDiv
            result = FullMath.mulDiv(result, result, FixedPoint96.Q96);
            if (_exponent % 2 == 1) {
                // calculate the square of the square root with FullMath.mulDiv and multiply by base once
                result = FullMath.mulDiv(result, _base, FixedPoint96.Q96);
            }
        }
    }
}
