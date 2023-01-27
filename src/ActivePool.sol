// SPDX-License-Identifier: MIT

pragma solidity <0.9.0;

import "./interfaces/IActivePool.sol";
import "src/liquity-dependencies/CheckContract.sol";
import "forge-std/console.sol";
import "@uniswap-core/libraries/FullMath.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

//import "Dependencies/console.sol";

import "./LPPositionsManager.sol";

contract ActivePool is Ownable, CheckContract, IActivePool, IERC721Receiver {

    string public constant NAME = "ActivePool";
    address public borrowerOperationsAddress;
    address public lpPositionsManagerAddress;
    //address public stabilityPoolAddress;
    //uint256 internal ETH;  // deposited ether tracker
    //uint256[] internal COLLATERAL; // array of LP position tokenIds in the protocol
    //mapping(uint256 => uint256) indexOfTokenId;
    uint256 internal GHODebt;

    uint256 internal liquidationFees = 5;

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

    function mintLP(
        INonfungiblePositionManager.MintParams memory params
    ) public onlyBOorLPPMorSP returns (uint256 tokenId) {
        TransferHelper.safeApprove(
            params.token0,
            address(uniswapPositionsNFT),
            params.amount0Desired
        );
        TransferHelper.safeApprove(
            params.token1,
            address(uniswapPositionsNFT),
            params.amount1Desired
        );
        (tokenId, , ,) = uniswapPositionsNFT.mint(params);
        return tokenId;
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
        uint256 amountToSend = FullMath.mulDiv(_amount, 100 - liquidationFees, 100);
        IERC20(_token).transfer(_account, amountToSend);
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
        address sender,
        uint256 _tokenId,
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
        address token0 = lpPositionsManager.getPosition(_tokenId).token0;
        address token1 = lpPositionsManager.getPosition(_tokenId).token1;

        TransferHelper.safeTransferFrom(token0, sender, address(this), amountAdd0);
        TransferHelper.safeTransferFrom(token1, sender, address(this), amountAdd1);

        TransferHelper.safeApprove(token0, address(uniswapPositionsNFT), amountAdd0);
        TransferHelper.safeApprove(token1, address(uniswapPositionsNFT), amountAdd1);

        (liquidity, amount0, amount1) = uniswapPositionsNFT.increaseLiquidity(
            INonfungiblePositionManager.IncreaseLiquidityParams({
                tokenId: _tokenId,
                amount0Desired: amountAdd0,
                amount1Desired: amountAdd1,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            })
        );
    }

    function removeLiquidity(uint256 _tokenId, uint128 _liquidityToRemove)
        public
        override
        returns (uint256 amount0, uint256 amount1)
    {
        // amount0Min and amount1Min are price slippage checks

        uniswapPositionsNFT.decreaseLiquidity(
            INonfungiblePositionManager
                .DecreaseLiquidityParams({
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
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            }));

        TransferHelper.safeTransfer(lpPositionsManager.getPosition(_tokenId).token0 , address(this), amount0);
        TransferHelper.safeTransfer(lpPositionsManager.getPosition(_tokenId).token1 , address(this), amount1);
        
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
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

