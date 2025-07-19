// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import {LockstakeCumpounder, ERC20} from "./LockstakeCumpounder.sol";
import {IStrategyInterface} from "./interfaces/IStrategyInterface.sol";

contract LockstakeCumpounderFactory {
    event NewStrategy(address indexed strategy, address indexed farm);

    address public immutable emergencyAdmin;

    address public management;
    address public performanceFeeRecipient;
    address public keeper;

    address public lockstakeEngine = 0xCe01C90dE7FD1bcFa39e237FE6D8D9F569e8A6a3;

    /// @notice Track the deployments. asset => pool => strategy
    mapping(address => address) public deployments;

    constructor(address _management, address _performanceFeeRecipient, address _keeper, address _emergencyAdmin) {
        management = _management;
        performanceFeeRecipient = _performanceFeeRecipient;
        keeper = _keeper;
        emergencyAdmin = _emergencyAdmin;
    }

    /**
     * @notice Deploy a new Strategy.
     * @param _farm The lockstake farm to be used by the strategy
     * @return . The address of the new strategy.
     */
    function newStrategy(address _farm, string calldata _name, bytes calldata _path)
        external
        virtual
        returns (address)
    {
        // tokenized strategies available setters.
        IStrategyInterface _newStrategy =
            IStrategyInterface(address(new LockstakeCumpounder(lockstakeEngine, _farm, _name)));

        _newStrategy.setPerformanceFeeRecipient(performanceFeeRecipient);

        _newStrategy.setKeeper(keeper);

        _newStrategy.setUniV3Path(_path);

        _newStrategy.setPendingManagement(management);

        _newStrategy.setEmergencyAdmin(emergencyAdmin);

        emit NewStrategy(address(_newStrategy), _farm);

        deployments[_farm] = address(_newStrategy);
        return address(_newStrategy);
    }

    function setAddresses(address _management, address _performanceFeeRecipient, address _keeper) external {
        require(msg.sender == management, "!management");
        management = _management;
        performanceFeeRecipient = _performanceFeeRecipient;
        keeper = _keeper;
    }

    function setLockstakeEngine(address _lockstakeEngine) external {
        require(msg.sender == management, "!management");
        lockstakeEngine = _lockstakeEngine;
    }

    function isDeployedStrategy(address _strategy) external view returns (bool) {
        address _asset = IStrategyInterface(_strategy).asset();
        return deployments[_asset] == _strategy;
    }
}
