// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Deploy} from "./Deploy.s.sol";
import {LockstakeCompounder, Hop, Dex} from "../src/LockstakeCompounder.sol";
import {LockstakeCompounderFactory} from "../src/LockstakeCompounderFactory.sol";
import {StrategyAprOracle} from "../src/periphery/StrategyAprOracle.sol";
import {IStrategyInterface} from "../src/interfaces/IStrategyInterface.sol";

contract DeployTest is Test {
    Deploy deployScript;
    
    function setUp() public {
        deployScript = new Deploy();
    }
    
    function testDeployScript() public {
        // Record logs to capture deployment events
        vm.recordLogs();
        
        // Run the deployment script
        deployScript.run();
        
        // Get all logs from the deployment
        Vm.Log[] memory logs = vm.getRecordedLogs();
        
        // Find deployed contracts by looking for specific events
        address factoryAddress;
        address strategyAddress;
        
        // Look through logs to find NewStrategy event and contract deployments
        for (uint256 i = 0; i < logs.length; i++) {
            // Look for NewStrategy event: NewStrategy(address strategy, address farm)
            if (logs[i].topics.length >= 2 && 
                logs[i].topics[0] == keccak256("NewStrategy(address,address)")) {
                strategyAddress = address(uint160(uint256(logs[i].topics[1])));
                // The emitter of this event is the factory
                factoryAddress = logs[i].emitter;
                break;
            }
        }
        
        // Verify factory exists and has correct settings
        assertTrue(factoryAddress != address(0), "Factory should be deployed");
        assertTrue(factoryAddress.code.length > 0, "Factory should have code");
        
        LockstakeCompounderFactory factory = LockstakeCompounderFactory(factoryAddress);
        
        // Verify factory constructor settings
        assertEq(factory.management(), deployScript.SMS(), "Factory management should be SMS");
        assertEq(factory.performanceFeeRecipient(), deployScript.ACCOUNTANT(), "Factory performance fee recipient should be ACCOUNTANT");
        assertEq(factory.keeper(), deployScript.KEEPER(), "Factory keeper should be KEEPER");
        assertEq(factory.emergencyAdmin(), deployScript.SMS(), "Factory emergency admin should be SMS");
        
        // If we didn't get strategy from logs, get it from factory
        if (strategyAddress == address(0)) {
            strategyAddress = factory.deployments(deployScript.REWARDS_LSSKY_SPK());
        }
        
        // Verify strategy deployment and settings
        assertTrue(strategyAddress != address(0), "Strategy should be deployed");
        assertTrue(strategyAddress.code.length > 0, "Strategy should have code");
        
        // Verify strategy constructor settings using IStrategyInterface
        IStrategyInterface strategyContract = IStrategyInterface(strategyAddress);
        
        assertEq(strategyContract.asset(), deployScript.SKY(), "Strategy asset should be SKY");
        assertEq(strategyContract.name(), "Lockstake SKY-SPK", "Strategy name should match");
        assertEq(strategyContract.management(), address(factory), "Strategy management should be factory");
        assertEq(strategyContract.performanceFeeRecipient(), deployScript.ACCOUNTANT(), "Strategy performance fee recipient should be ACCOUNTANT");
        assertEq(strategyContract.keeper(), deployScript.KEEPER(), "Strategy keeper should be KEEPER");
        
        // Verify swap path is set correctly using LockstakeCompounder interface
        LockstakeCompounder lockstakeContract = LockstakeCompounder(strategyAddress);
        Hop[] memory deployedPath = lockstakeContract.getSwapPath();
        assertEq(deployedPath.length, 3, "Swap path should have 3 hops");
        
        assertEq(uint8(deployedPath[0].dex), uint8(Dex.UniV3), "First hop should be UniV3");
        assertEq(deployedPath[0].from, deployScript.SPK(), "First hop from should be SPK");
        assertEq(deployedPath[0].to, deployScript.USDC(), "First hop to should be USDC");
        assertEq(deployedPath[0].fee, 100, "First hop fee should be 100");
        
        assertEq(uint8(deployedPath[1].dex), uint8(Dex.Psm), "Second hop should be PSM");
        assertEq(deployedPath[1].from, deployScript.USDC(), "Second hop from should be USDC");
        assertEq(deployedPath[1].to, deployScript.USDS(), "Second hop to should be USDS");
        
        assertEq(uint8(deployedPath[2].dex), uint8(Dex.UniV2), "Third hop should be UniV2");
        assertEq(deployedPath[2].from, deployScript.USDS(), "Third hop from should be USDS");
        assertEq(deployedPath[2].to, deployScript.SKY(), "Third hop to should be SKY");
        
        assertTrue(true, "Deploy script executed successfully with correct settings");
    }
}
