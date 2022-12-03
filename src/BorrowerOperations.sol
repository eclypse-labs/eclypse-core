// SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

import "./LPPositionsManager.sol";

import "./interfaces/IBorrowerOperations.sol";
import "./interfaces/IGHOToken.sol";
import "src/liquity-dependencies/EclypseBase.sol";
import "src/liquity-dependencies/CheckContract.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap-periphery/interfaces/INonfungiblePositionManager.sol";

contract BorrowerOperations is
    EclypseBase,
    Ownable,
    CheckContract,
    IBorrowerOperations
{
    using SafeMath for uint256;

    LPPositionsManager private lpPositionsManager;
    IGHOToken private GHOToken;

    //address stabilityPoolAddress;
    //address gasPoolAddress;

    INonfungiblePositionManager constant uniswapPositionsNFT =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

    struct ContractsCache {
        ILPPositionsManager lpPositionsManager;
        IActivePool activePool;
        IGHOToken GHOToken;
    }

    enum BorrowerOperation {
        openPosition,
        closePosition,
        adjustPosition
    }

    function setAddresses(
        address _lpPositionsManagerAddress,
        address _activePoolAddress,
        //address _stabilityPoolAddress,
        //address _gasPoolAddress,
        address _GHOTokenAddress
    ) external onlyOwner {
        // This makes impossible to open a trove with zero withdrawn GHO
        assert(MIN_NET_DEBT > 0);

        lpPositionsManager = LPPositionsManager(_lpPositionsManagerAddress);
        activePool = IActivePool(_activePoolAddress);
        //stabilityPoolAddress = _stabilityPoolAddress;
        //gasPoolAddress = _gasPoolAddress;
        GHOToken = IGHOToken(_GHOTokenAddress);

        emit LPPositionsManagerAddressChanged(_lpPositionsManagerAddress);
        emit ActivePoolAddressChanged(_activePoolAddress);
        //emit StabilityPoolAddressChanged(_stabilityPoolAddress);
        //emit GasPoolAddressChanged(_gasPoolAddress);
        emit GHOTokenAddressChanged(_GHOTokenAddress);

        renounceOwnership();
    }

    // --- Borrower Position Operations ---

    function openPosition(uint256 _tokenId) external override {
        uniswapPositionsNFT.transferFrom(
            msg.sender,
            address(activePool),
            _tokenId
        );

        ContractsCache memory contractsCache = ContractsCache(
            lpPositionsManager,
            activePool,
            GHOToken
        );
        contractsCache.lpPositionsManager.openPosition(msg.sender, _tokenId);
    }

    function closePosition(uint256 _tokenId) public {
        lpPositionsManager._requirePositionIsActive(_tokenId);
        ILPPositionsManager.Position memory position = lpPositionsManager
            .getPosition(_tokenId);

        require(
            position.user == msg.sender,
            "You are not the owner of this position."
        );
        require(position.debt == 0, "you have to repay your debt");

        // send LP to owner
        activePool.sendLp(msg.sender, _tokenId);

        lpPositionsManager.changePositionStatus(
            _tokenId,
            ILPPositionsManager.Status.closedByOwner
        );
    }

    function borrowGHO(uint256 _GHOAmount, uint256 _tokenId)
        external
        payable
        override
    {
        ILPPositionsManager.Position memory position = lpPositionsManager
            .getPosition(_tokenId);
        require(
            position.user == msg.sender,
            "You are not the owner of this position."
        );

        lpPositionsManager._requirePositionIsActive(_tokenId);

        require(_GHOAmount > 0, "Cannot withdraw 0 GHO.");

        lpPositionsManager.increaseDebtOf(_tokenId, _GHOAmount);
        //Check whether the user's collateral is enough to withdraw _GHOAmount GHO.
        require(!lpPositionsManager.liquidatable(_tokenId));

        GHOToken.mint(msg.sender, _GHOAmount);

        emit WithdrawnGHO(msg.sender, _GHOAmount, block.timestamp);
    }

    function repayGHO(uint256 _GHOAmount, uint256 _tokenId)
        external
        payable
        override
    {
        require(_GHOAmount > 0, "Cannot repay 0 GHO.");
        ILPPositionsManager.Position memory position = lpPositionsManager
            .getPosition(_tokenId);
        require(
            position.user == msg.sender,
            "You are not the owner of this position."
        );

        lpPositionsManager._requirePositionIsActive(_tokenId);

        require(
            _GHOAmount <= position.debt,
            "Cannot repay more GHO than the position's debt."
        );
        GHOToken.burn(msg.sender, _GHOAmount);
        lpPositionsManager.decreaseDebtOf(_tokenId, _GHOAmount);
        emit RepaidGHO(msg.sender, _GHOAmount, block.timestamp);
    }

    // TODO : add verficiation of amount0 and amount1 regarding LP specifications
    // current implementation does not work
    function addCollateral(
        uint256 tokenId,
        uint256 amountAdd0,
        uint256 amountAdd1
    )
        external
        override
        returns (
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {
        (liquidity, amount0, amount1) = activePool.increaseLiquidity(
            tokenId,
            amountAdd0,
            amountAdd1
        );
        lpPositionsManager.setNewLiquidity(tokenId, liquidity);
    }

    function removeCollateral(uint256 _tokenId, uint128 _liquidityToRemove)
        external
        override
        returns (uint256 amount0, uint256 amount1)
    {
        lpPositionsManager._requirePositionIsActive(_tokenId);

        LPPositionsManager.Position memory position = lpPositionsManager
            .getPosition(_tokenId);

        require(
            msg.sender == position.user,
            "You are not the owner of this position."
        );
        require(
            _liquidityToRemove <= position.liquidity,
            "You can't remove more liquidity than you have"
        );

        lpPositionsManager.setNewLiquidity(
            _tokenId,
            position.liquidity - _liquidityToRemove
        );

        // Moved this here because it should be true **after** we account for the removal of liquidity, otherwise, the transaction reverts
        require(
            !lpPositionsManager.liquidatable(_tokenId),
            "Collateral Ratio cannot be lower than the minimum collateral ratio."
        );

        activePool.removeLiquidity(_tokenId, _liquidityToRemove);

        return (amount0, amount1);
    }

    function changeTick(
        uint256 _tokenId,
        int24 _newMinTick,
        int24 _newMaxTick
    ) public payable {
        lpPositionsManager._checkOwnership(_tokenId, msg.sender);
        lpPositionsManager._requirePositionIsActive(_tokenId);
        lpPositionsManager._changeTicks(_tokenId, _newMinTick, _newMaxTick);
    }
}
