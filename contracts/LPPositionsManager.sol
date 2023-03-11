// SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

import "./interfaces/IActivePool.sol";
import "./interfaces/ILPPositionsManager.sol";
import "./interfaces/IStableCoin.sol";

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

import "forge-std/console.sol";
import "forge-std/Test.sol";

import "gho-core/src/contracts/gho/GHOToken.sol";

/**
 * @title LPPositionsManager contract
 * @notice Contains the logic for position operations performed by users.
 * @dev The contract is owned by the Eclypse system, and is called by the BorrowerOperations and ActivePool contracts.
 */

contract LPPositionsManager is ILPPositionsManager, Ownable, Test {
    // -- Integer Constants --

    uint256 constant MAX_UINT256 = 2 ** 256 - 1;

    ProtocolValues public protocolValues;
    ProtocolContracts public protocolContracts;

    address constant WETHAddress = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    mapping(address => bool) private whiteListedPools;
    mapping(address => PoolPricingInfo) private tokenToWETHPoolInfo;
    mapping(address => RiskConstants) private riskConstantsFromPool;

    mapping(address => Position[]) private positionsFromAddress;
    mapping(uint256 => Position) private positionFromTokenId;
    Position[] private allPositions;

    // -- Methods --

    //-------------------------------------------------------------------------------------------------------------------------------------------------------//
    // Constructors
    //-------------------------------------------------------------------------------------------------------------------------------------------------------//

    /**
     * @notice Set the addresses of various contracts and emit events to indicate that these addresses have been modified.
     * @param _uniFactory The address of the Uniswap V3 factory contract.
     * @param _uniPosNFT The address of the Uniswap V3 positions NFT contract.
     * @param _StableCoinAddr The address of the StableCoin token contract.
     * @param _borrowerOpAddr The address of the borrower operations contract.
     * @param _activePoolAddr The address of the active pool contract.
     * @dev This function can only be called by the contract owner.
     */
    function setAddresses(
        address _uniFactory,
        address _uniPosNFT,
        address _StableCoinAddr,
        address _borrowerOpAddr,
        address _activePoolAddr
    ) external override onlyOwner {
        protocolContracts.borrowerOperationsAddr = _borrowerOpAddr;
        protocolContracts.activePool = IActivePool(_activePoolAddr);
        protocolContracts.stableCoin = IStableCoin(_StableCoinAddr);
        protocolContracts.uniswapFactory = IUniswapV3Factory(_uniFactory);
        protocolContracts.uniswapPositionsManager = INonfungiblePositionManager(_uniPosNFT);

        emit BorrowerOperationsAddressChanged(_borrowerOpAddr);
        emit ActivePoolAddressChanged(_activePoolAddr);
        emit StableCoinAddressChanged(_StableCoinAddr);

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
    function addPoolToProtocol(
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

    //-------------------------------------------------------------------------------------------------------------------------------------------------------//
    // Position Functions
    //-------------------------------------------------------------------------------------------------------------------------------------------------------//

    /**
     * @notice Opens a new position for the given token ID and owner.
     * @dev The position is added to the array of positions owned by the owner, and the position is added to the array of all positions.
     * @param _owner The address of the position owner.
     * @param _tokenId The ID of the Uniswap NFT representing the position.
     */
    function openPosition(address _owner, uint256 _tokenId) public override onlyBorrowerOperations {
        protocolContracts.uniswapPositionsManager.safeTransferFrom(
            _owner, address(protocolContracts.activePool), _tokenId
        );

        (,, address token0, address token1, uint24 fee, int24 tickLower, int24 tickUpper, uint128 liquidity,,,,) =
            protocolContracts.uniswapPositionsManager.positions(_tokenId);

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
            protocolValues.interestFactor
        );

        allPositions.push(position);
        positionsFromAddress[_owner].push(position);
        positionFromTokenId[_tokenId] = position;
    }

    /**
     * @notice Closes a position.
     * @param _owner The owner of the position.
     * @param _tokenId The ID of the Uniswap V3 NFT representing the position.
     * @dev The caller must have approved the transfer of the Uniswap V3 NFT from the BorrowerOperations contract to their wallet.
     */
    function closePosition(address _owner, uint256 _tokenId)
        public
        override
        onlyActivePosition(_tokenId)
        onlyBorrowerOperations
    {
        require(positionFromTokenId[_tokenId].user == _owner, "The position does not belong to the owner.");

        protocolContracts.activePool.sendPosition(_owner, _tokenId);

        uint256 debt = debtOf(_tokenId);
        if (debt > 0) {
            repay(_owner, _tokenId, debt);
        }
        positionFromTokenId[_tokenId].status = Status.closedByOwner;
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
    // Debt tracking Functions
    //-------------------------------------------------------------------------------------------------------------------------------------------------------//

    function refreshDebtTracking() public {
        uint256 newInterestFactor =
            power(protocolValues.interestRate, block.timestamp - protocolValues.lastFactorUpdate);
        protocolValues.interestFactor =
            FullMath.mulDivRoundingUp(protocolValues.interestFactor, newInterestFactor, FixedPoint96.Q96);
        protocolValues.lastFactorUpdate = block.timestamp;
    }

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
            power(protocolValues.interestRate, block.timestamp - protocolValues.lastFactorUpdate);
        currentDebt = FullMath.mulDivRoundingUp(currentDebt, newInterestFactor, FixedPoint96.Q96);
    }

    function allDebtComponentsOf(uint256 _tokenId)
        public
        view
        returns (uint256 currentDebt, uint256 debtPrincipal, uint256 interest)
    {
        debtPrincipal = getPosition(_tokenId).debtPrincipal;
        currentDebt = FullMath.mulDivRoundingUp(
            debtPrincipal, protocolValues.interestFactor, getPosition(_tokenId).interestConstant
        );
        uint256 newInterestFactor =
            power(protocolValues.interestRate, block.timestamp - protocolValues.lastFactorUpdate);
        currentDebt = FullMath.mulDivRoundingUp(currentDebt, newInterestFactor, FixedPoint96.Q96);
        interest = currentDebt - debtPrincipal;
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
     * @param sender The address of the user that is increasing its debt.
     * @param _tokenId The ID of the position to increase the debt of.
     * @param _amount The amount to increase the debt of the position by.
     */
    function borrow(address sender, uint256 _tokenId, uint256 _amount)
        public
        override
        onlyBorrowerOperations
        onlyActivePosition(_tokenId)
    {
        require(_amount > 0, "A debt cannot be increased by 0.");

        refreshDebtTracking();
        // From here, the interestFactor is up-to-date.
        (uint256 totalDebt, uint256 debtPrincipal,) = allDebtComponentsOf(_tokenId);

        protocolContracts.activePool.mint(sender, _amount, address(protocolContracts.stableCoin));
        protocolValues.totalBorrowedStableCoin += _amount;

        positionFromTokenId[_tokenId].interestConstant =
            FullMath.mulDiv(protocolValues.interestFactor, debtPrincipal + _amount, totalDebt + _amount);
        positionFromTokenId[_tokenId].debtPrincipal += _amount;

        if (liquidatable(_tokenId)) {
            revert("The position can't be liquidatable!");
        }

        emit IncreasedDebt(positionFromTokenId[_tokenId].user, _tokenId, totalDebt, totalDebt + _amount);
    }

    /**
     * @notice Decreases the debt of a position by a given amount.
     * @dev The debt is decreased by the given amount, and the last update timestamp is set to the current block timestamp.
     * @param _tokenId The ID of the position to decrease the debt of.
     * @param _amount The amount to decrease the debt of the position by.
     */
    function repay(address sender, uint256 _tokenId, uint256 _amount)
        public
        override
        onlyBorrowerOperations
        onlyActivePosition(_tokenId)
    {
        require(_amount > 0, "A debt cannot be decreased by 0.");

        refreshDebtTracking();
        // From here, the interestFactor is up-to-date.
        (uint256 currentDebt, uint256 debtPrincipal, uint256 accumulatedInterest) = allDebtComponentsOf(_tokenId);

        _amount = Math.min(_amount, currentDebt);

        uint256 interestRepayment = Math.min(_amount, accumulatedInterest);
        uint256 principalRepayment = _amount - interestRepayment;

        IERC20(address(protocolContracts.stableCoin)).transferFrom(
            sender, address(protocolContracts.activePool), principalRepayment + interestRepayment
        );
        if (principalRepayment > 0) {
            protocolContracts.activePool.burn(principalRepayment, address(protocolContracts.stableCoin));
            protocolValues.totalBorrowedStableCoin -= principalRepayment;
        }

        uint256 newDebt = currentDebt - _amount;
        uint256 newDebtPrincipal = debtPrincipal - principalRepayment;
        console.log("newDebtPrincipal", newDebtPrincipal);
        console.log("newDebt", newDebt);
        if (newDebt > 0) {
            positionFromTokenId[_tokenId].interestConstant =
                FullMath.mulDivRoundingUp(protocolValues.interestFactor, newDebtPrincipal, newDebt);
        } else {
            positionFromTokenId[_tokenId].interestConstant = protocolValues.interestFactor;
        }
        positionFromTokenId[_tokenId].debtPrincipal = newDebtPrincipal;

        emit DecreasedDebt(positionFromTokenId[_tokenId].user, _tokenId, currentDebt, newDebt);
    }

    //-------------------------------------------------------------------------------------------------------------------------------------------------------//
    // Values in ETH Functions
    //-------------------------------------------------------------------------------------------------------------------------------------------------------//

    /**
     * @notice Returns the value of a token in ETH.
     * @dev The value is calculated using the TWAP on the TOKEN/ETH's pool.
     * @param _tokenAddress The address of the token.
     * @return valueInETH The value of the token in ETH.
     */
    function priceInETH(address _tokenAddress) public view override returns (uint256) {
        if (_tokenAddress == WETHAddress) return FixedPoint96.Q96;
        (int24 twappedTick,) =
            OracleLibrary.consult(tokenToWETHPoolInfo[_tokenAddress].poolAddress, protocolValues.twapLength);
        uint160 sqrtRatioX96 = TickMath.getSqrtRatioAtTick(twappedTick);
        uint256 ratio = FullMath.mulDiv(sqrtRatioX96, sqrtRatioX96, FixedPoint96.Q96);
        if (tokenToWETHPoolInfo[_tokenAddress].inv) return FullMath.mulDiv(FixedPoint96.Q96, FixedPoint96.Q96, ratio);
        // need to confirm if this is mathematically correct!
        else return ratio;
    }

    /**
     * @notice Returns the debt of a position in ETH.
     * @dev The debt is calculated using the price of the token in ETH.
     * @param _tokenId The ID of the position to get the debt of.
     * @return debtInETH The debt of the position in ETH.
     */
    function debtOfInETH(uint256 _tokenId) public view override returns (uint256) {
        return FullMath.mulDivRoundingUp(
            debtOf(_tokenId), priceInETH(address(protocolContracts.stableCoin)), FixedPoint96.Q96
        );
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
    // Positions interaction
    //-------------------------------------------------------------------------------------------------------------------------------------------------------//

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
    function increaseLiquidity(address sender, uint256 tokenId, uint256 amountAdd0, uint256 amountAdd1)
        public
        override
        onlyBorrowerOperations
        returns (uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        Position memory position = getPosition(tokenId);
        address token0 = position.token0;
        address token1 = position.token1;

        (liquidity,,) = protocolContracts.activePool.increaseLiquidity(sender, tokenId, token0, token1, amountAdd0, amountAdd1);

        Position storage _position = positionFromTokenId[tokenId];
        _position.liquidity = liquidity;

        emit LiquidityIncreased(tokenId, liquidity);
    }

    /**
     * @notice Decreases the liquidity of an LP position.
     * @param tokenId The ID of the LP position to be decreased.
     * @param liquidityToRemove The amount of liquidity to be removed from the LP position.
     * @return amount0 The amount of token0 removed from the LP position.
     * @return amount1 The amount of token1 removed from the LP position.
     * @dev Only the Borrower Operations contract can call this function.
     */
    function decreaseLiquidity(address sender, uint256 tokenId, uint128 liquidityToRemove)
        public
        override
        returns (uint256 amount0, uint256 amount1)
    {
        liquidityToRemove =
            liquidityToRemove > getPosition(tokenId).liquidity ? getPosition(tokenId).liquidity : liquidityToRemove;
        // amount0Min and amount1Min are price slippage checks

        protocolContracts.activePool.decreaseLiquidity(sender, tokenId, liquidityToRemove);

        Position storage _position = positionFromTokenId[tokenId];
        _position.liquidity = getPosition(tokenId).liquidity - liquidityToRemove;

        emit LiquidityDecreased(tokenId, liquidityToRemove);
    }

    //-------------------------------------------------------------------------------------------------------------------------------------------------------//
    // Collateral Ratio functions
    //-------------------------------------------------------------------------------------------------------------------------------------------------------//

    /**
     * @notice Returns the collateral ratio of a position.
     * @param _tokenId The ID of the position to get the collateral ratio of.
     * @return collRatio The collateral ratio of the position.
     */
    function collRatioOf(uint256 _tokenId) public view returns (uint256 collRatio) {
        /*(uint256 fee0, uint256 fee1) = activePool.feesOwed(
            INonfungiblePositionManager.CollectParams(_tokenId, address(this), type(uint128).max, type(uint128).max)
        );*/
        (,,,,,,,,,, uint128 fee0, uint128 fee1) = protocolContracts.uniswapPositionsManager.positions(_tokenId);
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
    function setNewLiquidity(uint256 _tokenId, uint128 _liquidity) public onlyBOorAP onlyActivePosition(_tokenId) {
        Position storage _position = positionFromTokenId[_tokenId];
        _position.liquidity = _liquidity;
    }

    // /**
    //  * @notice Changes the ticks of a position.
    //  * @dev The new ticks must be smaller than the maximum tick and greater than the minimum tick.
    //  * @param _tokenId The ID of the position to change the ticks of.
    //  * @param _newMinTick The new minimum tick of the position.
    //  * @param _newMaxTick The new maximum tick of the position.
    //  */
    // function _changeTicks(
    //     uint256 _tokenId,
    //     int24 _newMinTick,
    //     int24 _newMaxTick
    // )
    //     public
    //     onlyBorrowerOperations
    //     onlyActivePosition(_tokenId)
    //     returns (uint256 _newTokenId)
    // {
    //     require(
    //         _newMinTick < _newMaxTick,
    //         "The new min tick must be smaller than the new max tick."
    //     );
    //     require(
    //         _newMinTick >= -887272,
    //         "The new min tick must be greater than -887272."
    //     );
    //     require(
    //         _newMaxTick <= 887272,
    //         "The new max tick must be smaller than 887272."
    //     );

    //     Position memory _position = positionFromTokenId[_tokenId];

    //     (uint256 _amount0, uint256 _amount1) = activePool.decreaseLiquidity(
    //         _tokenId,
    //         _position.liquidity,
    //         address(activePool)
    //                 );

    //     INonfungiblePositionManager.MintParams memory mintParams = INonfungiblePositionManager
    //         .MintParams({
    //             token0: _position.token0,
    //             token1: _position.token1,
    //             fee: _position.fee,
    //             tickLower: _newMinTick,
    //             tickUpper: _newMaxTick,
    //             amount0Desired: _amount0,
    //             amount1Desired: _amount1,
    //             amount0Min: 0, //TODO: Change that cause it represents a vulnerability
    //             amount1Min: 0, //TODO: Change that cause it represents a vulnerability
    //             recipient: address(activePool),
    //             deadline: block.timestamp
    //         });

    //     _newTokenId = activePool.mintPosition(mintParams);

    //     setNewPosition(
    //         address(activePool),
    //         _position.poolAddress,
    //         _newTokenId,
    //         Status.active,
    //         _position.debt,
    //         _position.lastUpdateTimestamp
    //     );

    //     activePool.burnPosition(_tokenId);
    //     changePositionStatus(_tokenId, Status.closedByOwner);

    //     return _newTokenId;
    // }

    /**
     * @notice Add a new position to the list of positions.
     * @param _owner The owner of the position.
     * @param _poolAddress The address of the pool of the position.
     * @param _newTokenId The ID of the position.
     * @param _status The status of the position.
     * @param _debt The debt of the position.
     * @param _lastUpdate The last update of the position.
     * @return position The position.
     */
    // function setNewPosition(
    //     address _owner,
    //     address _poolAddress,
    //     uint256 _newTokenId,
    //     Status _status,
    //     uint256 _debt,
    //     uint256 _lastUpdate
    // ) public returns (Position memory position) {
    //     (
    //         ,
    //         ,
    //         address _token0,
    //         address _token1,
    //         uint24 _fee,
    //         int24 _tickLower,
    //         int24 _tickUpper,
    //         uint128 _liquidity,
    //         ,
    //         ,
    //         ,

    //     ) = uniswapPositionsNFT.positions(_newTokenId);

    //     position = Position({
    //         user: _owner,
    //         token0: _token0,
    //         token1: _token1,
    //         fee: _fee,
    //         tickLower: _tickLower,
    //         tickUpper: _tickUpper,
    //         liquidity: _liquidity,
    //         poolAddress: _poolAddress,
    //         tokenId: _newTokenId,
    //         status: _status,
    //         debt: _debt,
    //         lastUpdateTimestamp: _lastUpdate
    //     });

    //     allPositions.push(position);
    //     positionsFromAddress[_owner].push(position);
    //     positionFromTokenId[_newTokenId] = position;
    // }

    //-------------------------------------------------------------------------------------------------------------------------------------------------------//
    // Liquidation functions
    //-------------------------------------------------------------------------------------------------------------------------------------------------------//

    /**
     * @notice Checks if a position is liquidatable.
     * @dev A position is liquidatable if its collateral ration is less than the minimum collateral ratio of the pool it is in.
     * @param _tokenId The ID of the position to check.
     * @return isLiquidatable, true if the position is liquidatable and false otherwise.
     */
    function liquidatable(uint256 _tokenId) public override view returns (bool) {
        Position memory position = positionFromTokenId[_tokenId];
        console.log("collRatioOf(_tokenId): ", collRatioOf(_tokenId));
        console.log("riskConstantsFromPool[position.poolAddress].minCR: ", riskConstantsFromPool[position.poolAddress].minCR);
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
        protocolContracts.stableCoin.transferFrom(msg.sender, address(protocolContracts.activePool), debt);
        protocolContracts.activePool.burn(debt, address(protocolContracts.stableCoin));
        protocolValues.totalBorrowedStableCoin -= positionFromTokenId[_tokenId].debtPrincipal;

        protocolContracts.uniswapPositionsManager.transferFrom(address(this), msg.sender, _tokenId);

        positionFromTokenId[_tokenId].status = Status.closedByLiquidation;
        return true;
    }

    /**
     * @notice Liquidates a position and its underlyings.
     * @dev Given that the caller has enough GHO to reimburse the position's debt, the position is liquidated, the GHO is burned and the NFT is transfered to the caller.
     * @param _tokenId The ID of the position to liquidate.
     * @param _GHOToRepay The amount of GHO to repay to reimburse the debt of the position.
     * @return hasBeenLiquidated true if the position has been liquidated and false otherwise.
     */
    function liquidateUnderlyings(uint256 _tokenId, uint256 _GHOToRepay)
        public
        override
        returns (bool hasBeenLiquidated)
    {
        require(liquidatable(_tokenId), "Position is not liquidatable");
        require(debtOf(_tokenId) <= _GHOToRepay, "Not enough GHO to repay debt");

        uint256 repayAmount = _GHOToRepay;
        uint256 GHOfees = 0;
    }

    /**
     * @notice Liquidates multiple positions.
     * @dev Given that the callers have enough GHO to reimburse the positions' debt, the positions are liquidated, the GHO is burned and the NFTs are transfered to the callers.
     * @param _tokenIds The IDs of the positions to liquidate.
     * @param _GHOToRepays The amounts of GHO to repay to reimburse the debt of the positions.
     */
    function batchliquidate(uint256[] memory _tokenIds, uint256[] memory _GHOToRepays) public override {
        require(_tokenIds.length == _GHOToRepays.length);
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            liquidatePosition(_tokenIds[i], _GHOToRepays[i]);
        }
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
        require(msg.sender == protocolContracts.borrowerOperationsAddr, "This operation is restricted");
        _;
    }

    modifier onlyBOorAP() {
        require(
            msg.sender == protocolContracts.borrowerOperationsAddr
                || msg.sender == address(protocolContracts.activePool),
            "This operation is restricted"
        );
        _;
    }

    // base is a fixedpoint96 number, exponent is a regular unsigned integer
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

    function getProtocolValues() external view returns (ProtocolValues memory) {
        return protocolValues;
    }
    function setProtocolValues(ProtocolValues memory _protocolValues) external {
        protocolValues = _protocolValues;
    }
}
