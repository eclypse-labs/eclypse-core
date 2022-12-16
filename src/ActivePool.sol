// SPDX-License-Identifier: MIT

pragma solidity <0.9.0;

import "./interfaces/IActivePool.sol";
import "src/liquity-dependencies/CheckContract.sol";
import "forge-std/console.sol";
//import "Dependencies/console.sol";

import "./LPPositionsManager.sol";

contract ActivePool is Ownable, CheckContract, IActivePool {

    string public constant NAME = "ActivePool";
    address public borrowerOperationsAddress;
    address public lpPositionsManagerAddress;
    //address public stabilityPoolAddress;
    //uint256 internal ETH;  // deposited ether tracker
    //uint256[] internal COLLATERAL; // array of LP position tokenIds in the protocol
    //mapping(uint256 => uint256) indexOfTokenId;
    uint256 internal GHODebt;

    INonfungiblePositionManager constant uniswapPositionsNFT =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
    LPPositionsManager lpPositionsManager;

    // --- Events ---

    event BorrowerOperationsAddressChanged(
        address _newBorrowerOperationsAddress
    );
    event TroveManagerAddressChanged(address _newTroveManagerAddress);
    event ActivePoolGHODebtUpdated(uint256 _GHODebt);
    event ActivePoolCollateralBalanceUpdated(uint256 _collateralValue);

    // --- Contract setters ---

    function setAddresses(
        address _borrowerOperationsAddress,
        address _lpPositionsManagerAddress
    )
        external
        //address _stabilityPoolAddress
        onlyOwner
    {
        checkContract(_borrowerOperationsAddress);
        checkContract(_lpPositionsManagerAddress);
        //checkContract(_stabilityPoolAddress);

        borrowerOperationsAddress = _borrowerOperationsAddress;
        lpPositionsManagerAddress = _lpPositionsManagerAddress;
        //stabilityPoolAddress = _stabilityPoolAddress;

        lpPositionsManager = LPPositionsManager(lpPositionsManagerAddress);

        emit BorrowerOperationsAddressChanged(_borrowerOperationsAddress);
        //emit StabilityPoolAddressChanged(_stabilityPoolAddress);

        //renounceOwnership(); //too early to renounce ownership of the contract yet
    }

    // --- Getters for public variables. Required by IPool interface ---

    /*
     * Returns the total collateral value locked in the protocol.
     *
     */
    function getCollateralValue() public view override returns (uint256) {
        uint256 sum = 0;
        for (
            uint32 i = 0;
            i < uniswapPositionsNFT.balanceOf(address(this));
            i++
        ) {
            sum += lpPositionsManager.positionValueInETH(
                uniswapPositionsNFT.tokenOfOwnerByIndex(address(this), i)
            );
        }
        return sum;
    }

    function getGHODebt() external view override returns (uint256) {
        return GHODebt;
    }

    // --- Pool functionality ---

    function decreaseLiquidity(INonfungiblePositionManager.DecreaseLiquidityParams memory params)
        public
        onlyBOorLPPMorSP
        returns (uint256 amount0, uint256 amount1)
    {
        (amount0, amount1) = uniswapPositionsNFT.decreaseLiquidity(params);

        return (amount0, amount1);
    }

    function collectOwed(INonfungiblePositionManager.CollectParams memory params)
        public
        onlyBOorLPPMorSP
        returns (uint256 amount0, uint256 amount1)
    {
        (amount0, amount1) = uniswapPositionsNFT.collect(params);

        return (amount0, amount1);
    }

    function burnPosition(uint256 tokenId)
        public
        onlyBOorLPPMorSP
    {
        uniswapPositionsNFT.burn(tokenId);
    }

    function sendLp(address _account, uint256 _tokenId)
        public
        onlyBOorLPPMorSP
        onlyBOorLPPM
    {
        //emit ActivePoolCollateralBalanceUpdated(getCollateralValue());
        emit LpSent(_account, _tokenId);
        uniswapPositionsNFT.transferFrom(address(this), _account, _tokenId);
    }

    function sendToken(address _token, address _account, uint256 _amount)
        public
        onlyBOorLPPMorSP
        onlyBOorLPPM
    {
        IERC20(_token).transfer(_account, _amount);
    }

    function increaseGHODebt(uint256 _amount) external override onlyBOorLPPM {
        GHODebt += _amount;
        emit ActivePoolGHODebtUpdated(GHODebt);
    }

    function decreaseGHODebt(uint256 _amount)
        external
        override
        onlyBOorLPPMorSP
    {
        GHODebt -= _amount;
        emit ActivePoolGHODebtUpdated(GHODebt);
    }

    // Heal function
    function increaseLiquidity(
        address payer,
        uint256 tokenId,
        uint256 amountAdd0,
        uint256 amountAdd1
    )
        public
        override
        onlyBorrowerOperations
        returns (
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {
        (
            ,
            ,
            address token0,
            address token1,
            ,
            ,
            ,
            ,
            ,
            ,
            ,

        ) = uniswapPositionsNFT.positions(tokenId);
        IERC20(token0).transferFrom(payer, address(this), amountAdd0);
        IERC20(token1).transferFrom(payer, address(this), amountAdd1);

        INonfungiblePositionManager.IncreaseLiquidityParams
            memory params = INonfungiblePositionManager
                .IncreaseLiquidityParams({
                    tokenId: tokenId,
                    amount0Desired: amountAdd0,
                    amount1Desired: amountAdd1,
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: block.timestamp
                });
        (liquidity, amount0, amount1) = uniswapPositionsNFT.increaseLiquidity(
            params
        );
    }

    function removeLiquidity(uint256 _tokenId, uint128 _liquidityToRemove)
        public
        override
        onlyBorrowerOperations
        returns (uint256 amount0, uint256 amount1)
    {
        // amount0Min and amount1Min are price slippage checks
        // if the amount received after burning is not greater than these minimums, transaction will fail
        INonfungiblePositionManager.DecreaseLiquidityParams
            memory params = INonfungiblePositionManager
                .DecreaseLiquidityParams({
                    tokenId: _tokenId,
                    liquidity: _liquidityToRemove,
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: block.timestamp
                });

        // It might be necessary that the ActivePool does this, since it's the actual NFT owner.
        (amount0, amount1) = uniswapPositionsNFT.decreaseLiquidity(params);

        //send liquidity back to owner
        uniswapPositionsNFT.collect(
            INonfungiblePositionManager.CollectParams(
                _tokenId,
                msg.sender,
                type(uint128).max, // sends everything owed to the position owner (removed liquidity + fees collected)
                type(uint128).max
            )
        );
    }

    modifier onlyBorrowerOperations() {
        require(msg.sender == borrowerOperationsAddress);
        _;
    }

    modifier onlyBOorLPPM() {
        require(
            msg.sender == borrowerOperationsAddress ||
                msg.sender == lpPositionsManagerAddress
        );
        _;
    }

    modifier onlyBOorLPPMorSP() {
        require(
            msg.sender == borrowerOperationsAddress ||
                msg.sender == lpPositionsManagerAddress
            //msg.sender == stabilityPoolAddress
        );
        _;
    }
}

