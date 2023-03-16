// SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

import "./interfaces/IUserInteractions.sol";

import "PositionsManager.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "@uniswap-periphery/interfaces/INonfungiblePositionManager.sol";


import "@openzeppelin/contracts/security/ReentrancyGuard.sol";


import {Errors} from "./utils/Errors.sol";

contract UserInteractions is Ownable, IUserInteractions, ReentrancyGuard {

    INonfungiblePositionManager internal uniswapV3NFPositionsManager;

    PositionsManager internal manager;

    function initialize(address _uniPosNFT, address _PositionManagerAddress) external override onlyOwner {
        uniswapV3NFPositionsManager = INonfungiblePositionManager(_uniPosNFT);
        manager = PositionsManager(_PositionManagerAddress);
        //renounceOwnership();
    }

    function openPosition(uint256 _tokenId, address _asset) external {
        require(manager.getPosition(_tokenId).status = 0);
        manager.openPosition(msg.sender, _tokenId, _asset);
    }

    function closePosition(uint256 _tokenId) external {
        require(manager.getPosition(_tokenId).status = 1);
        require(manager.getPosition(_tokenId).user = msg.sender);
        manager.closePosition(msg.sender, _tokenId);
    }

    function borrow(uint256 _amount, uint256 _tokenId) public payable override nonReentrant {
        require(manager.getPosition(_tokenId).status = 1);
        require(manager.getPosition(_tokenId).user = msg.sender);

        if (!(_amount > 0)) {
            revert Errors.AmountShouldBePositive();
        }

        manager.borrow(msg.sender, _tokenId, _amount);
    }

    function repay(uint256 _amount, uint256 _tokenId) public override nonReentrant {
        require(manager.getPosition(_tokenId).status = 1);
        require(manager.getPosition(_tokenId).user = msg.sender);

        if (_amount <= 0) {
            revert Errors.AmountShouldBePositive();
        }

        manager.repay(msg.sender, _tokenId, _amount);
    }

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

    function withdraw(uint256 _liquidity, uint256 _tokenId) 
    public override nonReentrant returns(uint256 amount0, uint256 amount1) {

        require(manager.getPosition(_tokenId).status = 1);
        require(manager.getPosition(_tokenId).user = msg.sender);

        (amount0, amount1) = manager.decreaseLiquidity(msg.sender, _tokenId, _liquidity);

        require(!manager.liquidatable(_tokenId), "Collateral Ratio cannot be lower than the minimum collateral ratio.");

    }
    
}
