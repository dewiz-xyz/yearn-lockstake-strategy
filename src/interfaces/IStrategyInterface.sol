// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {IBaseHealthCheck} from "@periphery/Bases/HealthCheck/IBaseHealthCheck.sol";
import {Hop} from "../periphery/MultiSwapper.sol";

interface IStrategyInterface is IBaseHealthCheck {
    function SKY() external view returns (address);

    function REWARD_TOKEN() external view returns (address);

    function LOCK_STAKE_ENGINE() external view returns (address);

    function FARM() external view returns (address);

    function URN() external view returns (address);

    function UNI_V2_ROUTER() external view returns (address);

    function URN_INDEX() external view returns (uint256);

    function referral() external view returns (uint16);

    function uniV3Path() external view returns (bytes memory);

    function minAmountToSell() external view returns (uint256);

    function openDeposits() external view returns (bool);

    function allowed(address _depositor) external view returns (bool);

    function estimatedTotalAssets() external view returns (uint256);

    function balanceOfStake() external view returns (uint256);

    function tend() external;

    function kick() external;

    function setReferral(uint16 _referral) external;

    function setVoteDelegate(address _voteDelegate) external;

    function voteDelegate() external view returns (address);

    function setSwapPath(Hop[] calldata _path) external;

    function setMinAmountToSell(uint256 _minAmountToSell) external;

    function setOpenDeposits(bool _openDeposits) external;

    function setAllowed(address _depositor, bool _allowed) external;
}
