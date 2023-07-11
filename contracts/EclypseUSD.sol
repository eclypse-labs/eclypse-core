// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract EclypseUSD is ERC20Burnable, Ownable {
    error EUSD__AmountMustBeMoreThanZero();
    error EUSD__BurnAmountExceedsBalance();
    error EUSD__NotZeroAddress();

    constructor(address newOwner) ERC20("Eclypse USD", "EUSD") {
        transferOwnership(newOwner);
    }

    function mint(address _to, uint256 _amount) public onlyOwner returns (bool){
         if (_to == address(0)) {
            revert EUSD__NotZeroAddress();
        }
        if (_amount <= 0) {
            revert EUSD__AmountMustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert EUSD__AmountMustBeMoreThanZero();
        }
        if (balance < _amount) {
            revert EUSD__BurnAmountExceedsBalance();
        }
        super.burn(_amount);
    }
}
