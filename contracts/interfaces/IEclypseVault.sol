// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IPositionsManager.sol";

import "@uniswap-periphery/interfaces/INonfungiblePositionManager.sol";

interface IEclypseVault {

    function initialize(
        address _uniPosNFT,
        address _positionsManagerAddress
    ) external;

    //function addChildren(address _children) external;

    function mint(address _caller, address _sender, uint256 _amount) external returns (bool _ok);
    function burn(address _caller, uint256 _amount) external returns (bool _ok);

    function increaseLiquidity(
        address _sender,
        uint256 _tokenId,
        address _token0,
        address _token1,
        uint256 _amountAdd0,
        uint256 _amountAdd1
    ) external returns (uint128 liquidity, uint256 amount0, uint256 amount1);

    function decreaseLiquidity(
        address _sender, 
        uint256 _tokenId,
        uint128 _liquidityToRemove
    ) external returns (uint256 amount0, uint256 amount1);

    function transferPosition(address _to, uint256 _tokenId) external;

    function updateTicks(
        address _sender,
        uint256 _tokenId,
        int24 _newLowerTick,
        int24 _newUpperTick,
        IPositionsManager.Position memory _position
    ) external returns (uint256 newTokenId, uint128 newLiquidity);
}