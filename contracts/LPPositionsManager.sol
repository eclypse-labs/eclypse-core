// SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

import "./interfaces/IActivePool.sol";
import "./interfaces/ILPPositionsManager.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap-core/libraries/TickMath.sol";
import "@uniswap-core/libraries/FullMath.sol";
import "@uniswap-core/libraries/FixedPoint96.sol";
import "@uniswap-periphery/interfaces/INonfungiblePositionManager.sol";
import "@uniswap-periphery/libraries/LiquidityAmounts.sol";
import "@uniswap-periphery/libraries/PoolAddress.sol";
import "@uniswap-periphery/libraries/OracleLibrary.sol";
import "forge-std/console.sol";
import "@uniswap-core/interfaces/IUniswapV3Factory.sol";
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
    uint32 constant lookBackTWAP = 60; // Number of seconds to calculate the TWAP
    uint256 constant interestRate = 79228162564014647528974148095; // 2% APY interest rate : fixedpoint96 value found by evaluating "1.02^(1/(31536000))*2^96" on https://www.mathsisfun.com/calculator-precision.html (31556952 is the number of seconds in a year)

    // -- Addresses --

    address constant WETHAddress = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant factoryAddress =
        0x1F98431c8aD98523631AE4a59f267346ea31F984;

    address borrowerOperationsAddress;

    GhoToken public GHOToken = new GhoToken();
    // -- Interfaces --

    INonfungiblePositionManager constant uniswapPositionsNFT =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

    IUniswapV3Factory internal uniswapFactory =
        IUniswapV3Factory(factoryAddress);

    IActivePool public activePool;

    //GHOToken public GHO = new GHOToken();

    //TODO: Comment next line
    //IGHOToken public GHOToken;


    // -- Mappings & Arrays --

    // Is this pool accepted by the protocol?
    mapping(address => bool) private _acceptedPoolAddresses;

    // Retrieves a pool's data given the pool's address.
    mapping(address => RiskConstants) private _poolAddressToRiskConstants;

    // Retrieves every positions a user has, under the form of an array, given the user's address.
    mapping(address => Position[]) private _positionsFromAddress;

    // Retrieves a position given its tokenId.
    mapping(uint256 => Position) private _positionFromTokenId;

    // Retrieves the address of the pool associated with the pair (token/ETH) where given the token's address.
    mapping(address => PoolPricingInfo) private _tokenToWETHPoolInfo;

    // An array of all positions.
    Position[] private _allPositions;

    //TODO: Comment next line.
    //mapping(uint256 => BorrowData[]) private _borrowDataFromTokenId;

    // -- Methods --

    //-------------------------------------------------------------------------------------------------------------------------------------------------------//
    // Constructors
    //-------------------------------------------------------------------------------------------------------------------------------------------------------//

    /**
     * @notice Set the addresses of various contracts and emit events to indicate that these addresses have been modified.
     * @param _borrowerOperationsAddress The address of the borrower operations contract.
     * @param _activePoolAddress The address of the active pool contract.
     * @dev This function can only be called by the contract owner.
     */
    function setAddresses(
        address _borrowerOperationsAddress,
        address _activePoolAddress

        //TODO: Comment next line
        //address _GHOTokenAddress
    ) external override onlyOwner {
        borrowerOperationsAddress = _borrowerOperationsAddress;
        activePool = IActivePool(_activePoolAddress);


        //TODO: Comment next line
        //GHOToken = IGHOToken(_GHOTokenAddress);

        emit BorrowerOperationsAddressChanged(_borrowerOperationsAddress);
        emit ActivePoolAddressChanged(_activePoolAddress);

        //TODO: Comment next line
        //emit GHOTokenAddressChanged(_GHOTokenAddress);

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
        _acceptedPoolAddresses[_poolAddress] = true;
        _tokenToWETHPoolInfo[_token0] = PoolPricingInfo(_ETHpoolToken0, _inv0);
        _tokenToWETHPoolInfo[_token1] = PoolPricingInfo(_ETHpoolToken1, _inv1);
        emit TokenAddedToPool(_token0, _ETHpoolToken0);
        emit TokenAddedToPool(_token1, _ETHpoolToken1);
    }

    //-------------------------------------------------------------------------------------------------------------------------------------------------------//
    // Getters for positions
    //-------------------------------------------------------------------------------------------------------------------------------------------------------//

    /**
     * @notice Retrieves the position of a given token
     * @param _tokenId The token to retrieve the position for
     * @return position The position of the given token
     */
    function getPosition(
        uint256 _tokenId
    ) public view returns (Position memory position) {
        return _positionFromTokenId[_tokenId];
    }

    /**
     * @notice Returns the total number of positions owned by all users.
     * @return totalCount The number of positions owned by all users.
     */
    function getPositionsCount() external view returns (uint256) {
        return _allPositions.length;
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
    function changePositionStatus(
        uint256 _tokenId,
        Status _status
    ) public onlyBorrowerOperations {
        require(
            _positionFromTokenId[_tokenId].status != _status,
            "A position status cannot be changed to its current one."
        );
        _positionFromTokenId[_tokenId].status = _status;
        emit PositionStatusChanged(_tokenId, _status);
    }

    /**
     * @notice Opens a new position for the given token ID and owner.
     * @dev The position is added to the array of positions owned by the owner, and the position is added to the array of all positions.
     * @param _owner The address of the position owner.
     * @param _tokenId The ID of the Uniswap NFT representing the position.
     */
    function openPosition(
        address _owner,
        uint256 _tokenId
    ) public override onlyBorrowerOperations {
        (
            ,
            ,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            ,
            ,
            ,

        ) = uniswapPositionsNFT.positions(_tokenId);

        address poolAddress = uniswapFactory.getPool(token0, token1, fee);
        require(
            _acceptedPoolAddresses[poolAddress],
            "This pool is not accepted by the protocol."
        );

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
            block.timestamp
        );

        _allPositions.push(position);
        _positionsFromAddress[_owner].push(position);
        _positionFromTokenId[_tokenId] = position;

        //TODO: create new debt token in activePool

        activePool.newDebtToken(_owner, interestRate, _tokenId);

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
    function positionAmounts(
        uint256 _tokenId
    )
        public
        view
        override
        returns (uint256 amountToken0, uint256 amountToken1)
    {
        Position memory _position = _positionFromTokenId[_tokenId];
        (int24 twappedTick, ) = OracleLibrary.consult(
            _position.poolAddress,
            lookBackTWAP
        );

        uint160 sqrtRatioX96 = TickMath.getSqrtRatioAtTick(twappedTick);
        uint160 sqrtRatio0X96 = TickMath.getSqrtRatioAtTick(
            _position.tickLower
        );
        uint160 sqrtRatio1X96 = TickMath.getSqrtRatioAtTick(
            _position.tickUpper
        );
        (uint256 amount0, uint256 amount1) = LiquidityAmounts
            .getAmountsForLiquidity(
                sqrtRatioX96,
                sqrtRatio0X96,
                sqrtRatio1X96,
                _position.liquidity
            );

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

    //TODO: replace this function by call to activePool.debtToken().balance

    function debtOf(uint256 _tokenId) public override view returns (uint256 currentDebt) {
        return activePool.getDebtToken(_tokenId).totalBalanceOf();
    }


    /**
     * @notice Returns the total debt of a user, including interest.
     * @dev The debt is calculated using the interest rate and the last update timestamp of the position.
     * @param _user The address of the user to get the debt of.
     * @return totalDebtInGHO The total debt of the user, including interest.
     */
    function totalDebtOf(
        address _user
    ) public view returns (uint256 totalDebtInGHO) {
        for (uint32 i = 0; i < _positionsFromAddress[_user].length; i++) {
            if (_positionsFromAddress[_user][i].status == Status.active) {
                totalDebtInGHO += debtOf(
                    _positionsFromAddress[_user][i].tokenId
                );
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
    // function increaseDebtOf(
    //     uint256 _tokenId,
    //     uint256 _amount
    // ) public override onlyBorrowerOperations onlyActivePosition(_tokenId) {
    //     require(
    //         _amount > 0,
    //         "A debt cannot be increased by a negative amount or by 0."
    //     );

    //     uint256 prevDebt = debtOf(_tokenId);

    //     _positionFromTokenId[_tokenId].debt = prevDebt + _amount;
    //     _positionFromTokenId[_tokenId].lastUpdateTimestamp = block.timestamp;

    //     _borrowDataFromTokenId[_tokenId].push(
    //         BorrowData(0, _amount, block.timestamp, interestRate)
    //     );

    //     activePool.increaseMintedSupply(
    //         _amount,
    //         _positionFromTokenId[_tokenId].user,
    //         _tokenId
    //     );

    //     emit IncreasedDebt(
    //         _positionFromTokenId[_tokenId].user,
    //         _tokenId,
    //         _positionFromTokenId[_tokenId].debt - _amount,
    //         _positionFromTokenId[_tokenId].debt
    //     );
    // }

    /**
     * @notice Decreases the debt of a position by a given amount.
     * @dev The debt is decreased by the given amount, and the last update timestamp is set to the current block timestamp.
     * @param _tokenId The ID of the position to decrease the debt of.
     * @param _amount The amount to decrease the debt of the position by.
     */
    // function decreaseDebtOf(
    //     uint256 _tokenId,
    //     uint256 _amount
    // )
    //     public
    //     override
    //     onlyBorrowerOperations
    //     onlyActivePosition(_tokenId)
    //     returns (uint256 GHOfees)
    // {
    //     require(
    //         _amount > 0,
    //         "A debt cannot be decreased by a negative amount or by 0."
    //     );
    //     uint256 prevDebt = debtOf(_tokenId);
    //     uint256 repayAmount = _amount;
    //     BorrowData[] memory _borrowDataArray = _borrowDataFromTokenId[_tokenId];
    //     for (uint32 i = 0; i < _borrowDataArray.length; i++) {
    //         if (repayAmount == 0) {
    //             break;
    //         } else if (repayAmount > _debtOf(_borrowDataArray[i])) {
    //             repayAmount -= _debtOf(_borrowDataArray[i]);
    //             GHOfees += _debtOf(_borrowDataArray[i]);
    //             if (repayAmount >= _borrowDataArray[i].mintedAmount) {
    //                 repayAmount -= _borrowDataArray[i].mintedAmount;
    //                 activePool.decreaseMintedSupply(
    //                     _borrowDataArray[i].mintedAmount,
    //                     _positionFromTokenId[_tokenId].user
    //                 );
    //                 delete _borrowDataFromTokenId[_tokenId][i];
    //             } else {
    //                 _borrowDataFromTokenId[_tokenId][i].amount = 0;
    //                 _borrowDataFromTokenId[_tokenId][i]
    //                     .mintedAmount -= repayAmount;
    //                 activePool.decreaseMintedSupply(
    //                     repayAmount,
    //                     _positionFromTokenId[_tokenId].user
    //                 );
    //                 repayAmount = 0;
    //             }
    //         } else {
    //             _borrowDataFromTokenId[_tokenId][i].amount -= repayAmount;
    //             GHOfees += repayAmount;
    //             repayAmount = 0;
    //         }
    //     }

    //     _positionFromTokenId[_tokenId].debt = Math.max(prevDebt - _amount, 0);
    //     _positionFromTokenId[_tokenId].lastUpdateTimestamp = block.timestamp;

    //     emit DecreasedDebt(
    //         _positionFromTokenId[_tokenId].user,
    //         _tokenId,
    //         _positionFromTokenId[_tokenId].debt + _amount,
    //         _positionFromTokenId[_tokenId].debt
    //     );

    //     return GHOfees;
    // }

    //-------------------------------------------------------------------------------------------------------------------------------------------------------//
    // Values in ETH Functions
    //-------------------------------------------------------------------------------------------------------------------------------------------------------//

    /**
     * @notice Returns the value of a token in ETH.
     * @dev The value is calculated using the TWAP on the TOKEN/ETH's pool.
     * @param _tokenAddress The address of the token.
     * @return valueInETH The value of the token in ETH.
     */
    function priceInETH(
        address _tokenAddress
    ) public view override returns (uint256) {
        if (_tokenAddress == WETHAddress) return FixedPoint96.Q96;
        (int24 twappedTick, ) = OracleLibrary.consult(
            _tokenToWETHPoolInfo[_tokenAddress].poolAddress,
            lookBackTWAP
        );
        uint160 sqrtRatioX96 = TickMath.getSqrtRatioAtTick(twappedTick);
        uint256 ratio = FullMath.mulDiv(
            sqrtRatioX96,
            sqrtRatioX96,
            FixedPoint96.Q96
        );
        if (_tokenToWETHPoolInfo[_tokenAddress].inv)
            return FullMath.mulDiv(FixedPoint96.Q96, FixedPoint96.Q96, ratio);
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
        return
            FullMath.mulDivRoundingUp(
                debtOf(_tokenId),
                priceInETH(address(GHOToken)),
                FixedPoint96.Q96
            );
    }

    /**
     * @notice Returns the value of a position in ETH.
     * @dev The value is calculated using the price of the tokens in ETH.
     * @param _tokenId The ID of the position to get the value of.
     * @return value The value of the position in ETH.
     */
    function positionValueInETH(
        uint256 _tokenId
    ) public view override returns (uint256 value) {
        (uint256 amount0, uint256 amount1) = positionAmounts(_tokenId);
        address token0 = _positionFromTokenId[_tokenId].token0;
        address token1 = _positionFromTokenId[_tokenId].token1;
        return
            FullMath.mulDiv(amount0, priceInETH(token0), FixedPoint96.Q96) +
            FullMath.mulDiv(amount1, priceInETH(token1), FixedPoint96.Q96);
    }

    /**
     * @notice Returns the total value of all active positions of a user in ETH.
     * @dev The value is calculated using the price of the tokens in ETH.
     * @param _user The address of the user to get the total value of.
     * @return totalValue The total value of all active positions of the user in ETH.
     */
    function totalPositionsValueInETH(
        address _user
    ) public view override returns (uint256 totalValue) {
        totalValue = 0;
        for (uint32 i = 0; i < _positionsFromAddress[_user].length; i++) {
            if (_positionsFromAddress[_user][i].status == Status.active) {
                totalValue += positionValueInETH(
                    _positionsFromAddress[_user][i].tokenId
                );
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
    function computeCR(uint256 _tokenId) public returns (uint256) {
        (uint256 fee0, uint256 fee1) = activePool.feesOwed(
            INonfungiblePositionManager.CollectParams(
                _tokenId,
                address(this),
                type(uint128).max,
                type(uint128).max
            )
        );
        uint256 fees = FullMath.mulDiv(
            fee0,
            priceInETH(_positionFromTokenId[_tokenId].token0),
            FixedPoint96.Q96
        ) +
            FullMath.mulDiv(
                fee1,
                priceInETH(_positionFromTokenId[_tokenId].token1),
                FixedPoint96.Q96
            );
        uint256 debt = debtOfInETH(_tokenId);
        uint256 collValue = positionValueInETH(_tokenId) + fees;
        return
            debt > 0
                ? FullMath.mulDiv(collValue, FixedPoint96.Q96, debt)
                : MAX_UINT256;
    }

    /**
     * @notice Returns the risk constants of a pool.
     * @dev The risk constants are the minimum collateral ratio of the pool.
     * @param _pool The address of the pool to get the risk constants of.
     * @return riskConstants The risk constants ratio of the pool.
     */
    function getRiskConstants(
        address _pool
    ) public view returns (uint256 riskConstants) {
        return _poolAddressToRiskConstants[_pool].minCR;
    }

    /**
     * @notice Updates the risk constants of a pool.
     * @dev The risk constants are the minimum collateral ratio of the pool.
     * @param _pool The address of the pool to update the risk constants of.
     * @param _riskConstants The new risk constants ratio of the pool.
     */
    function updateRiskConstants(address _pool, uint256 _riskConstants) public {
        require(
            _riskConstants > FixedPoint96.Q96,
            "The minimum collateral ratio must be greater than 1."
        );
        _poolAddressToRiskConstants[_pool].minCR = _riskConstants;
    }

    //-------------------------------------------------------------------------------------------------------------------------------------------------------//
    // Position Attributes Modifier Functions
    //-------------------------------------------------------------------------------------------------------------------------------------------------------//

    /**
     * @notice Sets the liquidity of a position.
     * @param _tokenId The ID of the position to set the liquidity of.
     * @param _liquidity The new liquidity of the position.
     */
    function setNewLiquidity(
        uint256 _tokenId,
        uint128 _liquidity
    ) public onlyBOorAP onlyActivePosition(_tokenId) {
        Position storage _position = _positionFromTokenId[_tokenId];
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

    //     Position memory _position = _positionFromTokenId[_tokenId];

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

    //     _allPositions.push(position);
    //     _positionsFromAddress[_owner].push(position);
    //     _positionFromTokenId[_newTokenId] = position;
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
    function liquidatable(uint256 _tokenId) public override returns (bool) {
        Position memory position = _positionFromTokenId[_tokenId];
        return
            computeCR(_tokenId) <
            _poolAddressToRiskConstants[position.poolAddress].minCR;
    }

    /**
     * @notice Liquidates a position.
     * @dev Given that the caller has enough GHO to reimburse the position's debt, the position is liquidated, the GHO is burned and the NFT is transfered to the caller.
     * @param _tokenId The ID of the position to liquidate.
     * @param _GHOToRepay The amount of GHO to repay to reimburse the debt of the position.
     * @return hasBeenLiquidated, true if the position has been liquidated and false otherwise.
     */
    function liquidatePosition(
        uint256 _tokenId,
        uint256 _GHOToRepay
    ) public override returns (bool) {
        require(liquidatable(_tokenId), "Position is not liquidatable");
        require(
            debtOf(_tokenId) <= _GHOToRepay,
            "Not enough GHO to repay debt"
        );

        uint256 repayAmount = _GHOToRepay;
        uint256 GHOfees = 0;

        // BorrowData[] memory _borrowDataArray = _borrowDataFromTokenId[_tokenId];
        // for (uint32 i = 0; i < _borrowDataArray.length; i++) {
        //     if (repayAmount == 0) {
        //         break;
        //     } else if (repayAmount > _debtOf(_borrowDataArray[i])) {
        //         repayAmount -= _debtOf(_borrowDataArray[i]);
        //         GHOfees += _debtOf(_borrowDataArray[i]);
        //         if (repayAmount >= _borrowDataArray[i].mintedAmount) {
        //             repayAmount -= _borrowDataArray[i].mintedAmount;
        //             activePool.decreaseMintedSupply(
        //                 _borrowDataArray[i].mintedAmount,
        //                 _positionFromTokenId[_tokenId].user
        //             );
        //             delete _borrowDataFromTokenId[_tokenId][i];
        //         } else {
        //             _borrowDataFromTokenId[_tokenId][i].amount = 0;
        //             _borrowDataFromTokenId[_tokenId][i]
        //                 .mintedAmount -= repayAmount;
        //             activePool.decreaseMintedSupply(
        //                 repayAmount,
        //                 _positionFromTokenId[_tokenId].user
        //             );
        //             repayAmount = 0;
        //         }
        //     } else {
        //         _borrowDataFromTokenId[_tokenId][i].amount -= repayAmount;
        //         GHOfees += repayAmount;
        //         repayAmount = 0;
        //     }
        // }

        // activePool.repayInterestFromUserToProtocol(msg.sender, GHOfees);
        // Position memory position = _positionFromTokenId[_tokenId];
        // position.debt = 0;
        // position.status = Status.closedByLiquidation;
        // _positionFromTokenId[_tokenId] = position;

        // activePool.sendPosition(msg.sender, _tokenId);

        return true;
    }

    /**
     * @notice Liquidates a position and its underlyings.
     * @dev Given that the caller has enough GHO to reimburse the position's debt, the position is liquidated, the GHO is burned and the NFT is transfered to the caller.
     * @param _tokenId The ID of the position to liquidate.
     * @param _GHOToRepay The amount of GHO to repay to reimburse the debt of the position.
     * @return hasBeenLiquidated true if the position has been liquidated and false otherwise.
     */
    function liquidateUnderlyings(
        uint256 _tokenId,
        uint256 _GHOToRepay
    ) public override returns (bool hasBeenLiquidated) {
        require(liquidatable(_tokenId), "Position is not liquidatable");
        require(
            debtOf(_tokenId) <= _GHOToRepay,
            "Not enough GHO to repay debt"
        );

        uint256 repayAmount = _GHOToRepay;
        uint256 GHOfees = 0;

        // BorrowData[] memory _borrowDataArray = _borrowDataFromTokenId[_tokenId];
        // for (uint32 i = 0; i < _borrowDataArray.length; i++) {
        //     if (repayAmount == 0) {
        //         break;
        //     } else if (repayAmount > _debtOf(_borrowDataArray[i])) {
        //         repayAmount -= _debtOf(_borrowDataArray[i]);
        //         GHOfees += _debtOf(_borrowDataArray[i]);
        //         if (repayAmount >= _borrowDataArray[i].mintedAmount) {
        //             repayAmount -= _borrowDataArray[i].mintedAmount;
        //             activePool.decreaseMintedSupply(
        //                 _borrowDataArray[i].mintedAmount,
        //                 _positionFromTokenId[_tokenId].user
        //             );
        //             delete _borrowDataFromTokenId[_tokenId][i];
        //         } else {
        //             _borrowDataFromTokenId[_tokenId][i].amount = 0;
        //             _borrowDataFromTokenId[_tokenId][i]
        //                 .mintedAmount -= repayAmount;
        //             activePool.decreaseMintedSupply(
        //                 repayAmount,
        //                 _positionFromTokenId[_tokenId].user
        //             );
        //             repayAmount = 0;
        //         }
        //     } else {
        //         _borrowDataFromTokenId[_tokenId][i].amount -= repayAmount;
        //         GHOfees += repayAmount;
        //         repayAmount = 0;
        //     }
        // }

        // Position memory position = _positionFromTokenId[_tokenId];

        // activePool.repayInterestFromUserToProtocol(msg.sender, GHOfees);

        // activePool.decreaseLiquidity(_tokenId, position.liquidity, msg.sender);

        // position.debt = 0;
        // position.status = Status.closedByLiquidation;
        // _positionFromTokenId[_tokenId] = position;
    }

    /**
     * @notice Liquidates multiple positions.
     * @dev Given that the callers have enough GHO to reimburse the positions' debt, the positions are liquidated, the GHO is burned and the NFTs are transfered to the callers.
     * @param _tokenIds The IDs of the positions to liquidate.
     * @param _GHOToRepays The amounts of GHO to repay to reimburse the debt of the positions.
     */
    function batchliquidate(
        uint256[] memory _tokenIds,
        uint256[] memory _GHOToRepays
    ) public override {
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
        require(
            _positionFromTokenId[_tokenId].status == Status.active,
            "Position does not exist or is closed"
        );
        _;
    }

    /**
     * @notice Checks if the caller is the borrower operations contract.
     * @dev This modifier is used to restrict access to the borrower operations contract.
     */
    modifier onlyBorrowerOperations() {
        require(
            msg.sender == borrowerOperationsAddress,
            "This operation is restricted"
        );
        _;
    }

    modifier onlyBOorAP() {
        require(
            msg.sender == borrowerOperationsAddress ||
                msg.sender == address(activePool),
            "This operation is restricted"
        );
        _;
    }

    modifier onlyBOorLPPM() {
        require(
            msg.sender == address(this) ||
                msg.sender == borrowerOperationsAddress,
            "This operation is restricted2"
        );
        _;
    }

    // base is a fixedpoint96 number, exponent is a regular unsigned integer
    function lessDumbPower(
        uint256 _base,
        uint256 _exponent
    ) public pure returns (uint256 result) {
        // do fast exponentiation by checking parity of exponent
        if (_exponent == 0) {
            result = FixedPoint96.Q96;
        } else if (_exponent == 1) {
            result = _base;
        } else if (_exponent % 2 == 0) {
            result = lessDumbPower(_base, _exponent / 2);
            // calculate the square of the square root with FullMath.mulDiv
            result = FullMath.mulDiv(result, result, FixedPoint96.Q96);
        } else {
            result = lessDumbPower(_base, (_exponent - 1) / 2);
            // calculate the square of the square root with FullMath.mulDiv and multiply by base once
            result = FullMath.mulDiv(result, result, FixedPoint96.Q96);
            result = FullMath.mulDiv(result, _base, FixedPoint96.Q96);
        }
    }
}
