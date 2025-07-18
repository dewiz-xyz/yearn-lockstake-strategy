// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

/// @dev  Only the minimal subset of LockstakeEngine functions the strategy needs.
interface ILockstakeEngine {
    /// @notice Creates a new URN for msg.sender at the specified index.
    ///         Index must equal the number of URNs the user already owns.
    ///         (E.g. first call: index = 0.)
    function open(uint256 index) external returns (address);

    /// @notice Selects which farm to stake this URN’s entire SKY into.
    /// @param owner  The address owning the URN.
    /// @param index  The URN index for that owner.
    /// @param farm   The farm contract address (e.g. USDS‐farm).
    /// @param ref    A ref code (usually 0).
    function selectFarm(address owner, uint256 index, address farm, uint16 ref) external;

    function selectVoteDelegate(address owner, uint256 index, address voteDelegate) external;

    /// @notice Locks `wad` amount of SKY for the `owner`’s `index`­th URN, staking it to the previously‐selected farm.
    /// @param owner  The address owning the URN.
    /// @param index  The URN index.
    /// @param wad    The amount of SKY (in wei) to lock & stake.
    /// @param ref    A ref code passed to the farm when staking (e.g. 0).
    function lock(address owner, uint256 index, uint256 wad, uint16 ref) external;

    /// @notice Frees (unlocks & unstakes) `wad` amount of SKY from the `owner`’s `index`­th URN, sending it (minus exit fee) to `to`.
    /// @param owner  The address owning the URN.
    /// @param index  The URN index.
    /// @param to     The recipient of freed SKY.
    /// @param wad    The amount of SKY (in wei) to free.
    function free(address owner, uint256 index, address to, uint256 wad) external returns (uint256);

    /// @notice Claims the accrued USDS rewards from the `farm` on behalf of `owner`’s `index`­th URN, sending them to `to`.
    /// @param owner  The address owning the URN.
    /// @param index  The URN index.
    /// @param farm   The farm contract address that was staking SKY.
    /// @param to     The recipient of claimed USDS tokens.
    function getReward(address owner, uint256 index, address farm, address to) external returns (uint256);
}
