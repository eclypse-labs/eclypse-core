// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { Script } from "forge-std/Script.sol";
import { EclypseVault } from "contracts/EclypseVault.sol";
import { PositionsManager } from "contracts/PositionsManager.sol";
import { UserInteractions } from "contracts/UserInteractions.sol";
import { PolygonPriceFeed } from "contracts/PolygonPriceFeed.sol";

import { Denominations } from "@chainlink/Denominations.sol";

contract Deploy is Script {
    
	address public constant wethAddr = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant wethPolygonAddr = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;
    address public constant usdcPolygonAddr = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    
	address public uniPoolUsdcETHAddr = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640;
    address public uniPoolUsdcETHPolygonAddr = 0x45dDa9cb7c25131DF268515131f647d726f50608;
	address constant feedRegisteryAddr = 0x47Fb2585D2C56Fe188D0E6ec628a38b74fCeeeDf;

	address public constant swapRouterAddr = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address public constant uniswapFactoryAddr = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
	address uniswapPositionsNFTAddr = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;

    function run() public {
        // Deploy contracts
        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);
        deploy();
        vm.stopBroadcast();
    }

    function deploy() public {
        // Deploy contracts


        EclypseVault eclypseVault = new EclypseVault();
        PositionsManager positionsManager = new PositionsManager();
        UserInteractions userInteractions = new UserInteractions();
        PolygonPriceFeed polygonPriceFeed = new PolygonPriceFeed();

        eclypseVault.initialize(uniswapPositionsNFTAddr, address(positionsManager));
        positionsManager.initialize(
            address(uniswapFactoryAddr),
            uniswapPositionsNFTAddr,
            address(userInteractions),
            address(eclypseVault),
            address(polygonPriceFeed)
        );
        userInteractions.initialize(uniswapPositionsNFTAddr, address(positionsManager));
        // 	function initialize(address[] _initialFeeds, address[] _initialToken, address[] _initialQuote) external onlyOwner {
        address[] memory _initialFeeds = new address[](2);
        _initialFeeds[0] = 0xF9680D99D6C9589e2a93a78A04A279e509205945;
        _initialFeeds[1] = 0xefb7e6be8356cCc6827799B6A7348eE674A80EaE;
        address[] memory _initialToken = new address[](2);
        _initialToken[0] = Denominations.ETH;
        _initialToken[1] = usdcPolygonAddr;
        address[] memory _initialQuote = new address[](2);
        _initialQuote[0] = Denominations.USD;
        _initialQuote[1] = Denominations.ETH;
        polygonPriceFeed.initialize(_initialFeeds, _initialToken, _initialQuote);


        /*
        address _poolAddress,
		address _token0,
		address _token1,
		address _ETHpoolToken0,
		address _ETHpoolToken1,
		bool _inv0,
		bool _inv1
        */
         // USDC/ETH on polygon
        positionsManager.addPoolToProtocol(
            uniPoolUsdcETHPolygonAddr,
            usdcPolygonAddr,
            wethPolygonAddr,
            usdcPolygonAddr,
            wethAddr,
            false,
            true
        );
    }
}