// SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

import "./interfaces/IEclypseVault.sol";

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import "@uniswap-periphery/libraries/TransferHelper.sol";
import "@uniswap-core/libraries/FullMath.sol";

import "@openzeppelin/contracts/access/Ownable.sol";

contract EclypseVault is Ownable, IEclypseVault, IERC721Receiver {

    uint256 internal LIQUIDATION_FEES;

    string public constant NAME = "Eclypse Vault";

    INonfungiblePositionManager internal uniswapV3NFPositionsManager;

    address public positionsManagerAddress;
    address public borrowerAddress;


    modifier onlyManager() {
        require(msg.sender == positionsManagerAddress);
        _;
    }

    modifier onlyBorrower() {
        require(msg.sender == borrowerAddress);
        _;
    }

    /**
     * @notice Set the addresses of various contracts and emit events to indicate that these addresses have been modified.
     * @param _uniFactory The address of the Uniswap V3 factory contract.
     * @param _positionsManagerAddress The address of the PositionsManager contract.
     * @param _borrowerAddress The address of the userInteractions contract.
     * @dev This function can only be called by the contract owner.
     */
    function initialize(
        address _uniPosNFT,
        address _positionsManagerAddress,
        address _borrowerAddress
    ) external override onlyOwner {
        uniswapV3NFPositionsManager = INonfungiblePositionManager(_uniPosNFT);
        positionsManagerAddress = _positionsManagerAddress;
        borrowerAddress = _borrowerAddress;
        //renounceOwnership();
    }

    /**
     * @notice Performs a delegateCall on the borrowable asset contract's mint function.
     * @param _asset The address of the contract to call.
     * @param _sender The address which will receive the minted tokens.
     * @param _amount The amount of token to mint.
     */
    function mint(address _asset, address _sender, uint256 _amount) public override onlyManager {
        (bool _ok, ) = _asset.delegatecall(abi.encodeWithSignature("mint(address,uint256)", _sender, _amount));
    }

    /**
     * @notice Performs a delegateCall on the borrowable asset contract's burn function.
     * @param _asset The address of the contract to call.
     * @param _amount The amount of token to burn.
     */

    function burn(address _asset, uint256 _amount) public override onlyManager {
        (bool _ok, ) = _asset.delegatecall(abi.encodeWithSignature("burn(uint256)", _amount));
    }

    /**
     * @notice Increases the liquidity of an LP position.
     * @param _sender The address of the account that is increasing the liquidity of the LP position.
     * @param _tokenId The ID of the LP position to be increased.
     * @param _token0 The address of token 0
     * @param _token1 The address of token 1
     * @param _amountAdd0 The amount of token0 to be added to the LP position.
     * @param _amountAdd1 The amount of token1 to be added to the LP position.
     * @return liquidity The amount of liquidity added to the LP position.
     * @return amount0 The amount of token0 added to the LP position.
     * @return amount1 The amount of token1 added to the LP position.
     * @dev Only the PositionsManager contract can call this function.
     */
    function increaseLiquidity(
        address _sender,
        uint256 _tokenId,
        address _token0,
        address _token1,
        uint256 _amountAdd0,
        uint256 _amountAdd1
    ) public override onlyManager returns (uint128 liquidity, uint256 amount0, uint256 amount1) {
        TransferHelper.safeTransferFrom(_token0, _sender, address(this), _amountAdd0);
        TransferHelper.safeTransferFrom(_token1, _sender, address(this), _amountAdd1);

        TransferHelper.safeApprove(_token0, address(uniswapPositionsNFT), _amountAdd0);
        TransferHelper.safeApprove(_token1, address(uniswapPositionsNFT), _amountAdd1);

        (liquidity, amount0, amount1) = uniswapPositionsNFT.increaseLiquidity(
            INonfungiblePositionManager.IncreaseLiquidityParams({
                tokenId: _tokenId,
                amount0Desired: _amountAdd0,
                amount1Desired: _amountAdd1,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            })
        );

        if (_amount0 < _amountAdd0) {
            TransferHelper.safeTransfer(_token0, _sender, _amountAdd0 - _amount0);
        }
        if (_amount1 < _amountAdd1) {
            TransferHelper.safeTransfer(_token1, _sender, _amountAdd1 - _amount1);
        }

    }

    /**
     * @notice Decreases the liquidity of an LP position.
     * @param _sender The address of the position owner.
     * @param _tokenId The ID of the LP position to be decreased.
     * @param _liquidityToRemove The amount of liquidity to be removed from the LP position.
     * @return amount0 The amount of token0 removed from the LP position.
     * @return amount1 The amount of token1 removed from the LP position.
     * @dev Only the PositionsManager contract can call this function.
     */
    function decreaseLiquidity(
        address _sender, 
        uint256 _tokenId,
        uint128 _liquidityToRemove
    ) public override onlyManager returns (uint256 amount0, uint256 amount1){

        uniswapPositionsNFT.decreaseLiquidity(
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: _tokenId,
                liquidity: _liquidityToRemove,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            })
        );

        (amount0, amount1) = uniswapPositionsNFT.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: _tokenId,
                recipient: sender,
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );
    }

    /**
     * @notice Sends an Position to an account.
     * @param _to The address of the account that will receive the LP Position.
     * @param _tokenId The ID of the LP Position to be sent.
     * @dev Only the PositionsManager contract or the LP Positions Manager contract can call this function.
     */
    function transferPosition(address _to, uint256 _tokenId) public override onlyManager {
        uniswapV3NFPositionsManager.transferFrom(address(this), _to, _tokenId);
    }

   /**
     * @notice Returns the address of the contract that implements the IERC721Receiver interface.
     * @return selector The Selector of the IERC721Receiver interface.
     */
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

}