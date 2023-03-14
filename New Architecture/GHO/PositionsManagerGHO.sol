// SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

import "./interfaces/IPositionsManager.sol";
import "./interfaces/IEclypseVault.sol";
import "gho-core/src/contracts/gho/GhoToken.sol";
import "@uniswap-periphery/libraries/TransferHelper.sol";


contract PositionsManagerGHO is Ownable, IPositionsManager {

    ProtocolValues public protocolValues;
    ProtocolContracts public protocolContracts;

    GhoToken GHO;

    mapping(address => bool) private whiteListedPools;
    mapping(address => PoolPricingInfo) private tokenToWETHPoolInfo;
    mapping(address => RiskConstants) private riskConstantsFromPool;

    mapping(address => UserPositions) private positionsFromAddress;
    
    mapping(uint256 => Position) private positionFromTokenId;


    function initialize(
        address _uniFactory,
        address _uniPosNFT,
        address _ghoAddress,
        address _userInteractionsAddress,
        address _eclypseVaultAddress
    ) external override onlyOwner {
        protocolContracts.userInteractions = _userInteractionsAddress;
        protocolContracts.eclypseVault = IEclypseVault(_activePoolAddr);
        protocolContracts.uniswapFactory = IUniswapV3Factory(_uniFactory);
        protocolContracts.uniswapPositionsManager = INonfungiblePositionManager(_uniPosNFT);
        protocolContracts.stableCoin = _ghoAddress;
        GHO = GhoToken(_ghoAddress);
    }

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
        }
        if (_token1 != WETHAddress) {
            tokenToWETHPoolInfo[_token1] = PoolPricingInfo(_ETHpoolToken1, _inv1);
        }
    }

    function openPosition(address _owner, uint256 _tokenId) 
    public override onlyChild {

        protocolContracts.uniswapPositionsManager.safeTransferFrom(
            _owner, address(protocolContracts.eclypseVault), _tokenId
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

        UserPositions memory userPositions = positionsFromAddress[_owner];
        userPositions.positions[userPositions.counter] = position;
        userPositions.counter++:
        positionFromTokenId[_tokenId] = position;
    }


    function closePosition(address _owner, uint256 _tokenId)
    public override onlyChild {
        uint256 debt = debtOf(_tokenId);
        if (debt > 0) {
            repay(_owner, _tokenId, debt);
        }
        
        protocolContracts.eclypseVault.sendPosition(_owner, _tokenId);
        positionFromTokenId[_tokenId].status = Status.closedByOwner;
    }

    function getPosition(uint256 _tokenId) 
    public view returns (Position memory position) {
        return positionFromTokenId[_tokenId];
    }

    function positionAmounts(uint256 _tokenId)
    public view override
    returns (uint256 amountToken0, uint256 amountToken1){
        Position memory _position = positionFromTokenId[_tokenId];
        (int24 twappedTick,) = OracleLibrary.consult(_position.poolAddress, protocolValues.twapLength);

        uint160 sqrtRatioX96 = TickMath.getSqrtRatioAtTick(twappedTick);
        uint160 sqrtRatio0X96 = TickMath.getSqrtRatioAtTick(_position.tickLower);
        uint160 sqrtRatio1X96 = TickMath.getSqrtRatioAtTick(_position.tickUpper);
        (uint256 amountToken0, uint256 amountToken1) =
            LiquidityAmounts.getAmountsForLiquidity(sqrtRatioX96, sqrtRatio0X96, sqrtRatio1X96, _position.liquidity);
    }

    function positionValueInETH(uint256 _tokenId)
    public view returns (uint256 value) {
        (uint256 amount0, uint256 amount1) = positionAmounts(_tokenId);
        address token0 = positionFromTokenId[_tokenId].token0;
        address token1 = positionFromTokenId[_tokenId].token1;
        value = FullMath.mulDiv(amount0, priceInETH(token0), FixedPoint96.Q96)
            + FullMath.mulDiv(amount1, priceInETH(token1), FixedPoint96.Q96);
    }

    function totalPositionsValueInETH(address _user) 
    public view override returns (uint256 totalValue) {
        totalValue = 0;
        UserPositions memory userPositions = positionsFromAddress[_user];
        for (uint32 i = 0; i < userPositions.counter; i++) {
            if (userPositions.positions[i].status == Status.active) {
                totalValue += positionValueInETH(userPositions.positions[i].tokenId);
            }
        }
    }

    function debtOf(uint256 _tokenId) 
    public view override returns (uint256 currentDebt) {
        uint256 debtPrincipal = getPosition(_tokenId).debtPrincipal;
        currentDebt = FullMath.mulDivRoundingUp(
            debtPrincipal, protocolValues.interestFactor, getPosition(_tokenId).interestConstant
        );
        uint256 newInterestFactor =
            power(protocolValues.interestRate, block.timestamp - protocolValues.lastFactorUpdate);
        currentDebt = FullMath.mulDivRoundingUp(currentDebt, newInterestFactor, FixedPoint96.Q96);
    }

    function totalDebtOf(address _user) 
    public view returns (uint256 totalDebt) {
        UserPositions memory userPositions = positionsFromAddress[_user];
        for (uint32 i = 0; i < userPositions.counter; i++) {
            if (userPositions.positions[i].status == Status.active) {
                totalDebt += debtOf(userPositions.positions[i].tokenId);
            }
        }
    }

    function debtOfInETH(uint256 _tokenId) 
    public view override returns (uint256) {
        return FullMath.mulDivRoundingUp(
            debtOf(_tokenId), priceInETH(address(protocolContracts.stableCoin)), FixedPoint96.Q96
        );
    }

    function borrow(address sender, uint256 _tokenId, uint256 _amount)
    public override onlyChild {
        require(_amount > 0, "A debt cannot be increased by 0.");

        refreshDebtTracking();
        // From here, the interestFactor is up-to-date.
        (uint256 totalDebt, uint256 debtPrincipal,) = allDebtComponentsOf(_tokenId);

        protocolContracts.eclypseVault.mint(address(this), sender, _amount);
        protocolValues.totalBorrowedStableCoin += _amount;

        positionFromTokenId[_tokenId].interestConstant =
            FullMath.mulDiv(protocolValues.interestFactor, debtPrincipal + _amount, totalDebt + _amount);
        positionFromTokenId[_tokenId].debtPrincipal += _amount;

        if (liquidatable(_tokenId)) {
            revert("The position can't be liquidatable!");
        }
    }

    function repay(address sender, uint256 _tokenId, uint256 _amount)
    public override onlyChild {
        require(_amount > 0, "A debt cannot be decreased by 0.");

        refreshDebtTracking();
        // From here, the interestFactor is up-to-date.
        (uint256 currentDebt, uint256 debtPrincipal, uint256 accumulatedInterest) = allDebtComponentsOf(_tokenId);

        _amount = Math.min(_amount, currentDebt);

        uint256 interestRepayment = Math.min(_amount, accumulatedInterest);
        uint256 principalRepayment = _amount - interestRepayment;

        IERC20(address(protocolContracts.stableCoin)).transferFrom(
            sender, address(protocolContracts.eclypseVault), principalRepayment + interestRepayment
        );
        if (principalRepayment > 0) {
            protocolContracts.eclypseVault.burn(address(this), principalRepayment);
            protocolValues.totalBorrowedStableCoin -= principalRepayment;
        }

        uint256 newDebt = currentDebt - _amount;
        uint256 newDebtPrincipal = debtPrincipal - principalRepayment;

        if (newDebt > 0) {
            positionFromTokenId[_tokenId].interestConstant =
                FullMath.mulDivRoundingUp(protocolValues.interestFactor, newDebtPrincipal, newDebt);
        } else {
            positionFromTokenId[_tokenId].interestConstant = protocolValues.interestFactor;
        }
        positionFromTokenId[_tokenId].debtPrincipal = newDebtPrincipal;

    }

    function increaseLiquidity(address sender, uint256 tokenId, uint256 amountAdd0, uint256 amountAdd1)
    public override onlyChild
    returns (uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        Position memory position = getPosition(tokenId);
        address token0 = position.token0;
        address token1 = position.token1;

        (liquidity,,) = protocolContracts.eclypseVault.increaseLiquidity(sender, tokenId, token0, token1, amountAdd0, amountAdd1);

        Position storage _position = positionFromTokenId[tokenId];
        _position.liquidity = liquidity;
    }

    function decreaseLiquidity(address sender, uint256 tokenId, uint128 liquidityToRemove)
    public override onlyChild
    returns (uint256 amount0, uint256 amount1)
    {
        liquidityToRemove =
            liquidityToRemove > getPosition(tokenId).liquidity ? getPosition(tokenId).liquidity : liquidityToRemove;
        // amount0Min and amount1Min are price slippage checks

        protocolContracts.eclypseVault.decreaseLiquidity(sender, tokenId, liquidityToRemove);

        Position storage _position = positionFromTokenId[tokenId];
        _position.liquidity = getPosition(tokenId).liquidity - liquidityToRemove;

    }

    function priceInETH(address _tokenAddress) 
    public view override 
    returns (uint256) {
        if (_tokenAddress == WETHAddress) return FixedPoint96.Q96;
        //TODO: Call PriceFeed contract.
    }

    function _mint(address _sender, uint256 _amount) 
    public override onlyVault {
        //TODO
    }

    function _burn(uint256 _amount)
    public override onlyVault {
        //TODO
    }

    function collRatioOf(uint256 _tokenId) 
    public view returns (uint256 collRatio) {
        (,,,,,,,,,, uint128 fee0, uint128 fee1) = protocolContracts.uniswapPositionsManager.positions(_tokenId);
        uint256 fees = FullMath.mulDiv(fee0, priceInETH(positionFromTokenId[_tokenId].token0), FixedPoint96.Q96)
            + FullMath.mulDiv(fee1, priceInETH(positionFromTokenId[_tokenId].token1), FixedPoint96.Q96);
        uint256 debt = debtOfInETH(_tokenId);
        uint256 collValue = positionValueInETH(_tokenId) + fees;
        return debt > 0 ? FullMath.mulDiv(collValue, FixedPoint96.Q96, debt) : MAX_UINT256;
    }

    function getRiskConstants(address _pool) 
    public view returns (uint256 riskConstants) {
        return riskConstantsFromPool[_pool].minCR;
    }

    function updateRiskConstants(address _pool, uint256 _riskConstants) 
    public onlyOwner {
        require(_riskConstants > FixedPoint96.Q96, "The minimum collateral ratio must be greater than 1.");
        riskConstantsFromPool[_pool].minCR = _riskConstants;
    }

    function liquidatable(uint256 _tokenId) 
    public override view returns (bool) {
        Position memory position = positionFromTokenId[_tokenId];
        return collRatioOf(_tokenId) < riskConstantsFromPool[position.poolAddress].minCR;
    }

    function liquidatePosition(uint256 _tokenId, uint256 _amountRepay) 
    public returns (bool) {

        require(liquidatable(_tokenId), "The position is not liquidatable.");
        uint256 debt = debtOf(_tokenId);
        require(_amountRepay >= debt, "The amount of GHO to repay is not enough to reimburse the debt of the position.");

        //TODO: Transfer GHO from liquidator to vault.
        //protocolContracts.stableCoin.transferFrom(msg.sender, address(protocolContracts.eclypseVault), debt);
        protocolContracts.eclypseVault.burn(address(this), debt);
        protocolValues.totalBorrowedStableCoin -= positionFromTokenId[_tokenId].debtPrincipal;

        protocolContracts.eclypseVault.transferPosition(msg.sender, _tokenId);
        positionFromTokenId[_tokenId].status = Status.closedByLiquidation;
        return true;
    }

    //TODO: Implement liquidateUnderlyings.
    function liquidateUnderlyings(uint256 _tokenId, uint256 _amountRepay)
    public override returns (bool hasBeenLiquidated)
    {
        require(liquidatable(_tokenId), "Position is not liquidatable");
        require(debtOf(_tokenId) <= _amountRepay, "Not enough GHO to repay debt");

        uint256 repayAmount = _amountRepay;
        uint256 GHOfees = 0;
    }

    function batchliquidate(uint256[] memory _tokenIds, uint256[] memory _amountRepays) 
    public override {
        require(_tokenIds.length == _amountRepays.length);
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            liquidatePosition(_tokenIds[i], _amountRepays[i]);
        }
    }

    function getProtocolValues() external view returns (ProtocolValues memory) {
        return protocolValues;
    }

    function setProtocolValues(ProtocolValues memory _protocolValues) external {
        protocolValues = _protocolValues;
    }

    modifier onlyChild() {
        require(msg.sender = protocolContracts.userInteractions);
    }

    modifier onlyVault() {
        require(msg.sender = protocolContracts.eclypseVault);
    }




}