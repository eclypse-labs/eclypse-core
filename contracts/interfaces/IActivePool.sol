// SPDX-License-Identifier: MIT

pragma solidity >=0.6.11;

import "./IPool.sol";
import "@uniswap-periphery/interfaces/INonfungiblePositionManager.sol";


interface IActivePool is IPool {
    // --- Events ---
    event BorrowerOperationsAddressChanged(address _newBorrowerOperationsAddress);
    event LPPositionsManagerAddressChanged(address _newLPPositionsManagerAddress);
    event GHOAddressChanged(address _newGHOAddress);
    event PositionMinted(uint256 _tokenId);
    event PositionBurned(uint256 _tokenId);
    event LiquidityIncreased(uint256 _tokenId, uint128 liquidity);
    event LiquidityDecreased(uint256 _tokenId, uint128 liquidity);
    event MintedSupplyUpdated(int256 _mintedSupply);
    event InterestRepaid(address _sender, uint256 _amount);
    event PositionSent(address _account, uint256 _tokenId);
    event TokenSent(address _token, address _account, uint256 _amount);

    // --- Functions ---

    function mintPosition(
        INonfungiblePositionManager.MintParams memory params
    ) external returns (uint256 tokenId);
    function sendPosition(address _account, uint256 _tokenId) external;
    function sendToken(address _token, address _account, uint256 _amount) external;
    
    function getMintedSupply() external view returns (uint256);
    function getMaxSupply() external view returns (uint256);

    function increaseMintedSupply(uint256 _amount, address sender) external;
    function decreaseMintedSupply(uint256 _amount, address sender) external;

    function feesOwed(INonfungiblePositionManager.CollectParams memory params) external returns (uint256 amount0, uint256 amount1);
    
    function burnPosition(uint256 _tokenId) external;
    
    function increaseLiquidity(
        address payer,
        uint256 tokenId,
        uint256 amountAdd0,
        uint256 amountAdd1
    )
        external
        returns (
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        );

    function decreaseLiquidity(uint256 _tokenId, uint128 _liquidityToRemove, address sender)
        external
        returns (uint256 amount0, uint256 amount1);

    function repayInterestFromUserToProtocol(address sender, uint256 amount) external;
}

