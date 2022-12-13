// SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

import "./interfaces/IStabilityPool.sol";
import "./interfaces/IActivePool.sol";
import "./interfaces/ILPPositionsManager.sol";
import "./interfaces/IGHOToken.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap-core/libraries/TickMath.sol";
import "@uniswap-core/libraries/FullMath.sol";
import "@uniswap-core/libraries/FixedPoint96.sol";
import "@uniswap-periphery/interfaces/INonfungiblePositionManager.sol";
import "@uniswap-periphery/libraries/LiquidityAmounts.sol";
import "@uniswap-periphery/libraries/PoolAddress.sol";
import "@uniswap-periphery/libraries/OracleLibrary.sol";
import "@uniswap-periphery/libraries/TransferHelper.sol";
import "forge-std/console.sol";
import "@uniswap-core/interfaces/IUniswapV3Factory.sol";

/*
 * @title LPPositionsManager contract
 * @notice Contains the logic for position operations performed by users.
 * @dev The contract is owned by the Eclypse system, and is called by the LPPositionManager contract.
 */

contract LPPositionsManager is ILPPositionsManager, Ownable {
    using SafeMath for uint256;

    uint32 constant lookBackTWAP = 60; // Number of seconds to calculate the TWAP
    uint256 constant interestRate = 79228162564705624056075081118; // 2% APY interest rate : fixedpoint96 value found by evaluating "1.02^(1/(12*30*24*60*60))*2^96" on https://www.mathsisfun.com/calculator-precision.html

    address constant ETHAddress = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant factoryAddress =
        0x1F98431c8aD98523631AE4a59f267346ea31F984;

    INonfungiblePositionManager constant uniswapPositionsNFT =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

    IUniswapV3Factory internal uniswapFactory =
        IUniswapV3Factory(factoryAddress);

    address gasPoolAddress;
    address public borrowerOperationsAddress;

    // IStabilityPool public stabilityPool;
    IActivePool public activePool;
    IGHOToken public GHOToken;

    // List of all of the LPPositionsManager's events

    event BorrowerOperationsAddressChanged(
        address _newBorrowerOperationsAddress
    );
    event GHOTokenAddressChanged(address _newGHOTokenAddress);
    event ActivePoolAddressChanged(address _activePoolAddress);
    // event StabilityPoolAddressChanged(address _stabilityPoolAddress);
    // event GasPoolAddressChanged(address _gasPoolAddress);

    // The pool's data
    struct RiskConstants {
        uint256 minCR; // Minimum collateral ratio
    }

    struct PoolPricingInfo {
        address poolAddress;
        bool inv; // true if and only if WETH is token0 of the pool.
    }

    mapping(address => bool) private _acceptedPoolAddresses;

    mapping(address => RiskConstants) private _poolAddressToRiskConstants;
    // Retrieves a pool's data given the pool's address.

    Position[] private _allPositions;
    // An array of all positions.

    mapping(address => Position[]) private _positionsFromAddress;
    // Retrieves every positions a user has, under the form of an array, given the user's address.

    mapping(uint256 => Position) private _positionFromTokenId;
    // Retrieves a position given its tokenId.

    mapping(address => PoolPricingInfo) private _tokenToWETHPoolInfo;

    // Retrieves the address of the pool associated with the pair (token/ETH) where given the token's address.

    //-------------------------------------------------------------------------------------------------------------------------------------------------------//
    // Constructors
    //-------------------------------------------------------------------------------------------------------------------------------------------------------//

    function setAddresses(
        address _borrowerOperationsAddress,
        address _activePoolAddress,
        // address _stabilityPoolAddress,
        // address _gasPoolAddress,
        address _GHOTokenAddress
    ) external override onlyOwner {
        borrowerOperationsAddress = _borrowerOperationsAddress;
        activePool = IActivePool(_activePoolAddress);
        // stabilityPool = IStabilityPool(_stabilityPoolAddress);
        // gasPoolAddress = _gasPoolAddress;
        GHOToken = IGHOToken(_GHOTokenAddress);

        emit BorrowerOperationsAddressChanged(_borrowerOperationsAddress);
        emit ActivePoolAddressChanged(_activePoolAddress);
        // emit StabilityPoolAddressChanged(_stabilityPoolAddress);
        // emit GasPoolAddressChanged(_gasPoolAddress);
        emit GHOTokenAddressChanged(_GHOTokenAddress);

        // renounceOwnership();
    }

    function addPairToProtocol(
        address _poolAddress,
        address _token0,
        address _token1,
        address _ETHpoolToken0,
        address _ETHpoolToken1,
        bool _inv0,
        bool _inv1
    ) public override {
        _acceptedPoolAddresses[_poolAddress] = true;
        _tokenToWETHPoolInfo[_token0] = PoolPricingInfo(_ETHpoolToken0, _inv0);
        _tokenToWETHPoolInfo[_token1] = PoolPricingInfo(_ETHpoolToken1, _inv1);
        emit TokenAddedToPool(_token0, _ETHpoolToken0, block.timestamp);
        emit TokenAddedToPool(_token1, _ETHpoolToken1, block.timestamp);
    }

    //-------------------------------------------------------------------------------------------------------------------------------------------------------//
    // Getters for positions
    //-------------------------------------------------------------------------------------------------------------------------------------------------------//

    function getPosition(uint256 _tokenId)
        public
        view
        returns (Position memory position)
    {
        return _positionFromTokenId[_tokenId];
    }

    function getPositionsOwnersCount() external view returns (uint256) {
        return _allPositions.length;
    }

    //-------------------------------------------------------------------------------------------------------------------------------------------------------//
    // Position Statuses
    //-------------------------------------------------------------------------------------------------------------------------------------------------------//

    // Get the status of a position given the position's tokenId.
    function getPositionStatus(uint256 _tokenId)
        public
        view
        override
        returns (Status status)
    {
        return _positionFromTokenId[_tokenId].status;
    }

    // Allows the owner of this contract to change the status of a position with a given status, given the position's tokenId.
    function changePositionStatus(uint256 _tokenId, Status status)
        public
        override
        onlyBorrowerOperations
    {
        require(
            getPositionStatus(_tokenId) != status,
            "A position status cannot be changed to its current one."
        );
        _positionFromTokenId[_tokenId].status = status;
    }

    // Allows BorrowerOperations to deposit a user's LP.
    function openPosition(address _owner, uint256 _tokenId)
        public
        override
        onlyBorrowerOperations
    {
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

        emit DepositedLP(_owner, _tokenId, block.timestamp);
    }

    //-------------------------------------------------------------------------------------------------------------------------------------------------------//
    // Position Amounts
    //-------------------------------------------------------------------------------------------------------------------------------------------------------//

    // Given a position's tokenId, calls computePositionAmounts on this position.
    function positionAmounts(uint256 _tokenId)
        public
        view
        override
        returns (uint256 amountToken0, uint256 amountToken1)
    {
        _requirePositionIsActive(_tokenId);
        Position memory _position = _positionFromTokenId[_tokenId];
        return computePositionAmounts(_position);
    }

    // Given a position, computes the amount of token0 relative to token1 and the amount of token1 relative to token0.
    function computePositionAmounts(Position memory _position)
        public
        view
        override
        returns (uint256 amountToken0, uint256 amountToken1)
    {
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

    //(1) Given a position's tokenId, calls positionAmounts on this tokenId.
    //(2) Computes the position's token0 and token1 values in ETH.
    //(3) Computes the position's token0 amount value given the token0 value in ETH.
    //(4) Computes the position's token1 amount value given the token1 value in ETH.
    //(5) Returns the position's value expressed as the sum of (3) & (4).

    //-------------------------------------------------------------------------------------------------------------------------------------------------------//
    // Debt Functions
    //-------------------------------------------------------------------------------------------------------------------------------------------------------//

    // Given a position's tokenId, returns the current debt of this position.
    function debtOf(uint256 _tokenId) public view override returns (uint256) {
        _requirePositionIsActive(_tokenId);

        uint256 _lastUpdateTimestamp = _positionFromTokenId[_tokenId]
            .lastUpdateTimestamp;
        uint256 debtPlusInterest = FullMath.mulDiv(
            _positionFromTokenId[_tokenId].debt,
            dumbPower(interestRate, block.timestamp - _lastUpdateTimestamp),
            FixedPoint96.Q96
        );

        return debtPlusInterest;
    }

    // Given a user's address, computes the sum of all of its positions' debt.
    function totalDebtOf(address _user)
        public
        view
        returns (uint256 totalDebtInGHO)
    {
        for (uint32 i = 0; i < _positionsFromAddress[_user].length; i++) {
            if (_positionsFromAddress[_user][i].status == Status.active) {
                totalDebtInGHO += debtOf(
                    _positionsFromAddress[_user][i].tokenId
                );
            }
        }
        return totalDebtInGHO;
    }

    // Given a position's tokenId and an amount, allows BorrowerOperations to increase the debt of a position by this amount.
    function increaseDebtOf(uint256 _tokenId, uint256 _amount)
        public
        override
        onlyBorrowerOperations
    {
        _requirePositionIsActive(_tokenId);
        require(
            _amount > 0,
            "A debt cannot be increased by a negative amount or by 0."
        );

        uint256 _lastUpdateTimestamp = _positionFromTokenId[_tokenId]
            .lastUpdateTimestamp;
        uint256 previousDebtPlusInterest = FullMath.mulDiv(
            _positionFromTokenId[_tokenId].debt,
            dumbPower(interestRate, block.timestamp - _lastUpdateTimestamp),
            FixedPoint96.Q96
        );
        _positionFromTokenId[_tokenId].debt =
            previousDebtPlusInterest +
            _amount;
        _positionFromTokenId[_tokenId].lastUpdateTimestamp = block.timestamp;

        emit IncreasedDebt(
            _positionFromTokenId[_tokenId].user,
            _tokenId,
            _positionFromTokenId[_tokenId].debt - _amount,
            _positionFromTokenId[_tokenId].debt,
            block.timestamp
        );
    }

    // Given a position's tokenId and an amount, allows BorrowerOperations to decrease the debt of a position by this amount.
    function decreaseDebtOf(uint256 _tokenId, uint256 _amount)
        public
        override
        onlyBorrowerOperations
        returns (uint256 leftOver)
    {
        _requirePositionIsActive(_tokenId);
        require(
            _amount > 0,
            "A debt cannot be decreased by a negative amount or by 0."
        );

        uint256 _lastUpdateTimestamp = _positionFromTokenId[_tokenId]
            .lastUpdateTimestamp;
        uint256 previousDebtPlusInterest = FullMath.mulDiv(
            _positionFromTokenId[_tokenId].debt,
            dumbPower(interestRate, block.timestamp - _lastUpdateTimestamp),
            FixedPoint96.Q96
        );

        if (previousDebtPlusInterest < _amount) {
            _positionFromTokenId[_tokenId].debt = 0;
            leftOver = _amount - previousDebtPlusInterest;
        } else {
            uint256 newDebt = previousDebtPlusInterest - _amount;
            _positionFromTokenId[_tokenId].debt = newDebt;
            _positionFromTokenId[_tokenId].lastUpdateTimestamp = block
                .timestamp;
        }

        emit DecreasedDebt(
            _positionFromTokenId[_tokenId].user,
            _tokenId,
            _positionFromTokenId[_tokenId].debt + _amount,
            _positionFromTokenId[_tokenId].debt,
            block.timestamp
        );
    }

    //-------------------------------------------------------------------------------------------------------------------------------------------------------//
    // Values in ETH Functions
    //-------------------------------------------------------------------------------------------------------------------------------------------------------//

    // Returns the price in ETH in the form of as a Q64.96 fixed point number.
    function priceInETH(address tokenAddress)
        public
        view
        override
        returns (uint256)
    {
        if (tokenAddress == ETHAddress) return FixedPoint96.Q96;
        (int24 twappedTick, ) = OracleLibrary.consult(
            _tokenToWETHPoolInfo[tokenAddress].poolAddress,
            lookBackTWAP
        );
        uint160 sqrtRatioX96 = TickMath.getSqrtRatioAtTick(twappedTick);
        uint256 ratio = FullMath.mulDiv(
            sqrtRatioX96,
            sqrtRatioX96,
            FixedPoint96.Q96
        );
        if (_tokenToWETHPoolInfo[tokenAddress].inv)
            return FullMath.mulDiv(FixedPoint96.Q96, FixedPoint96.Q96, ratio);
        // need to confirm if this is mathematically correct!
        else return ratio;
    }

    function debtOfInETH(uint256 _tokenId)
        public
        view
        override
        returns (uint256)
    {
        return
            FullMath.mulDivRoundingUp(
                debtOf(_tokenId),
                priceInETH(address(GHOToken)),
                FixedPoint96.Q96
            );
    }

    function positionValueInETH(uint256 _tokenId)
        public
        view
        override
        returns (uint256 value)
    {
        (uint256 amount0, uint256 amount1) = positionAmounts(_tokenId);
        address token0 = _positionFromTokenId[_tokenId].token0;
        address token1 = _positionFromTokenId[_tokenId].token1;
        //return amount0 * priceInETH(token0) + amount1 * priceInETH(token1);
        return
            FullMath.mulDiv(amount0, priceInETH(token0), FixedPoint96.Q96) +
            FullMath.mulDiv(amount1, priceInETH(token1), FixedPoint96.Q96);
    }

    // Given a user's address, computes the sum of all of its positions' values.
    function totalPositionsValueInETH(address _user)
        public
        view
        override
        returns (uint256 totalValue)
    {
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

    function computeCR(uint256 _tokenId) public view returns (uint256) {
        return _computeCR(positionValueInETH(_tokenId), debtOfInETH(_tokenId));
    }

    function _computeCR(uint256 _collValue, uint256 _debt)
        public
        pure
        returns (uint256)
    {
        if (_debt > 0) {
            // uint256 newCollRatio = _collValue.div(_debt); // This is not accurate, because we are working with integers.
            // Solution : work with fixed point collateral ratios :
            uint256 newCollRatio = FullMath.mulDiv(
                _collValue,
                FixedPoint96.Q96,
                _debt
            );
            return newCollRatio;
        }
        // Return the maximal value for uint256 if the Trove has a debt of 0. Represents "infinite" CR.
        else {
            // if (_debt == 0)
            return 2**256 - 1;
        }
    }

    function getRiskConstants(address _pool)
        public
        view
        returns (uint256 minCR)
    {
        return _poolAddressToRiskConstants[_pool].minCR;
    }

    // Allows the owner of this contract to add risk constants for a certain type of LP.
    // THIS RATIO IS ENCODED AS A 96-DECIMALS FIXED POINT.
    function updateRiskConstants(address _pool, uint256 _minCR) public {
        require(
            _minCR > FixedPoint96.Q96,
            "The minimum collateral ratio must be greater than 1."
        );
        _poolAddressToRiskConstants[_pool].minCR = _minCR;
    }

    //-------------------------------------------------------------------------------------------------------------------------------------------------------//
    // Position Attributes Modifier Functions
    //-------------------------------------------------------------------------------------------------------------------------------------------------------//

    // Given a position's tokenId and an amount, allows BorrowerOperations to set the liquidity of a position to this amount.
    function setNewLiquidity(uint256 _tokenId, uint128 _liquidity)
        public
        onlyBorrowerOperations
    {
        _requirePositionIsActive(_tokenId);
        Position storage _position = _positionFromTokenId[_tokenId];
        _position.liquidity = _liquidity;
    }

    function _changeTicks(
        uint256 _tokenId,
        int24 _newMinTick,
        int24 _newMaxTick
    ) public payable onlyBorrowerOperations {
        require(
            _newMinTick < _newMaxTick,
            "The new min tick must be smaller than the new max tick."
        );
        require(
            _newMinTick >= -887272,
            "The new min tick must be greater than -887272."
        );
        require(
            _newMaxTick <= 887272,
            "The new max tick must be smaller than 887272."
        );

        Position memory _position = _positionFromTokenId[_tokenId];

        _requirePositionIsActive(_tokenId);

        (
            uint256 amount0ToWithdraw,
            uint256 amount1ToWithdraw
        ) = positionAmounts(_tokenId);

        TransferHelper.safeApprove(
            _position.token0,
            address(uniswapPositionsNFT),
            amount0ToWithdraw
        );
        TransferHelper.safeApprove(
            _position.token1,
            address(uniswapPositionsNFT),
            amount1ToWithdraw
        );

        INonfungiblePositionManager.CollectParams
            memory collectParams = INonfungiblePositionManager.CollectParams({
                tokenId: _tokenId,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            });

        INonfungiblePositionManager.MintParams memory mintParams = INonfungiblePositionManager
            .MintParams({
                token0: _position.token0,
                token1: _position.token1,
                fee: _position.fee,
                tickLower: _newMinTick,
                tickUpper: _newMaxTick,
                amount0Desired: amount0ToWithdraw,
                amount1Desired: amount1ToWithdraw,
                amount0Min: 0, //TODO: Change that cause it represents a vulnerability
                amount1Min: 0, //TODO: Change that cause it represents a vulnerability
                recipient: address(this),
                deadline: block.timestamp
            });

        (uint256 _amount0, uint256 _amount1) = uniswapPositionsNFT.collect(
            collectParams
        );

        TransferHelper.safeTransfer(_position.token0, address(this), _amount0);
        TransferHelper.safeTransfer(_position.token1, address(this), _amount1);

        (uint256 _newTokenId, , , ) = uniswapPositionsNFT.mint(mintParams);

        Position memory position = setNewPosition(
            msg.sender,
            _position.poolAddress,
            _newTokenId,
            Status.active,
            _position.debt,
            _position.lastUpdateTimestamp
        );

        _allPositions.push(position);
        _positionsFromAddress[msg.sender].push(position);
        _positionFromTokenId[_newTokenId] = position;

        _position.status = Status.closedByOwner;
        uniswapPositionsNFT.burn(_tokenId);
    }

    function setNewPosition(
        address _owner,
        address _poolAddress,
        uint256 _newTokenId,
        Status _status,
        uint256 _debt,
        uint256 _lastUpdate
    ) public view returns (Position memory) {
        (
            ,
            ,
            address _token0,
            address _token1,
            uint24 _fee,
            int24 _tickLower,
            int24 _tickUpper,
            uint128 _liquidity,
            ,
            ,
            ,

        ) = uniswapPositionsNFT.positions(_newTokenId);

        return
            Position({
                user: _owner,
                token0: _token0,
                token1: _token1,
                fee: _fee,
                tickLower: _tickLower,
                tickUpper: _tickUpper,
                liquidity: _liquidity,
                poolAddress: _poolAddress,
                tokenId: _newTokenId,
                status: _status,
                debt: _debt,
                lastUpdateTimestamp: _lastUpdate
            });
    }

    //-------------------------------------------------------------------------------------------------------------------------------------------------------//
    // Liquidation functions
    //-------------------------------------------------------------------------------------------------------------------------------------------------------//

    // Given a position's tokenId, checks if this position is liquidatable.
    function liquidatable(uint256 _tokenId)
        public
        view
        override
        returns (bool)
    {
        Position memory position = _positionFromTokenId[_tokenId];
        /*return
            positionValueInETH(_tokenId) <
            FullMath.mulDiv(
                debtOf(_tokenId),
                _poolAddressToRiskConstants[position.poolAddress].minCR,
                FixedPoint96.Q96
            );*/
        return
            computeCR(_tokenId) <
            _poolAddressToRiskConstants[position.poolAddress].minCR;
    }

    // liquidation by a simple public liquidate function.
    function liquidate(uint256 _tokenId, uint256 _GHOToRepay)
        public
        override
        returns (bool)
    {
        require(liquidatable(_tokenId), "Position is not liquidatable");
        require(
            debtOf(_tokenId) <= _GHOToRepay,
            "Not enough GHO to repay debt"
        );
        //We should burn the GHO here.
        GHOToken.burn(msg.sender, debtOf(_tokenId)); // burn exactly the debt
        Position memory position = _positionFromTokenId[_tokenId];
        position.debt = 0;
        position.status = Status.closedByLiquidation;
        _positionFromTokenId[_tokenId] = position;

        // uint128 currentLiquidity = position.liquidity;
        // uint128 liquidityToDecrease = (currentLiquidity * 5) / 100;
        // INonfungiblePositionManager.DecreaseLiquidityParams memory params =
        //     INonfungiblePositionManager.DecreaseLiquidityParams({
        //         tokenId: _tokenId,
        //         liquidity: liquidityToDecrease,
        //         amount0Min: 0,
        //         amount1Min: 0,
        //         deadline: block.timestamp
        //     });
        //(uint256 amount0, uint256 amount1) = uniswapPositionsNFT.decreaseLiquidity(params);

        activePool.sendLp(msg.sender, _tokenId);

        return true;
    }

    function batchLiquidate(
        uint256[] memory _tokenIds,
        uint256[] memory _GHOToRepays
    ) public override {
        require(_tokenIds.length == _GHOToRepays.length);
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            liquidate(_tokenIds[i], _GHOToRepays[i]);
        }
    }

    //-------------------------------------------------------------------------------------------------------------------------------------------------------//
    // Modifiers and Require functions
    //-------------------------------------------------------------------------------------------------------------------------------------------------------//

    //Checks is a given position is active to avoid unecessary computations.
    function _requirePositionIsActive(uint256 _tokenId) public view override {
        require(
            _positionFromTokenId[_tokenId].status == Status.active,
            "LPPositionManager: Position does not exist or is closed"
        );
    }

    function _checkOwnership(uint256 _tokenId, address _owner) public view {
        require(
            _positionFromTokenId[_tokenId].user == _owner,
            "LPPositionManager: You are not the owner of this position"
        );
    }

    modifier onlyBorrowerOperations() {
        require(
            msg.sender == borrowerOperationsAddress,
            "This operation is restricted"
        );
        _;
    }

    // base is a fixedpoint96 number, exponent is a regular unsigned integer
    function dumbPower(uint256 _base, uint256 _exponent)
        public
        pure
        returns (uint256 result)
    {
        result = FixedPoint96.Q96;
        for (uint256 i = 0; i < _exponent; i++) {
            result = FullMath.mulDiv(result, _base, FixedPoint96.Q96);
        }
    }
}
