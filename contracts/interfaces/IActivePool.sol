// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

import "./IPool.sol";
import "@uniswap-periphery/interfaces/INonfungiblePositionManager.sol";

interface IActivePool /*is IPool*/ {
    // --- Events ---
    event LPPositionsManagerAddressChanged(address _newLPPositionsManagerAddress);
    event PositionMinted(uint256 _tokenId);
    event PositionBurned(uint256 _tokenId);
    event LiquidityIncreased(uint256 _tokenId, uint128 liquidity);
    event LiquidityDecreased(uint256 _tokenId, uint128 liquidity);
    event MintedSupplyUpdated(address stableCoinAddr, uint256 _mintedSupply);
    event InterestRepaid(address _sender, uint256 _amount);
    event PositionSent(address _account, uint256 _tokenId);
    event TokenSent(address _token, address _account, uint256 _amount);

    // --- Functions ---

    function setAddresses(address _lpPositionsManagerAddress) external;

    //function getMintedSupply() external view returns (uint256);
    //function getMaxSupply() external view returns (uint256);
    function feesOwed(INonfungiblePositionManager.CollectParams memory params)
        external
        returns (uint256 amount0, uint256 amount1);

    //function mintPosition(INonfungiblePositionManager.MintParams memory params) external returns (uint256 tokenId);

    //function burnPosition(uint256 _tokenId) external;

    function increaseLiquidity(
        address sender,
        uint256 _tokenId,
        address token0,
        address token1,
        uint256 amountAdd0,
        uint256 amountAdd1
    ) external returns (uint128 liquidity, uint256 amount0, uint256 amount1);
    function decreaseLiquidity(address sender, uint256 _tokenId, uint128 _liquidityToRemove)
        external
        returns (uint256 amount0, uint256 amount1);

    function mint(address sender, uint256 _amount, address stableCoinAddr) external;
    function burn(uint256 _amount, address stableCoinAddr) external;

    //function repayDebtFromUserToProtocol(address sender, uint256 amount, uint256 tokenId) external;

    function sendPosition(address _account, uint256 _tokenId) external;
    //function sendToken(address _token, address _account, uint256 _amount) external;
}
