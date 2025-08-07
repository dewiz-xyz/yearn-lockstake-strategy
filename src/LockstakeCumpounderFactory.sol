// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {LockstakeCumpounder, Hop} from "./LockstakeCumpounder.sol";
import {IStrategyInterface} from "./interfaces/IStrategyInterface.sol";

contract LockstakeCumpounderFactory {
    event NewStrategy(address indexed strategy, address indexed farm);

    address public immutable emergencyAdmin;

    address public management;
    address public performanceFeeRecipient;
    address public keeper;

    address public lockstakeEngine = 0xCe01C90dE7FD1bcFa39e237FE6D8D9F569e8A6a3;

    /// @notice Track the deployments. farm => strategy
    mapping(address => address) public deployments;

    /// @notice Constructor to set initial addresses.
    /// @param _management The address of the management role.
    /// @param _performanceFeeRecipient The address of the performance fee recipient.
    /// @param _keeper The address of the keeper.
    /// @param _emergencyAdmin The address of the emergency admin.
    constructor(
        address _management,
        address _performanceFeeRecipient,
        address _keeper,
        address _emergencyAdmin
    ) {
        management = _management;
        performanceFeeRecipient = _performanceFeeRecipient;
        keeper = _keeper;
        emergencyAdmin = _emergencyAdmin;
    }

    /**
     * @notice Deploy a new LockstakeCumpounder strategy.
     * @param _farm The lockstake farm to be used by the strategy
     * @param _name The name of the new strategy.
     * @param _path The MultiSwapper path for swapping rewards.
     * @return The address of the new strategy.
     */
    function newStrategy(
        address _farm,
        string calldata _name,
        Hop[] calldata _path
    ) external virtual returns (address) {
        require(
            deployments[_farm] == address(0),
            "Strategy already deployed for this farm"
        );

        LockstakeCumpounder _newStrategy = new LockstakeCumpounder(
            lockstakeEngine,
            _farm,
            _name
        );

        // slither-disable-next-line reentrancy-no-eth
        // Safe: Constructor call above is trusted, no reentrancy risk
        deployments[_farm] = address(_newStrategy);

        IStrategyInterface _strategyInterface = IStrategyInterface(
            address(_newStrategy)
        );

        _strategyInterface.setPerformanceFeeRecipient(performanceFeeRecipient);

        _strategyInterface.setKeeper(keeper);

        _strategyInterface.setSwapPath(_path);

        _strategyInterface.setPendingManagement(management);

        _strategyInterface.setEmergencyAdmin(emergencyAdmin);

        emit NewStrategy(address(_newStrategy), _farm);
        return address(_newStrategy);
    }

    /// @notice Updates the management, performance fee recipient, and keeper addresses.
    /// @param _management The new management address.
    /// @param _performanceFeeRecipient The new performance fee recipient address.
    /// @param _keeper The new keeper address.
    function setAddresses(
        address _management,
        address _performanceFeeRecipient,
        address _keeper
    ) external {
        require(msg.sender == management, "!management");
        management = _management;
        performanceFeeRecipient = _performanceFeeRecipient;
        keeper = _keeper;
    }

    /// @notice Sets the LockstakeEngine contract address.
    /// @param _lockstakeEngine The new LockstakeEngine address.
    function setLockstakeEngine(address _lockstakeEngine) external {
        require(msg.sender == management, "!management");
        lockstakeEngine = _lockstakeEngine;
    }

    /// @notice Checks if a strategy is deployed by this factory.
    /// @param _strategy The address of the strategy to check.
    /// @return A boolean indicating if the strategy is deployed by this factory.
    function isDeployedStrategy(
        address _strategy
    ) external view returns (bool) {
        address _farm = IStrategyInterface(_strategy).FARM();
        return deployments[_farm] == _strategy;
    }
}
