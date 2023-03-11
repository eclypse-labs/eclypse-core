// SPDX-License-Identifier: MIT

pragma solidity >=0.6.11;

import "gho-core/src/contracts/gho/interfaces/IERC20Mintable.sol";
import "gho-core/src/contracts/gho/interfaces/IERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IStableCoin is IERC20Mintable, IERC20Burnable, IERC20 {

}
