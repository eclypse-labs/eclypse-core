// SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

import "./LPPositionsManager.sol";

import "./interfaces/IBorrowerOperations.sol";
import "./DebtToken.sol";
import "contracts/utils/CheckContract.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap-periphery/interfaces/INonfungiblePositionManager.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
//import "@oppenzeppelin/contracts/token/ERC721/IERC721.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import {Errors} from "./utils/Errors.sol";

/**
 * @title BorrowerOperations contract
 * @notice Contains the logic for position operations performed by users.
 * @dev The contract is owned by the Eclypse system, and serves as a link between the Frontend and the Backend.
 */
contract BorrowerOperations is
    Ownable,
    CheckContract,
    IBorrowerOperations,
    ReentrancyGuard
{
    // --- Addresses ---
    IActivePool private activePool;
    LPPositionsManager private lpPositionsManager;

    //TODO: Comment next line
    //IGHOToken private GHOToken;

    // --- Interfaces ---
    INonfungiblePositionManager constant uniswapPositionsNFT =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

    // --- Data Structures ---
    struct ContractsCache {
        ILPPositionsManager lpPositionsManager;
        IActivePool activePool;

        //TODO: Comment next line
        //IGHOToken GHOToken;
    }

    // --- Methods ---

    //-------------------------------------------------------------------------------------------------------------------------------------------------------//
    // Constructors
    //-------------------------------------------------------------------------------------------------------------------------------------------------------//

    /**
     * @notice Set the addresses of various contracts and emit events to indicate that these addresses have been modified.
     * @param _lpPositionsManagerAddress The address of the LPPositionsManager contract.
     * @param _activePoolAddress The address of the ActivePool contract.
     * @dev This function can only be called by the contract owner.
     */
    function setAddresses(
        address _lpPositionsManagerAddress,
        address _activePoolAddress

        //TODO: Comment next line
        //address _GHOTokenAddress
    ) external onlyOwner {
        lpPositionsManager = LPPositionsManager(_lpPositionsManagerAddress);
        activePool = IActivePool(_activePoolAddress);

        //TODO: Comment next line
        //GHOToken = IGHOToken(_GHOTokenAddress);

        emit LPPositionsManagerAddressChanged(_lpPositionsManagerAddress);
        emit ActivePoolAddressChanged(_activePoolAddress);

        //TODO: Comment next line
        //emit GHOTokenAddressChanged(_GHOTokenAddress);

        //renounceOwnership();
    }

    //-------------------------------------------------------------------------------------------------------------------------------------------------------//
    // Positions fundametals Operations
    //-------------------------------------------------------------------------------------------------------------------------------------------------------//

    /**
     * @notice Opens a new position.
     * @param _tokenId The ID of the Uniswap V3 NFT representing the position.
     * @dev The caller must have approved the transfer of the Uniswap V3 NFT from their wallet to the BorrowerOperations contract.
     */
    function openPosition(
        uint256 _tokenId
    ) external positionNotInitiated(_tokenId) {
        uniswapPositionsNFT.transferFrom(
            msg.sender,
            address(activePool),
            _tokenId
        );

        //TODO: create new debt token for this position in lpPositionManager.openPosition.

        ContractsCache memory contractsCache = ContractsCache(
            lpPositionsManager,
            activePool
            //TODO: Comment next line
            //GHOToken
        );
        contractsCache.lpPositionsManager.openPosition(msg.sender, _tokenId);
        emit OpenedPosition(msg.sender, _tokenId);
    }

    /**
     * @notice Closes a position.
     * @param _tokenId The ID of the Uniswap V3 NFT representing the position.
     * @dev The caller must have approved the transfer of the Uniswap V3 NFT from the BorrowerOperations contract to their wallet.
     */
    function closePosition(
        uint256 _tokenId
    )
        public
        onlyActivePosition(_tokenId)
        onlyPositionOwner(_tokenId, msg.sender)
    {
        uint256 debt = lpPositionsManager.debtOf(_tokenId);

        if (!(debt == 0)) {
            revert Errors.DebtIsNotPaid(debt);
        }

        activePool.sendPosition(msg.sender, _tokenId);

        lpPositionsManager.changePositionStatus(
            _tokenId,
            ILPPositionsManager.Status.closedByOwner
        );
        emit ClosedPosition(msg.sender, _tokenId);
    }

    //-------------------------------------------------------------------------------------------------------------------------------------------------------//
    // Debt Operations
    //-------------------------------------------------------------------------------------------------------------------------------------------------------//

    /**
     * @notice Borrow GHO.
     * @param _GHOAmount The amount of GHO to withdraw.
     * @param _tokenId The ID of the Uniswap V3 NFT representing the position.
     */
    function borrowGHO(
        uint256 _GHOAmount,
        uint256 _tokenId
    )
        public
        payable
        override
        nonReentrant
        onlyActivePosition(_tokenId)
        onlyPositionOwner(_tokenId, msg.sender)
    {
        if (!(_GHOAmount > 0)) {
            revert Errors.AmountShouldBePositive();
        }

        if (
            !(activePool.getMintedSupply() + _GHOAmount <=
                activePool.getMaxSupply())
        ) {
            revert Errors.SupplyNotAvailable();
        }
        
        activePool.increaseMintedSupply(_GHOAmount, msg.sender, _tokenId);

        //TODO: Comment next line.
        //lpPositionsManager.increaseDebtOf(_tokenId, _GHOAmount);

        if (lpPositionsManager.liquidatable(_tokenId)) {
            revert Errors.PositionILiquidatable();
        }
        emit WithdrawnGHO(msg.sender, _GHOAmount, _tokenId);
    }

    /**
     * @notice Repay GHO.
     * @param _GHOAmount The amount of GHO to repay.
     * @param _tokenId The ID of the Uniswap V3 NFT representing the position.
     */
    function repayGHO(
        uint256 _GHOAmount,
        uint256 _tokenId
    )
        public
        override
        nonReentrant
        onlyActivePosition(_tokenId)
        onlyPositionOwner(_tokenId, msg.sender)
    {
        //_GHOAmount = Math.min(_GHOAmount, lpPositionsManager.debtOf(_tokenId));
        if (_GHOAmount > lpPositionsManager.debtOf(_tokenId)) {
            revert Errors.CannotRepayMoreThanDebt(
                _GHOAmount,
                lpPositionsManager.debtOf(_tokenId)
            );
        }
        if (_GHOAmount <= 0) {
            revert Errors.AmountShouldBePositive();
        }

        uint256 feesGeneratedByInterests = activePool.getDebtToken(_tokenId).balanceOfInterest();

        if (_GHOAmount >= feesGeneratedByInterests) {
            activePool.repayInterestFromUserToProtocol(
                msg.sender,
                feesGeneratedByInterests,
                _tokenId
            );

            activePool.burnDebtToken(_tokenId, _GHOAmount - feesGeneratedByInterests);

            //TODO: Decrease remaining minted supply.
            
        }
        else {
            activePool.repayInterestFromUserToProtocol(
                msg.sender,
                _GHOAmount,
                _tokenId
            );
        }

        emit RepaidGHO(msg.sender, _GHOAmount, _tokenId);
    }

    //-------------------------------------------------------------------------------------------------------------------------------------------------------//
    // LP Positions Operations
    //-------------------------------------------------------------------------------------------------------------------------------------------------------//

    // TODO : add verification of amount0 and amount1 regarding LP specifications
    // current implementation does not work
    /**
     * @notice Add collateral to a position.
     * @param tokenId The ID of the Uniswap V3 NFT representing the position.
     * @param amountAdd0 The amount of token0 to add.
     * @param amountAdd1 The amount of token1 to add.
     * @return liquidity The amount of liquidity added.
     * @return amount0 The amount of token0 added.
     * @return amount1 The amount of token1 added.
     */
    function addCollateral(
        uint256 tokenId,
        uint256 amountAdd0,
        uint256 amountAdd1
    )
        external
        override
        nonReentrant
        onlyActivePosition(tokenId)
        onlyPositionOwner(tokenId, msg.sender)
        returns (uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        if (amountAdd0 <= 0 || amountAdd1 <= 0) {
            revert Errors.AmountShouldBePositive();
        }

        (liquidity, amount0, amount1) = activePool.increaseLiquidity(
            msg.sender,
            tokenId,
            amountAdd0,
            amountAdd1
        );

        lpPositionsManager.setNewLiquidity(
            tokenId,
            lpPositionsManager.getPosition(tokenId).liquidity + liquidity
        );
        emit AddedCollateral(tokenId, liquidity, amount0, amount1);
    }

    /**
     * @notice Remove collateral from a position.
     * @param _tokenId The ID of the Uniswap V3 NFT representing the position.
     * @param _liquidityToRemove The amount of liquidity to remove.
     * @return amount0 The amount of token0 removed.
     * @return amount1 The amount of token1 removed.
     */
    function removeCollateral(
        uint256 _tokenId,
        uint128 _liquidityToRemove
    )
        external
        nonReentrant
        onlyActivePosition(_tokenId)
        onlyPositionOwner(_tokenId, msg.sender)
        returns (uint256 amount0, uint256 amount1)
    {
        LPPositionsManager.Position memory position = lpPositionsManager
            .getPosition(_tokenId);

        if (_liquidityToRemove > position.liquidity) {
            revert Errors.MustRemoveLessLiquidity(
                _liquidityToRemove,
                position.liquidity
            );
        }

        // Moved this here because it should be true **after** we account for the removal of liquidity, otherwise, the transaction reverts
        activePool.decreaseLiquidity(_tokenId, _liquidityToRemove, msg.sender);

        require(
            !lpPositionsManager.liquidatable(_tokenId),
            "Collateral Ratio cannot be lower than the minimum collateral ratio."
        );

        activePool.decreaseLiquidity(_tokenId, _liquidityToRemove, msg.sender);

        require(
            !lpPositionsManager.liquidatable(_tokenId),
            "Collateral Ratio cannot be lower than the minimum collateral ratio."
        );

        emit RemovedCollateral(_tokenId, _liquidityToRemove, amount0, amount1);

        return (amount0, amount1);
    }

    // /**
    //  * @notice Change the tick range of a position.
    //  * @param _tokenId The ID of the Uniswap V3 NFT representing the position.
    //  * @param _newMinTick The new minimum tick.
    //  * @param _newMaxTick The new maximum tick.
    //  * @return _newTokenId The ID of the new Uniswap V3 NFT representing the position.
    //  */
    // function changeTick(
    //     uint256 _tokenId,
    //     int24 _newMinTick,
    //     int24 _newMaxTick
    // )
    //     public
    //     payable
    //     onlyPositionOwner(_tokenId, msg.sender)
    //     onlyActivePosition(_tokenId)
    //     onlyPositionOwner(_tokenId, msg.sender)
    //     returns (uint256 _newTokenId)
    // {
    //     _newTokenId = lpPositionsManager._changeTicks(_tokenId, _newMinTick, _newMaxTick);
    // }

    //-------------------------------------------------------------------------------------------------------------------------------------------------------//
    // Modifiers and Require functions
    //-------------------------------------------------------------------------------------------------------------------------------------------------------//

    /**
     * @notice Check if the position is active.
     * @param _tokenId The ID of the Uniswap V3 NFT representing the position.
     */
    modifier onlyActivePosition(uint256 _tokenId) {
        if (
            !(lpPositionsManager.getPosition(_tokenId).status ==
                ILPPositionsManager.Status.active)
        ) {
            revert Errors.PositionIsNotActiveOrIsClosed(_tokenId);
        }
        _;
    }

    modifier positionNotInitiated(uint256 _tokenId) {
        if (
            (lpPositionsManager.getPosition(_tokenId).status ==
                ILPPositionsManager.Status.active)
        ) {
            revert Errors.PositionIsAlreadyActive(_tokenId);
        }
        _;
    }

    /**
     * @notice Check if the user is the owner of the position.
     * @param _tokenId The ID of the Uniswap V3 NFT representing the position.
     * @param _user The address of the user.
     */
    modifier onlyPositionOwner(uint256 _tokenId, address _user) {
        if (!(lpPositionsManager.getPosition(_tokenId).user == _user)) {
            revert Errors.NotOwnerOfPosition(_tokenId);
        }
        _;
    }

    // modifier notOwnerOfTokenId(uint256 _tokenId, address _user) {
    //     if (ERC721.ownerOf(_tokenId) != _user) {
    //         revert Errors.NotOwnerOfTokenId();
    //     }
    // }
}
