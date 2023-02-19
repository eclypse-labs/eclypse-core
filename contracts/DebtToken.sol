//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@uniswap-core/libraries/FullMath.sol";
import "@uniswap-core/libraries/FixedPoint96.sol";

import "gho-core/src/contracts/gho/ERC20.sol";

contract DebtToken is ERC20 {


    event Mint(address indexed to, uint256 amount);
    event Burn(address indexed from, uint256 amount);
    event BorrowLimitChanged(uint256 newBorrowLimit);

   
    uint256 interest;
    uint256 mintedAmount;
    uint256 timestamp;
    uint256 interestRate;

    address user;
    
    uint256 tokenIdSignature;
    address underlying;


    constructor(address userDebtToken, 
    uint256 interestRateDebtToken, 
    string memory nameDebtToken, 
    string memory symbolDebtToken, 
    uint8 decimalsDebtToken, 
    uint256 tokenIdSignatureDebtToken, 
    address underlyingDebtToken
    ) 
    ERC20(nameDebtToken, symbolDebtToken, decimalsDebtToken) {
        user = userDebtToken;
        tokenIdSignature = tokenIdSignatureDebtToken;
        underlying = underlyingDebtToken;

        interest = 0;
        mintedAmount = 0;
        timestamp = block.timestamp;
        interestRate = interestRateDebtToken;
    }

    function mint(uint256 amount) public {
        _mint(user, amount);
        unchecked {
            mintedAmount += amount;
        }
        emit Mint(user, amount);
    }

    function burn(uint256 amount) public {
        _burn(user, amount);
        require(mintedAmount >= amount, "DebtToken: burn amount exceeds debt");
        require(amount > 0, "DebtToken: Cannot burn 0 tokens");
        mintedAmount -= amount;
        emit Burn(user, amount);
    }

    function mintedBalanceOf() public view returns (uint256) {
        return mintedAmount;
    }
    
    function balanceOfInterest() public view returns (uint256) {
        return interest;
    }

    function totalBalanceOf() public view returns (uint256) {
        return mintedAmount + interest;
    }

    //TODO: When Variable Interest Rate is implemented, call getInterestRate() and remove the interestRate parameter.
    function updateInterest() public {
        uint256 timeElapsed = block.timestamp - timestamp;
        
        uint256 newInterests = 
        FullMath.mulDivRoundingUp(
                mintedAmount,
                lessDumbPower(
                    interestRate,
                    timeElapsed
                ),
                FixedPoint96.Q96
            ) +
            FullMath.mulDivRoundingUp(
                interest,
                lessDumbPower(
                    interestRate,
                    timeElapsed
                ),
                FixedPoint96.Q96
            ) -
            mintedAmount;
        
        timestamp = block.timestamp;
        mint(newInterests);
        interest += newInterests;
    }


    function lessDumbPower(
        uint256 _base,
        uint256 _exponent
    ) private pure returns (uint256 result) {
        // do fast exponentiation by checking parity of exponent
        if (_exponent == 0) {
            result = FixedPoint96.Q96;
        } else if (_exponent == 1) {
            result = _base;
        } else if (_exponent % 2 == 0) {
            result = lessDumbPower(_base, _exponent / 2);
            // calculate the square of the square root with FullMath.mulDiv
            result = FullMath.mulDiv(result, result, FixedPoint96.Q96);
        } else {
            result = lessDumbPower(_base, (_exponent - 1) / 2);
            // calculate the square of the square root with FullMath.mulDiv and multiply by base once
            result = FullMath.mulDiv(result, result, FixedPoint96.Q96);
            result = FullMath.mulDiv(result, _base, FixedPoint96.Q96);
        }
    }

}
