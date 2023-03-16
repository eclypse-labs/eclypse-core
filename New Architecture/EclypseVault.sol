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

    mapping(uint256 => address) internal childrens;

    uint256 internal childrensCount;

    INonfungiblePositionManager internal uniswapV3NFPositionsManager;


    modifier onlyChildren() {
        bool isChildren = false;
        for (int i = 0 ; i < childrensCount ; ++i) {
            if(msg.sender == childrens[i]){
                isChildren = true;
            }
        }
        require(isChildren);
    }

    function initialize(
        address _uniPosNFT
    ) external override onlyOwner {
        uniswapV3NFPositionsManager = INonfungiblePositionManager(_uniPosNFT);
        //renounceOwnership();
    }

    function addChildren(address _children) public override onlyOwner {
        children[childrensCount] = _children;
        childrensCount++;
    }

    function mint(address _caller, address _sender, uint256 _amount) public override onlyChildren {
        (bool _ok, ) = _caller.delegatecall(abi.encodeWithSignature("mint(address,uint256)", _sender, _amount));
    }

    function burn(address _caller, uint256 _amount) public override onlyChildren {
        (bool _ok, ) = _caller.delegatecall(abi.encodeWithSignature("burn(uint256)", _amount));
    }

    function increaseLiquidity(
        address _sender,
        uint256 _tokenId,
        address _token0,
        address _token1,
        uint256 _amountAdd0,
        uint256 _amountAdd1
    ) public override onlyChildren returns (uint128 liquidity, uint256 amount0, uint256 amount1) {
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

    function decreaseLiquidity(
        address _sender, 
        uint256 _tokenId,
        uint128 _liquidityToRemove
    ) public override onlyChildren returns (uint256 amount0, uint256 amount1){

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

    function transferPosition(address _to, uint256 _tokenId) public override onlyChildren {
        uniswapV3NFPositionsManager.transferFrom(address(this), _to, _tokenId);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

}