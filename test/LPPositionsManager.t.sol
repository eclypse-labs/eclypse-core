//SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

// import "forge-std/Test.sol";
// import "../src/GHOToken.sol";
// import "../src/BorrowerOperations.sol";
// import "../src/ActivePool.sol";
// import "../src/LPPositionsManager.sol";
// import "@uniswap-core/interfaces/IUniswapV3Factory.sol";
// import "@uniswap-core/interfaces/IUniswapV3Pool.sol";
// import "@uniswap-periphery/interfaces/INonfungiblePositionManager.sol";
// import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "./UniswapTest.sol";

contract LPPositionsManagerTest is UniswapTest {
    function setUp() public {
        // uniswapTest();
    }

    function testOpenPosition() public {
        //uniswapPositionsNFT.transferFrom(randomLotNFT, address(activePool), 374478);
        //console.log(lpPositionsManager.getPosition(374478).user);
    }

    //     //TODO: test deposit
    //     function testDeposit() public {
    //         uint256 _tokenId;
    //         uint256 collateralRatio;

    //         INonfungiblePositionManager.MintParams
    //             memory mintParams = INonfungiblePositionManager.MintParams({
    //                 token0: wethAddr,
    //                 token1: usdcAddr,
    //                 fee: 0,
    //                 tickLower: int24(69082),
    //                 tickUpper: int24(73136),
    //                 amount0Desired: 1 ether,
    //                 amount1Desired: 5000 ether,
    //                 amount0Min: 0,
    //                 amount1Min: 0,
    //                 recipient: address(this),
    //                 deadline: 0
    //             });

    //         //We set the token identifier for the given position
    //         (_tokenId, , , ) = uniswapPositionsNFT.mint(mintParams);
    //         //we compute the colaterl ratio of the opened position
    //         borrowerOperations.openPosition(_tokenId);
    //         collateralRatio = positionsManager.computeCR(_tokenId);
    //         //we verifity that the position is not undercollateralized.
    //         assertTrue(collateralRatio > 1, "the position is undercollateralized");

    //         vm.stopPrank();
    //     }

    //     //TODO: test deposit + withdraw

    //     function testDepositAndWithdraw() public {
    //         uint256 _tokenId;

    //         INonfungiblePositionManager.MintParams
    //             memory mintParams = INonfungiblePositionManager.MintParams({
    //                 token0: wethAddr,
    //                 token1: usdcAddr,
    //                 fee: 0,
    //                 tickLower: int24(69082),
    //                 tickUpper: int24(73136),
    //                 amount0Desired: 1 ether,
    //                 amount1Desired: 5000 ether,
    //                 amount0Min: 0,
    //                 amount1Min: 0,
    //                 recipient: address(this),
    //                 deadline: block.timestamp
    //             });

    //         (_tokenId, , , ) = uniswapPositionsNFT.mint(mintParams);
    //     }

    //     //TODO: test deposit + borrow + check health factor

    //     //TODO: test deposit + borrow + can't withdraw if it would liquidate the position

    //     //TODO: test liquidation (change oracle price)

    //     function testNumberIs42() public {}

    //     function testFailSubtract43() public {}
}
