// SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

import "./LPPositionsManager.sol";

import "./interfaces/IBorrowerOperations.sol";
import "./interfaces/IGHOToken.sol";
import "src/liquity-dependencies/EclypseBase.sol";
import "src/liquity-dependencies/CheckContract.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap-periphery/interfaces/INonfungiblePositionManager.sol";

/**
 * @title BorrowerOperations contract
 * @notice Contains the logic for position operations performed by users.
 * @dev The contract is owned by the Eclypse system, and serves as a link between the Frontend and the Backend.
 */
contract BorrowerOperations is
    EclypseBase,
    Ownable,
    CheckContract,
    IBorrowerOperations
{
    // --- Addresses ---
    LPPositionsManager private lpPositionsManager;
    IGHOToken private GHOToken;

    //address stabilityPoolAddress;
    //address gasPoolAddress;

    // --- Interfaces ---
    INonfungiblePositionManager constant uniswapPositionsNFT =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

    // --- Data Structures ---
    struct ContractsCache {
        ILPPositionsManager lpPositionsManager;
        IActivePool activePool;
        IGHOToken GHOToken;
    }

    /*enum BorrowerOperation {
        openPosition,
        closePosition,
        adjustPosition
    }*/
    // Not used, commented it in case we need it in the future

    // --- Methods ---

    //-------------------------------------------------------------------------------------------------------------------------------------------------------//
    // Constructors
    //-------------------------------------------------------------------------------------------------------------------------------------------------------//

    /**
    * @notice Set the addresses of various contracts and emit events to indicate that these addresses have been modified.
     * @param _lpPositionsManagerAddress The address of the LPPositionsManager contract.
     * @param _activePoolAddress The address of the ActivePool contract.
     * @param _GHOTokenAddress The address of the GHOToken contract.
     * @dev This function can only be called by the contract owner.
     */
    function setAddresses(
        address _lpPositionsManagerAddress,
        address _activePoolAddress,
        //address _stabilityPoolAddress,
        //address _gasPoolAddress,
        address _GHOTokenAddress
    ) external onlyOwner {
        // This makes it impossible to open a trove with zero withdrawn GHO
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

    //-------------------------------------------------------------------------------------------------------------------------------------------------------//
    // Positions fundametals Operations
    //-------------------------------------------------------------------------------------------------------------------------------------------------------//

    /**
    * @notice Opens a new position.
    * @param _tokenId The ID of the Uniswap V3 NFT representing the position.
    * @dev The caller must have approved the transfer of the Uniswap V3 NFT from their wallet to the BorrowerOperations contract.
    */
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
        uint256 debt = lpPositionsManager.debtOf(_tokenId);

        if (debt > 0) repayGHO(debt, _tokenId); // try to repay all debt
        require(debt == 0, "Debt is not repaid."); // should be 0 or the tx would have reverted, but just in case

        // send LP to owner
        activePool.sendPosition(msg.sender, _tokenId);

        lpPositionsManager.changePositionStatus(
            _tokenId,
            ILPPositionsManager.Status.closedByOwner
        );
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
        onlyActivePosition(_tokenId)
        onlyPositionOwner(_tokenId, msg.sender)
    {
        require(_GHOAmount > 0, "Cannot withdraw 0 GHO.");
        require(activePool.getMintedSupply() + _GHOAmount <= activePool.getMaxSupply() , "Supply not available.");
        lpPositionsManager.increaseDebtOf(_tokenId, _GHOAmount);
        require(!lpPositionsManager.liquidatable(_tokenId));
        emit WithdrawnGHO(msg.sender, _GHOAmount, _tokenId, block.timestamp);
    }

    /**
     * @notice Repay GHO.
     * @param _GHOAmount The amount of GHO to repay.
     * @param _tokenId The ID of the Uniswap V3 NFT representing the position.
     */
    function repayGHO(uint256 _GHOAmount, uint256 _tokenId)
        public
        override
        onlyActivePosition(_tokenId)
    {
        _GHOAmount = Math.min(_GHOAmount, lpPositionsManager.debtOf(_tokenId));
        require(_GHOAmount > 0, "Cannot repay 0 GHO.");

        uint256 GHOfees = lpPositionsManager.decreaseDebtOf(_tokenId, _GHOAmount);
        // console.log("GHO Fees:", GHOfees);
        // console.log("Balance GHO:", GHOToken.balanceOf(msg.sender));
        // GHOToken.approve(address(activePool), GHOfees);
        // console.log("Allowance:", GHOToken.allowance(msg.sender, address(activePool)));
        // activePool.repayInterestFromUserToProtocol(msg.sender, GHOfees);

        //emit RepaidGHO(msg.sender, _GHOAmount, _tokenId, block.timestamp);
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
        onlyActivePosition(tokenId)
        returns (
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {

        require(
            amountAdd0 > 0 || amountAdd1 > 0,
            "Cannot add 0 liquidity."
        );

        (liquidity, amount0, amount1) = activePool.increaseLiquidity(
            msg.sender,
            tokenId,
            amountAdd0,
            amountAdd1
        );

        lpPositionsManager.setNewLiquidity(tokenId, liquidity);
    }

    /**
     * @notice Remove collateral from a position.
     * @param _tokenId The ID of the Uniswap V3 NFT representing the position.
     * @param _liquidityToRemove The amount of liquidity to remove.
     * @return amount0 The amount of token0 removed.
     * @return amount1 The amount of token1 removed.
     */
    function removeCollateral(uint256 _tokenId, uint128 _liquidityToRemove)
        external
        onlyActivePosition(_tokenId)
        onlyPositionOwner(_tokenId, msg.sender)
        returns (uint256 amount0, uint256 amount1)
    {
        LPPositionsManager.Position memory position = lpPositionsManager
            .getPosition(_tokenId);
        
        require(
            _liquidityToRemove <= position.liquidity,
            "You can't remove more liquidity than you have"
        );

        // Moved this here because it should be true **after** we account for the removal of liquidity, otherwise, the transaction reverts
        require(
            !lpPositionsManager.liquidatable(_tokenId),
            "Collateral Ratio cannot be lower than the minimum collateral ratio."
        );

        activePool.decreaseLiquidity(_tokenId, _liquidityToRemove, msg.sender);

        require(
            !lpPositionsManager.liquidatable(_tokenId),
            "Collateral Ratio cannot be lower than the minimum collateral ratio."
        );

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
        require(
            lpPositionsManager.getPosition(_tokenId).status ==
                ILPPositionsManager.Status.active,
            "Position does not exist or is closed"
        );
        _;
    }

    /**
     * @notice Check if the user is the owner of the position.
     * @param _tokenId The ID of the Uniswap V3 NFT representing the position.
     * @param _user The address of the user.
     */
    modifier onlyPositionOwner(uint256 _tokenId, address _user) {
        require(
            lpPositionsManager.getPosition(_tokenId).user == _user,
            "You are not the owner of this position."
        );
        _;
    }
}
