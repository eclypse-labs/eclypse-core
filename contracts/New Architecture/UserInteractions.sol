// SPDX-License-Identifier: MIT
pragma solidity <0.9.0;
import "./interfaces/IUserInteractions.sol";
import "PositionsManager.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap-periphery/interfaces/INonfungiblePositionManager.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Errors} from "./utils/Errors.sol";

/**
 * @title UserInteractions contract
 * @notice Contains the logic for position operations performed by users.
 * @dev The contract is owned by the Eclypse system, and serves as a link between the Frontend and the Backend.
 */
contract UserInteractions is Ownable, IUserInteractions, ReentrancyGuard {

    INonfungiblePositionManager internal uniswapV3NFPositionsManager;

    PositionsManager internal manager;

    /**
     * @notice Set the addresses of various contracts and emit events to indicate that these addresses have been modified.
     * @param _uniPosNFT The address of the uniswapV3 NonfungiblePositionManager contract.
     * @param _PositionManagerAddress The address of the PositionsManager contract.
     * @dev This function can only be called by the contract owner.
     */
    function initialize(address _uniPosNFT, address _PositionManagerAddress) external override onlyOwner {
        uniswapV3NFPositionsManager = INonfungiblePositionManager(_uniPosNFT);
        manager = PositionsManager(_PositionManagerAddress);
        //renounceOwnership();
    }

    /**
     * @notice Opens a new position.
     * @param _tokenId The ID of the Uniswap V3 NFT representing the position.
     * @param _asset The address of the asset which will be borrowed with this position.
     * @dev The caller must have approved the transfer of the Uniswap V3 NFT from their wallet to the BorrowerOperations contract.
     */
    function openPosition(uint256 _tokenId, address _asset) external {
        require(manager.getPosition(_tokenId).status = 0);
        manager.openPosition(msg.sender, _tokenId, _asset);
    }

    /**
     * @notice Closes a position.
     * @param _tokenId The ID of the Uniswap V3 NFT representing the position.
     */
    function closePosition(uint256 _tokenId) external {
        require(manager.getPosition(_tokenId).status = 1);
        require(manager.getPosition(_tokenId).user = msg.sender);
        manager.closePosition(msg.sender, _tokenId);
    }

    /**
     * @notice Borrow.
     * @param _amount The amount of stablecoin to withdraw.
     * @param _tokenId The ID of the Uniswap V3 NFT representing the position.
     */
    function borrow(uint256 _amount, uint256 _tokenId) public payable override nonReentrant {
        require(manager.getPosition(_tokenId).status = 1);
        require(manager.getPosition(_tokenId).user = msg.sender);

        if (!(_amount > 0)) {
            revert Errors.AmountShouldBePositive();
        }

        manager.borrow(msg.sender, _tokenId, _amount);
    }

    /**
     * @notice Repay.
     * @param _amount The amount of stablecoin to repay.
     * @param _tokenId The ID of the Uniswap V3 NFT representing the position.
     */
    function repay(uint256 _amount, uint256 _tokenId) public override nonReentrant {
        require(manager.getPosition(_tokenId).status = 1);
        require(manager.getPosition(_tokenId).user = msg.sender);

        if (_amount <= 0) {
            revert Errors.AmountShouldBePositive();
        }

        manager.repay(msg.sender, _tokenId, _amount);
    }

    /**
     * @notice Add collateral to a position.
     * @param _amount0 The amount of token0 to add.
     * @param _amount1 The amount of token1 to add.
     * @param _tokenId The ID of the Uniswap V3 NFT representing the position.
     * @return liquidity The amount of liquidity added.
     * @return amount0 The amount of token0 added.
     * @return amount1 The amount of token1 added.
     */
    function deposit(uint256 _amount0, uint256 _amount1, uint256 _tokenId) public override nonReentrant 
    returns (uint128 liquidity, uint256 amount0, uint256 amoun1) {
        require(manager.getPosition(_tokenId).status = 1);
        require(manager.getPosition(_tokenId).user = msg.sender);

        if (_amount0 <= 0 || _amount1 <= 0) {
            revert Errors.AmountShouldBePositive();
        }
        
        (liquidity, amount0, amount1) =
            manager.increaseLiquidity(msg.sender, _tokenId, _amount0, _amount1);
    }

    /**
     * @notice Remove collateral from a position.
     * @param _liquidity The amount of liquidity to remove.
     * @param _tokenId The ID of the Uniswap V3 NFT representing the position.
     * @return amount0 The amount of token0 removed.
     * @return amount1 The amount of token1 removed.
     */
    function withdraw(uint256 _liquidity, uint256 _tokenId) 
    public override nonReentrant returns(uint256 amount0, uint256 amount1) {

        require(manager.getPosition(_tokenId).status = 1);
        require(manager.getPosition(_tokenId).user = msg.sender);

        (amount0, amount1) = manager.decreaseLiquidity(msg.sender, _tokenId, _liquidity);

        require(!manager.liquidatable(_tokenId), "Collateral Ratio cannot be lower than the minimum collateral ratio.");

    }
    
}
