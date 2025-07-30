// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {LockstakeCumpounder, Hop} from "./LockstakeCumpounder.sol";
import {IStrategyInterface} from "./interfaces/IStrategyInterface.sol";

contract LockstakeCumpounderFactory {
    event NewStrategy(address indexed strategy, address indexed farm);
    event ImplementationBytecodeUpdated(bytes32 indexed bytecodeHash);

    address public immutable emergencyAdmin;

    address public management;
    address public performanceFeeRecipient;
    address public keeper;

    address public lockstakeEngine = 0xCe01C90dE7FD1bcFa39e237FE6D8D9F569e8A6a3;

    /// @notice Track the deployments. farm => strategy
    mapping(address => address) public deployments;

    /// @notice The implementation contract bytecode used for CREATE2 deployment
    bytes public implementationBytecode;

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

        // Set default implementation bytecode to current LockstakeCumpounder
        implementationBytecode = type(LockstakeCumpounder).creationCode;
    }

    /**
     * @notice Deploy a new Strategy using CREATE2 with the current implementation bytecode.
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
            implementationBytecode.length > 0,
            "Implementation bytecode not set"
        );

        // Encode constructor arguments
        bytes memory constructorArgs = abi.encode(
            lockstakeEngine,
            _farm,
            _name
        );

        // Combine bytecode with constructor arguments
        bytes memory deploymentBytecode = bytes.concat(
            implementationBytecode,
            constructorArgs
        );

        // Generate deterministic salt based on farm and current timestamp
        bytes32 salt = keccak256(
            abi.encodePacked(
                _farm,
                keccak256(abi.encodePacked(_name)),
                block.timestamp,
                msg.sender
            )
        );

        // Deploy using CREATE2
        address strategy;
        assembly {
            strategy := create2(
                0,
                add(deploymentBytecode, 0x20),
                mload(deploymentBytecode),
                salt
            )
        }

        require(strategy != address(0), "Strategy deployment failed");

        IStrategyInterface _newStrategy = IStrategyInterface(strategy);

        _newStrategy.setPerformanceFeeRecipient(performanceFeeRecipient);

        _newStrategy.setKeeper(keeper);

        _newStrategy.setSwapPath(_path);

        _newStrategy.setPendingManagement(management);

        _newStrategy.setEmergencyAdmin(emergencyAdmin);

        emit NewStrategy(address(_newStrategy), _farm);

        // Intentionally not checking if a strategy for a farm has already been deployed, allowing for redeployments of newer implementations.
        deployments[_farm] = address(_newStrategy);
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

    /// @notice Updates the implementation bytecode used for new strategy deployments.
    /// @param _bytecode The new implementation contract bytecode.
    function setImplementationBytecode(bytes calldata _bytecode) external {
        require(msg.sender == management, "!management");
        require(_bytecode.length > 0, "Invalid bytecode");

        implementationBytecode = _bytecode;

        emit ImplementationBytecodeUpdated(keccak256(_bytecode));
    }

    /// @notice Get the hash of the current implementation bytecode for verification.
    /// @return The keccak256 hash of the current implementation bytecode.
    function getImplementationBytecodeHash() external view returns (bytes32) {
        return keccak256(implementationBytecode);
    }
}
