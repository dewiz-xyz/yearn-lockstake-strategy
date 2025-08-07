// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {Setup} from "./utils/Setup.sol";

import {LockstakeCumpounderFactory} from "../LockstakeCumpounderFactory.sol";
import {LockstakeCumpounder, Hop, Dex} from "../LockstakeCumpounder.sol";
import {IStrategyInterface} from "../interfaces/IStrategyInterface.sol";

contract LockstakeCumpounderFactoryTest is Setup {
    LockstakeCumpounderFactory public testFactory;

    address public newManagement = address(100);
    address public newPerformanceFeeRecipient = address(101);
    address public newKeeper = address(102);
    address public newLockstakeEngine = address(103);

    function setUp() public override {
        super.setUp();

        testFactory = new LockstakeCumpounderFactory(
            management,
            performanceFeeRecipient,
            keeper,
            emergencyAdmin
        );
    }

    function test_factory_constructor() public {
        assertEq(testFactory.management(), management);
        assertEq(
            testFactory.performanceFeeRecipient(),
            performanceFeeRecipient
        );
        assertEq(testFactory.keeper(), keeper);
        assertEq(testFactory.emergencyAdmin(), emergencyAdmin);
        assertEq(testFactory.lockstakeEngine(), lockstakeEngine);
    }

    function test_factory_newStrategy1() public {
        Hop[] memory path = new Hop[](2);
        path[0] = Hop(Dex.UniV3, tokenAddrs["SPK"], tokenAddrs["USDC"], 100);
        path[1] = Hop(Dex.UniV2, tokenAddrs["USDC"], tokenAddrs["SKY"], 0);

        vm.expectEmit(false, true, false, true);
        emit LockstakeCumpounderFactory.NewStrategy(address(0), farm); // address(0) will be replaced by actual address

        address newStrategy = testFactory.newStrategy(
            farm,
            "Test Strategy",
            path
        );

        assertNotEq(newStrategy, address(0), "Strategy should be deployed");
        assertEq(
            testFactory.deployments(farm),
            newStrategy,
            "Deployment should be tracked"
        );
        assertTrue(
            testFactory.isDeployedStrategy(newStrategy),
            "Should recognize deployed strategy"
        );

        IStrategyInterface strategyInterface = IStrategyInterface(newStrategy);
        assertEq(
            strategyInterface.FARM(),
            farm,
            "Farm should be set correctly"
        );
        assertEq(
            strategyInterface.name(),
            "Test Strategy",
            "Name should be set correctly"
        );
        assertEq(
            strategyInterface.pendingManagement(),
            management,
            "Pending management should be set"
        );
        assertEq(strategyInterface.keeper(), keeper, "Keeper should be set");
        assertEq(
            strategyInterface.performanceFeeRecipient(),
            performanceFeeRecipient,
            "Performance fee recipient should be set"
        );
        assertEq(
            strategyInterface.emergencyAdmin(),
            emergencyAdmin,
            "Emergency admin should be set"
        );
    }

    function test_factory_newStrategy_emptyPath() public {
        Hop[] memory emptyPath = new Hop[](0);

        address newStrategy = testFactory.newStrategy(
            farm,
            "Test Strategy",
            emptyPath
        );
        assertNotEq(
            newStrategy,
            address(0),
            "Strategy should deploy with empty path"
        );
    }

    function test_factory_newStrategy_complexPath() public {
        Hop[] memory complexPath = new Hop[](4);
        complexPath[0] = Hop(
            Dex.UniV3,
            tokenAddrs["SPK"],
            tokenAddrs["USDC"],
            100
        );
        complexPath[1] = Hop(
            Dex.Psm,
            tokenAddrs["USDC"],
            tokenAddrs["USDS"],
            0
        );
        complexPath[2] = Hop(
            Dex.UniV2,
            tokenAddrs["USDS"],
            tokenAddrs["DAI"],
            0
        );
        complexPath[3] = Hop(
            Dex.UniV3,
            tokenAddrs["DAI"],
            tokenAddrs["SKY"],
            500
        );

        address newStrategy = testFactory.newStrategy(
            farm,
            "Complex Path Strategy",
            complexPath
        );
        assertNotEq(
            newStrategy,
            address(0),
            "Strategy should deploy with complex path"
        );

        IStrategyInterface strategyInterface = IStrategyInterface(newStrategy);
        assertEq(strategyInterface.name(), "Complex Path Strategy");
    }

    function test_factory_setAddresses() public {
        vm.expectRevert("!management");
        vm.prank(user);
        testFactory.setAddresses(
            newManagement,
            newPerformanceFeeRecipient,
            newKeeper
        );

        vm.prank(management);
        testFactory.setAddresses(
            newManagement,
            newPerformanceFeeRecipient,
            newKeeper
        );

        assertEq(testFactory.management(), newManagement);
        assertEq(
            testFactory.performanceFeeRecipient(),
            newPerformanceFeeRecipient
        );
        assertEq(testFactory.keeper(), newKeeper);
    }

    function test_factory_setAddresses_zeroAddresses() public {
        vm.prank(management);
        testFactory.setAddresses(address(0), address(0), address(0));

        assertEq(testFactory.management(), address(0));
        assertEq(testFactory.performanceFeeRecipient(), address(0));
        assertEq(testFactory.keeper(), address(0));
    }

    function test_factory_setLockstakeEngine() public {
        vm.expectRevert("!management");
        vm.prank(user);
        testFactory.setLockstakeEngine(newLockstakeEngine);

        vm.prank(management);
        testFactory.setLockstakeEngine(newLockstakeEngine);

        assertEq(testFactory.lockstakeEngine(), newLockstakeEngine);
    }

    function test_factory_setLockstakeEngine_zeroAddress() public {
        vm.prank(management);
        testFactory.setLockstakeEngine(address(0));

        assertEq(testFactory.lockstakeEngine(), address(0));
    }

    function test_factory_isDeployedStrategy() public {
        Hop[] memory path = new Hop[](1);
        path[0] = Hop(Dex.UniV2, tokenAddrs["SPK"], tokenAddrs["SKY"], 0);

        address deployedStrategy = testFactory.newStrategy(
            farm,
            "Test Strategy",
            path
        );

        assertTrue(testFactory.isDeployedStrategy(deployedStrategy));
        assertFalse(testFactory.isDeployedStrategy(address(strategy)));
    }

    function test_factory_deployments_mapping() public {
        Hop[] memory path = new Hop[](1);
        path[0] = Hop(Dex.UniV2, tokenAddrs["SPK"], tokenAddrs["SKY"], 0);

        address strategy1 = testFactory.newStrategy(farm, "Strategy 1", path);
        assertEq(testFactory.deployments(farm), strategy1);

        assertEq(testFactory.deployments(address(0x3333)), address(0)); // Non-existent farm
    }

    function test_factory_newStrategy_afterAddressUpdate() public {
        vm.prank(management);
        testFactory.setAddresses(
            newManagement,
            newPerformanceFeeRecipient,
            newKeeper
        );

        Hop[] memory path = new Hop[](1);
        path[0] = Hop(Dex.UniV2, tokenAddrs["SPK"], tokenAddrs["SKY"], 0);

        address newStrategy = testFactory.newStrategy(
            farm,
            "Test Strategy",
            path
        );

        IStrategyInterface strategyInterface = IStrategyInterface(newStrategy);
        assertEq(strategyInterface.pendingManagement(), newManagement);
        assertEq(strategyInterface.keeper(), newKeeper);
        assertEq(
            strategyInterface.performanceFeeRecipient(),
            newPerformanceFeeRecipient
        );
    }

    function test_factory_immutable_emergencyAdmin() public {
        assertEq(testFactory.emergencyAdmin(), emergencyAdmin);

        Hop[] memory path = new Hop[](1);
        path[0] = Hop(Dex.UniV2, tokenAddrs["SPK"], tokenAddrs["SKY"], 0);

        address newStrategy = testFactory.newStrategy(
            farm,
            "Test Strategy",
            path
        );
        IStrategyInterface strategyInterface = IStrategyInterface(newStrategy);
        assertEq(strategyInterface.emergencyAdmin(), emergencyAdmin);
    }

    function test_factory_newStrategy_revertOnRedeployment() public {
        Hop[] memory path = new Hop[](1);
        path[0] = Hop(Dex.UniV2, tokenAddrs["SPK"], tokenAddrs["SKY"], 0);

        address firstStrategy = testFactory.newStrategy(
            farm,
            "First Strategy",
            path
        );

        assertNotEq(
            firstStrategy,
            address(0),
            "First strategy should be deployed"
        );
        assertEq(
            testFactory.deployments(farm),
            firstStrategy,
            "First deployment should be tracked"
        );
        assertTrue(
            testFactory.isDeployedStrategy(firstStrategy),
            "Should recognize first deployed strategy"
        );

        vm.expectRevert("Strategy already deployed for this farm");
        testFactory.newStrategy(farm, "Second Strategy", path);

        assertEq(
            testFactory.deployments(farm),
            firstStrategy,
            "Original deployment should still be tracked"
        );
        assertTrue(
            testFactory.isDeployedStrategy(firstStrategy),
            "Should still recognize original deployed strategy"
        );
    }
}
