// SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

import "./interfaces/IUserInteractions.sol";

import "PositionsManagerGHO.sol";

import "@openzeppelin/contracts/access/Ownable.sol";

import "@uniswap-periphery/interfaces/INonfungiblePositionManager.sol";

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import {Errors} from "./utils/Errors.sol";

contract PositionsManagerMAI is Ownable, IUserInteractions, ReentrancyGuard {
    
    INonfungiblePositionManager internal uniswapV3NFPositionsManager;

    PositionsManagerGHO internal managerGHO;
    function initialize(address _uniPosNFT, address _PositionManagerAddress) external override onlyOwner {
        uniswapV3NFPositionsManager = INonfungiblePositionManager(_uniPosNFT);
        managerGHO = PositionsManagerGHO(_PositionManagerAddress);
        //renounceOwnership();
    }

    function openPosition(uint256 _tokenId) external {
        //TODO: Check that the position is not already initialized.
        managerGHO.openPosition(msg.sender, _tokenId);
    }

    function closePosition(uint256 _tokenId) external {
        //TODO: Check that the position is active.
        //TODO: Check that caller is owner.

        managerGHO.closePosition(msg.sender, _tokenId);
    }

    function borrow(uint256 _amount, uint256 _tokenId) public payable override nonReentrant {
        //TODO: Check that position is active.
        //TODO: Check that caller is owner.

        if (!(_amount > 0)) {
            revert Errors.AmountShouldBePositive();
        }

        managerGHO.borrow(msg.sender, _tokenId, _amount);
    }

    function repay(uint256 _amount, uint256 _tokenId) public override nonReentrant {
        //TODO: Check that position is active.
        //TODO: Check that caller is owner.

        if (_amount <= 0) {
            revert Errors.AmountShouldBePositive();
        }

        managerGHO.repay(msg.sender, _tokenId, _amount);
    }

    function deposit(uint256 _amount0, uint256 _amount1, uint256 _tokenId) public override nonReentrant 
    returns (uint128 liquidity, uint256 amount0, uint256 amoun1) {
        //TODO: Check that position is active.
        //TODO: Check that caller is owner.

        if (_amount0 <= 0 || _amount1 <= 0) {
            revert Errors.AmountShouldBePositive();
        }

        (liquidity, amount0, amount1) =
            managerGHO.increaseLiquidity(msg.sender, _tokenId, _amount0, _amount1);
    }
    
    function withdraw(uint256 _liquidity, uint256 _tokenId) public override nonReentrant 
    returns (uint256 amount0, uint256 amount1) {
        //TODO: Check that position is active.
        //TODO: Check that caller is owner.

        (amount0, amount1) = managerGHO.decreaseLiquidity(msg.sender, _tokenId, _liquidity);

        require(
            !managerGHO.liquidatable(_tokenId),
            "Collateral Ratio cannot be lower than the minimum collateral ratio."
        )
    }

}