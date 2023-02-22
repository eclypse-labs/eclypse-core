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
    event MintedSupplyUpdated(uint256 _mintedSupply);
    event InterestRepaid(address _sender, uint256 _amount);
    event PositionSent(address _account, uint256 _tokenId);
    event TokenSent(address _token, address _account, uint256 _amount);

    // --- Functions ---

    function setAddresses(address _borrowerOperationsAddress, address _lpPositionsManagerAddress, address _GhoAddress)
        external;

    function getMintedSupply() external view returns (uint256);

    function getMaxSupply() external view returns (uint256);

    function feesOwed(INonfungiblePositionManager.CollectParams memory params)
        external
        returns (uint256 amount0, uint256 amount1);

    function mintPosition(INonfungiblePositionManager.MintParams memory params) external returns (uint256 tokenId);

    function burnPosition(uint256 _tokenId) external;

    function increaseLiquidity(address payer, uint256 tokenId, uint256 amountAdd0, uint256 amountAdd1)
        external
        returns (uint128 liquidity, uint256 amount0, uint256 amount1);

    function decreaseLiquidity(uint256 _tokenId, uint128 _liquidityToRemove, address sender)
        external
        returns (uint256 amount0, uint256 amount1);

    function increaseMintedSupply(uint256 _amount, address sender, uint256 tokenId) external;

    function decreaseMintedSupply(uint256 _amount, address sender) external;

    function repayDebtFromUserToProtocol(address sender, uint256 amount, uint256 tokenId) external;

    function sendPosition(address _account, uint256 _tokenId) external;
    //function sendToken(address _token, address _account, uint256 _amount) external;
}
