// SPDX-License-Identifier: MIT

pragma solidity <0.9.0;

import "./interfaces/IGHOToken.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "src/liquity-dependencies/CheckContract.sol";
//import "Dependencies/console.sol";

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/*
*
* Based upon OpenZeppelin's ERC20 contract:
* https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/ERC20.sol
*  
* and their EIP2612 (ERC20Permit / ERC712) functionality:
* https://github.com/OpenZeppelin/openzeppelin-contracts/blob/53516bc555a454862470e7860a9b5254db4d00f5/contracts/token/ERC20/ERC20Permit.sol
* 
*
* --- Functionality added specific to the GHOToken ---
* 
* 1) Transfer protection: blacklist of addresses that are invalid recipients (i.e. core Liquity contracts) in external 
* transfer() and transferFrom() calls. The purpose is to protect users from losing tokens by mistakenly sending GHO directly to a Liquity 
* core contract, when they should rather call the right function. 
*
* 2) sendToPool() and returnFromPool(): functions callable only Liquity core contracts, which move GHO tokens between Liquity <-> user.
*/

contract GHOToken is CheckContract, IGHOToken, ERC20Permit {
    using SafeMath for uint256;
    
    uint256 private _totalSupply;
    string constant internal _NAME = "GHO Stablecoin";
    string constant internal _SYMBOL = "GHO";
    string constant internal _VERSION = "1";
    uint8 constant internal _DECIMALS = 18;
    
    // --- Data for EIP2612 ---
    
    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 private constant _PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    // keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant _TYPE_HASH = 0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f;

    // Cache the domain separator as an immutable value, but also store the chain id that it corresponds to, in order to
    // invalidate the cached domain separator if the chain id changes.
    //uint256 private immutable _CACHED_CHAIN_ID;

    bytes32 private immutable _HASHED_NAME;
    bytes32 private immutable _HASHED_VERSION;
        
    // User data for GHO token
    mapping (address => uint256) private _balances;
    mapping (address => mapping (address => uint256)) private _allowances;  
    
    // --- Addresses ---
    address public immutable borrowerOperationsAddress;
    
    // --- Events ---

    constructor
    (
        address _borrowerOperationsAddress
    ) 
        ERC20Permit(_NAME) ERC20(_NAME, _VERSION)
    {  
        borrowerOperationsAddress = _borrowerOperationsAddress;        
        emit BorrowerOperationsAddressChanged(_borrowerOperationsAddress);
        
        bytes32 hashedName = keccak256(bytes(_NAME));
        bytes32 hashedVersion = keccak256(bytes(_VERSION));
        
        _HASHED_NAME = hashedName;
        _HASHED_VERSION = hashedVersion;
    }

    // --- Functions for intra-Liquity calls ---

    function mint(address _account, uint256 _amount) external override {
        _requireCallerIsBorrowerOperations();
        _mint(_account, _amount);
    }

    function burn(address _account, uint256 _amount) external override {
        //TODO: require(msg.sender == owner)
        _burn(_account, _amount);
    }

    function sendToPool(address _sender,  address _poolAddress, uint256 _amount) external override {
        //TODO: require(msg.sender == owner)
        _transfer(_sender, _poolAddress, _amount);
    }

    function returnFromPool(address _poolAddress, address _receiver, uint256 _amount) external override {
        //TODO: require(msg.sender == owner)
        _transfer(_poolAddress, _receiver, _amount);
    }

    // --- External functions ---

    // --- EIP 2612 Functionality ---

    // --- Internal operations ---


    // --- Internal operations ---
    // Warning: sanity checks (for sender and recipient) should have been done before calling these internal functions


    // --- 'require' functions ---

    function _requireValidRecipient(address _recipient) internal view {
        require(
            _recipient != address(0) && 
            _recipient != address(this),
            "GHO: Cannot transfer tokens directly to the GHO token contract or the zero address"
        );
        require(
            _recipient != borrowerOperationsAddress, 
            "GHO: Cannot transfer tokens directly to the StabilityPool, TroveManager or BorrowerOps"
        );
    }

    function _requireCallerIsBorrowerOperations() internal view {
        require(msg.sender == borrowerOperationsAddress, "GHOToken: Caller is not BorrowerOperations");
    }

    function balanceOf(address account) public view virtual override(IGHOToken, ERC20) returns (uint256) {
        return _balances[account];
    }


    // --- Optional functions ---

    /*function version() external view override returns (string memory) {
        return _VERSION;
    }*/

    /*function permitTypeHash() external view override returns (bytes32) {
        return _PERMIT_TYPEHASH;
    }*/
}