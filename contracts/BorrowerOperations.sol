// SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

import "./LPPositionsManager.sol";

import "./interfaces/IBorrowerOperations.sol";
import "contracts/utils/CheckContract.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap-periphery/interfaces/INonfungiblePositionManager.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import {Errors} from "./utils/Errors.sol";
import "./Eclypse.sol";

/**
 * @title BorrowerOperations contract
 * @notice Contains the logic for position operations performed by users.
 * @dev The contract is owned by the Eclypse system, and serves as a link between the Frontend and the Backend.
 */
contract BorrowerOperations is Ownable, CheckContract, IBorrowerOperations, ReentrancyGuard {
    // --- Addresses ---
    Eclypse private eclypse;

    //TODO: Comment next line
    GhoToken private GHO;

    // --- Interfaces ---
    INonfungiblePositionManager constant uniswapPositionsNFT =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

    // --- Data Structures ---
    /*struct ContractsCache {
        Eclypse eclypse;
        GhoToken GHO;
    }*/

    // --- Methods ---

    //-------------------------------------------------------------------------------------------------------------------------------------------------------//
    // Constructors
    //-------------------------------------------------------------------------------------------------------------------------------------------------------//

    /**
     * @notice Set the addresses of various contracts and emit events to indicate that these addresses have been modified.
     * @param _eclypse The address of the Eclypse contract.
     * @param _GhoAddress The address of the GHO token contract.
     * @dev This function can only be called by the contract owner.
     */
    function setAddresses(address _eclypse, address _GhoAddress) external onlyOwner {
        eclypse = Eclypse(_eclypse);
        GHO = GhoToken(_GhoAddress);

        emit GHOTokenAddressChanged(_GhoAddress);

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
    function openPosition(uint256 _tokenId) external positionNotInitiated(_tokenId) {
        uniswapPositionsNFT.transferFrom(msg.sender, address(eclypse), _tokenId);

        //TODO: create new debt token for this position in lpPositionManager.openPosition.

        eclypse.openPosition(msg.sender, _tokenId);
        emit OpenedPosition(msg.sender, _tokenId);
    }

    /**
     * @notice Closes a position.
     * @param _tokenId The ID of the Uniswap V3 NFT representing the position.
     * @dev The caller must have approved the transfer of the Uniswap V3 NFT from the BorrowerOperations contract to their wallet.
     */
    function closePosition(uint256 _tokenId)
        public
        onlyActivePosition(_tokenId)
        onlyPositionOwner(_tokenId, msg.sender)
    {
        eclypse.closePosition(msg.sender, _tokenId);
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
    function borrowGHO(uint256 _GHOAmount, uint256 _tokenId)
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

        // No need to check that, GHO checks that for us!
        /*if (!(activePool.getMintedSupply() + _GHOAmount <= activePool.getMaxSupply())) {
    revert Errors.SupplyNotAvailable();
    }*/

        eclypse.borrowGHO(msg.sender, _tokenId, _GHOAmount);
        if (eclypse.liquidatable(_tokenId)) {
            revert Errors.PositionILiquidatable();
        }
        //already done by increaseDebtOf
        //eclypse.increaseMintedSupply(_GHOAmount, msg.sender, _tokenId);

        emit WithdrawnGHO(msg.sender, _GHOAmount, _tokenId);
    }

    /**
     * @notice Repay GHO.
     * @param _GHOAmount The amount of GHO to repay.
     * @param _tokenId The ID of the Uniswap V3 NFT representing the position.
     */
    function repayGHO(uint256 _GHOAmount, uint256 _tokenId)
        public
        override
        nonReentrant
        onlyActivePosition(_tokenId)
        onlyPositionOwner(_tokenId, msg.sender)
    {
        _GHOAmount = Math.min(_GHOAmount, eclypse.debtOf(_tokenId));
        if (_GHOAmount <= 0) {
            revert Errors.AmountShouldBePositive();
        }
        // TODO: change the amount activepool pays back to the user /!\
        //eclypse.repayDebtFromUserToProtocol(msg.sender, _GHOAmount, _tokenId);
        eclypse.repayGHO(msg.sender, _tokenId, _GHOAmount);
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
    function addCollateral(uint256 tokenId, uint256 amountAdd0, uint256 amountAdd1)
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

        (liquidity, amount0, amount1) = eclypse.increaseLiquidity(msg.sender, tokenId, amountAdd0, amountAdd1);

        eclypse.setNewLiquidity(tokenId, eclypse.getPosition(tokenId).liquidity + liquidity);
        emit AddedCollateral(tokenId, liquidity, amount0, amount1);
    }

    /**
     * @notice Remove collateral from a position.
     * @param _tokenId The ID of the Uniswap V3 NFT representing the position.
     * @param _liquidityToRemove The amount of liquidity to remove.
     * @return amount0 The amount of token0 removed.
     * @return amount1 The amount of token1 removed.
     */
    //TODO manage to put the require before the call to decreaseLiquidity
    function removeCollateral(uint256 _tokenId, uint128 _liquidityToRemove)
        external
        nonReentrant
        onlyActivePosition(_tokenId)
        onlyPositionOwner(_tokenId, msg.sender)
        returns (uint256 amount0, uint256 amount1)
    {
        Eclypse.Position memory position = eclypse.getPosition(_tokenId);

        if (_liquidityToRemove > position.liquidity) {
            revert Errors.MustRemoveLessLiquidity(_liquidityToRemove, position.liquidity);
        }

        // Moved this here because it should be true **after** we account for the removal of liquidity, otherwise, the transaction reverts
        eclypse.decreaseLiquidity(_tokenId, _liquidityToRemove, msg.sender);

        require(!eclypse.liquidatable(_tokenId), "Collateral Ratio cannot be lower than the minimum collateral ratio.");

        // eclypse.decreaseLiquidity(_tokenId, _liquidityToRemove, msg.sender);

        // require(!eclypse.liquidatable(_tokenId), "Collateral Ratio cannot be lower than the minimum collateral ratio.");

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
        if (!(eclypse.getPosition(_tokenId).status == IEclypse.Status.active)) {
            revert Errors.PositionIsNotActiveOrIsClosed(_tokenId);
        }
        _;
    }

    modifier positionNotInitiated(uint256 _tokenId) {
        if ((eclypse.getPosition(_tokenId).status == IEclypse.Status.active)) {
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
        if (!(eclypse.getPosition(_tokenId).user == _user)) {
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
