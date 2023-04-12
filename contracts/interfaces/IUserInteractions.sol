// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IUserInteractions {

    event Initialized(address _PositionManagerAddress);

    event OpenedPosition(address _borrower, uint256 _tokenId);
    event ClosedPosition(address _borrower, uint256 _tokenId);

    event BorrowedStableCoin(uint256 _amount, uint256 _tokenId);
    event RepaidStableCoin(uint256 _amount, uint256 _tokenId);
    event DepositedCollateral(uint128 _liquidity, uint256 _tokenId);
    event WithdrawnCollateral(uint256 _amount0, uint256 _amount1, uint256 _tokenId);


    function initialize(address _uniPosNFT, address _PositionManagerAddress) external;

    function openPosition(uint256 _tokenId, address _asset) external;

    function closePosition(uint256 _tokenId) external;

    function borrow(uint256 _amount, uint256 _tokenId) external;

    function repay(uint256 _amount, uint256 _tokenId) external;

    function deposit(uint256 _amount0, uint256 _amount1, uint256 _tokenId) 
        external 
        returns (uint128 liquidity, uint256 amount0, uint256 amoun1);
    
    function withdraw(uint128 _liquidity, uint256 _tokenId)
        external
        returns (uint256 amount0, uint256 amount1);

}