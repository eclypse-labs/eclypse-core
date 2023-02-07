// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library Errors {
    error ZeroAddress();
    error InsufficientBalance(uint256 balance, uint256 amount);
    error InsufficientAllowance(uint256 allowance, uint256 amount); //pas besoin, revert automatique?
    error InsufficientSupply(uint256 supply, uint256 amount);
    error InsufficientTotalSupply(uint256 totalSupply, uint256 amount);
    error PositionIsNotActiveOrIsClosed(uint256 _tokenId);

    //for modifiers
    error PositionIsAlreadyActive(uint256 _tokenId);
    error NotOwnerOfPosition(uint256 _tokenId);
    error NotOwnerOfTokenId();


    error AmountShouldBePositive();
    error PositionILiquidatable();

    //borrowGHO
    error SupplyNotAvailable();

    //repayGHO
    error CannotRepayMoreThanDebt(uint256 _amount, uint256 _debt);

    //closePosition
    error DebtIsNotPaid(uint256 debt);

    //removeCollateral
    error MustRemoveLessLiquidity(uint256 _amount, uint256 _liquidity);
    error CannotBeUndercollateralized();
    

}
