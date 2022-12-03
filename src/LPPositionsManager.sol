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

import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import "@uniswap/v3-core/contracts/libraries/FixedPoint96.sol";

import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import "@uniswap/v3-periphery/contracts/libraries/PoolAddress.sol";
import "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";

contract LPPositionsManager is ILPPositionsManager, Ownable {
    using SafeMath for uint256;

    uint32 constant lookBackTWAP = 60; // Number of seconds to calculate the TWAP

    address constant ETHAddress = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant GHOAddress = 0x0000000000000000000000000000000000000000; //TBD
    address constant factoryAddress =
        0x1F98431c8aD98523631AE4a59f267346ea31F984;

    INonfungiblePositionManager constant uniswapPositionsNFT =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

    address gasPoolAddress;
    address public borrowerOperationsAddress;

    // IStabilityPool public stabilityPool;
    IActivePool public activePool;
    IGHOToken public GHOToken;

    //List of all of the LPPositionsManager's events

    event BorrowerOperationsAddressChanged(
        address _newBorrowerOperationsAddress
    );
    event GHOTokenAddressChanged(address _newGHOTokenAddress);
    event ActivePoolAddressChanged(address _activePoolAddress);
    // event StabilityPoolAddressChanged(address _stabilityPoolAddress);
    // event GasPoolAddressChanged(address _gasPoolAddress);

    //The pool's data
    struct RiskConstants {
        uint256 minCR; // Minimum collateral ratio
    }

    struct PoolPricingInfo {
        address poolAddress;
        bool inv; // true if and only if WETH is token0 of the pool.
    }

    mapping(address => RiskConstants) private _poolAddressToRiskConstants;
    //Retrieves a pool's data given the pool's address.

    Position[] private _allPositions;
    //An array of all positions.

    mapping(address => Position[]) private _positionsFromAddress;
    //Retrieves every positions a user has, under the form of an array, given the user's address.

    mapping(uint256 => Position) private _positionFromTokenId;
    //Retrieves a position given its tokenId.

    mapping(address => PoolPricingInfo) private _tokenToWETHPoolInfo;

    //Retrieves the address of the pool associated with the pair (token/ETH) where given the token's address.

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

        renounceOwnership();
    }

    function getTroveOwnersCount() external view returns (uint256) {
        return _allPositions.length;
    }

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

    //Allows the owner of this contract to add a pair of (token/ETH).
    function addTokenETHpoolAddress(
        address _token,
        address _pool,
        bool _inv
    ) public override onlyOwner {
        _tokenToWETHPoolInfo[_token] = PoolPricingInfo(_pool, _inv);
        emit TokenAddedToPool(_token, _pool, block.timestamp);
    }

    //Allows the owner of this contract to add risk constants for a certain type of LP.
    //THIS RATIO IS ENCODED AS A 96-DECIMALS FIXED POINT.
    function updateRiskConstants(address _pool, uint256 _minCR)
        public
        onlyOwner
    {
        require(_minCR > FixedPoint96.Q96);
        _poolAddressToRiskConstants[_pool].minCR = _minCR;
    }

    //Get the status of a position given the position's tokenId.
    function getPositionStatus(uint256 _tokenId)
        public
        view
        override
        returns (Status status)
    {
        return _positionFromTokenId[_tokenId].status;
    }

    //Allows the owner of this contract to change the status of a position with a given status, given the position's tokenId.
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

        address poolAddress = PoolAddress.computeAddress(
            factoryAddress,
            PoolAddress.getPoolKey(token0, token1, fee)
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
            0
        );

        _allPositions.push(position);
        _positionsFromAddress[_owner].push(position);
        _positionFromTokenId[_tokenId] = position;

        emit DepositedLP(_owner, _tokenId, block.timestamp);
    }

    function getPosition(uint256 _tokenId)
        public
        view
        returns (Position memory position)
    {
        return _positionFromTokenId[_tokenId];
    }

    //Given a position, computes the amount of token0 relative to token1 and the amount of token1 relative to token0.
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

    //Given a position's tokenId, calls computePositionAmounts on this position.
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

    //(1) Given a position's tokenId, calls positionAmounts on this tokenId.
    //(2) Computes the position's token0 and token1 values in ETH.
    //(3) Computes the position's token0 amount value given the token0 value in ETH.
    //(4) Computes the position's token1 amount value given the token1 value in ETH.
    //(5) Returns the position's value expressed as the sum of (3) & (4).

    function positionValueInETH(uint256 _tokenId)
        public
        view
        override
        returns (uint256 value)
    {
        (uint256 amount0, uint256 amount1) = positionAmounts(_tokenId);

        address token0 = _positionFromTokenId[_tokenId].token0;
        address token1 = _positionFromTokenId[_tokenId].token1;

        return amount0 * priceInETH(token0) + amount1 * priceInETH(token1);
    }

    //Given a user's address, computes the sum of all of its positions' values.
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

    //Given a position's tokenId, returns the current debt of this position.
    function debtOf(uint256 _tokenId) public view override returns (uint256) {
        _requirePositionIsActive(_tokenId);
        Position memory _position = _positionFromTokenId[_tokenId];
        return _position.debt;
    }

    function debtOfInETH(uint256 _tokenId)
        public
        view
        override
        returns (uint256)
    {
        return
            FullMath.mulDiv(
                debtOf(_tokenId),
                priceInETH(GHOAddress),
                FixedPoint96.Q96
            );
    }

    //Given a user's address, computes the sum of all of its positions' debt.
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

    //Given a position's tokenId and an amount, allows BorrowerOperations to set the liquidity of a position to this amount.
    function setNewLiquidity(uint256 _tokenId, uint128 _liquidity)
        public
        onlyBorrowerOperations
    {
        _requirePositionIsActive(_tokenId);
        Position storage _position = _positionFromTokenId[_tokenId];
        _position.liquidity = _liquidity;
    }

    //Given a position's tokenId and an amount, allows BorrowerOperations to increase the debt of a position by this amount.
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

        _positionFromTokenId[_tokenId].debt += _amount;

        emit IncreasedDebt(
            _positionFromTokenId[_tokenId].user,
            _tokenId,
            _positionFromTokenId[_tokenId].debt - _amount,
            _positionFromTokenId[_tokenId].debt,
            block.timestamp
        );
    }

    //Given a position's tokenId and an amount, allows BorrowerOperations to decrease the debt of a position by this amount.
    function decreaseDebtOf(uint256 _tokenId, uint256 _amount)
        public
        override
        onlyBorrowerOperations
    {
        _requirePositionIsActive(_tokenId);
        require(
            _amount > 0,
            "A debt cannot be decreased by a negative amount or by 0."
        );

        if (_positionFromTokenId[_tokenId].debt < _amount) {
            _positionFromTokenId[_tokenId].debt = 0;
        } else {
            _positionFromTokenId[_tokenId].debt -= _amount;
        }

        emit DecreasedDebt(
            _positionFromTokenId[_tokenId].user,
            _tokenId,
            _positionFromTokenId[_tokenId].debt + _amount,
            _positionFromTokenId[_tokenId].debt,
            block.timestamp
        );
    }

    //Given a position's tokenId, checks if this position is liquidatable.
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
            computeCR(_tokenId) >
            _poolAddressToRiskConstants[position.poolAddress].minCR;
    }

    // (soft) liquidation by a simple public liquidate function.
    function liquidate(uint256 _tokenId, uint256 _GHOToRepay)
        public
        override
        returns (bool)
    {
        require(liquidatable(_tokenId));
        GHOToken.transferFrom(msg.sender, address(this), _GHOToRepay);

        Position memory position = _positionFromTokenId[_tokenId];
        position.debt -= _GHOToRepay;
        if (position.debt == 0) {
            position.status = Status.closedByLiquidation;
        }

        //TODO: burn the received GHO
        GHOToken.burn(address(this), _GHOToRepay);
        //TODO: decrease liquidity of the position such that the liquidator receives 5%
        _positionFromTokenId[_tokenId] = position;

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

    //Returns the price in ETH in the form of as a Q64.96 fixed point number.
    function priceInETH(address tokenAddress)
        public
        view
        override
        returns (uint256)
    {
        if (tokenAddress == ETHAddress) return 1;

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

    function computeCR(uint256 _tokenId) public view returns (uint256) {
        Position storage position = _positionFromTokenId[_tokenId];
        return _computeCR(positionValueInETH(_tokenId), position.debt);
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
            _position.debt
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
        uint256 _debt
    ) public view returns (Position memory position) {
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
                debt: _debt
            });
    }

    /*function priceFeed() public override view returns (IPriceFeed) {
        return priceFeed;
    }*/

    modifier onlyBorrowerOperations() {
        require(
            msg.sender == borrowerOperationsAddress,
            "This operation is restricted"
        );
        _;
    }
}
