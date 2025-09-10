// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {LockstakeCompounder, Hop, Dex} from "../src/LockstakeCompounder.sol";
import {LockstakeCompounderFactory} from "../src/LockstakeCompounderFactory.sol";
import {console} from "forge-std/console.sol";
import {IStrategyInterface} from "../src/interfaces/IStrategyInterface.sol";
import {StrategyAprOracle} from "../src/periphery/StrategyAprOracle.sol";

contract Deploy is Script {
    address public constant LOCKSTAKE_ENGINE = 0xCe01C90dE7FD1bcFa39e237FE6D8D9F569e8A6a3;
    address public constant REWARDS_LSSKY_SPK = 0x99cBC0e4E6427F6939536eD24d1275B95ff77404;

    address public constant KEEPER = 0x604e586F17cE106B64185A7a0d2c1Da5bAce711E;
    address public constant ACCOUNTANT = 0x5A74Cb32D36f2f517DB6f7b0A0591e09b22cDE69;
    address public constant SMS = 0x16388463d60FFE0661Cf7F1f31a7D658aC790ff7;

    address public constant SKY = 0x56072C95FAA701256059aa122697B133aDEd9279;
    address public constant SPK = 0xc20059e0317DE91738d13af027DfC4a50781b066;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant USDS = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;

    function run() public {
        vm.startBroadcast();

        StrategyAprOracle oracle = new StrategyAprOracle();
        console.log("StrategyAprOracle deployed to:", address(oracle));

        LockstakeCompounderFactory factory = new LockstakeCompounderFactory(SMS, ACCOUNTANT, KEEPER, SMS);

        console.log("LockstakeCompounderFactory deployed to:", address(factory));

        Hop[] memory path = new Hop[](3);
        path[0] = Hop(Dex.UniV3, SPK, USDC, 100);
        path[1] = Hop(Dex.Psm, USDC, USDS, 0);
        path[2] = Hop(Dex.UniV2, USDS, SKY, 0);

        address strategy = factory.newStrategy(REWARDS_LSSKY_SPK, "Lockstake SKY-SPK", path);
        console.log("Lockstake SKY-SPK deployed to:", strategy);

        vm.stopBroadcast();
    }
}
