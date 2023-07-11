// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { Script } from "forge-std/Script.sol";
import { EclypseVault } from "contracts/EclypseVault.sol";
import { PositionsManager } from "contracts/PositionsManager.sol";
import { UserInteractions } from "contracts/UserInteractions.sol";
import { PolygonPriceFeed } from "contracts/PolygonPriceFeed.sol";
import { IPositionsManager } from "contracts/interfaces/IPositionsManager.sol";
import { EclypseUSD } from "contracts/EclypseUSD.sol";

import { Denominations } from "@chainlink/Denominations.sol";

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { FixedPoint96 } from "@uniswap-core/libraries/FixedPoint96.sol";
import { FullMath } from "@uniswap-core/libraries/FullMath.sol";

contract UpdateRiskConstants is Script {
	address public uniPoolUsdcETHAddr = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640;
    address public uniPoolUsdcETHPolygonAddr = 0x45dDa9cb7c25131DF268515131f647d726f50608;

    EclypseVault constant eclypseVault = EclypseVault(0xC44460BABaE4e7Dcd2F36628135223e4E8b85DC7);
    PositionsManager constant positionsManager = PositionsManager(0x84044fa3f057617B78f7399e2560e15e06AC2d21);
    UserInteractions constant userInteractions = UserInteractions(0x618A35812B057d556F3BF866bC54ad7b3a90756E);
    PolygonPriceFeed constant polygonPriceFeed = PolygonPriceFeed(0xab251AA10d5B600509DBc76A3a8333960b6A8ddE);
    EclypseUSD constant stablecoin = EclypseUSD(0x38811C6e7Cc0952f88142335B578c398Bf0b6fC0);

    function run() public {
        // Deploy contracts
        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);
        deploy();
        vm.stopBroadcast();
    }

    function deploy() public {
        uint256 maxCollateralRatio = FullMath.mulDiv(FixedPoint96.Q96, 11, 10); // 1.1
        positionsManager.updateRiskConstants(uniPoolUsdcETHPolygonAddr, maxCollateralRatio);
    }
}