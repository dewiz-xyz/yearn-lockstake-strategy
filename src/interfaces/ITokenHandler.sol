// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

/**
 * @title ITokenHandler
 * @notice Interface for TokenHandler contract that manages token withdrawals
 */
interface ITokenHandler {
    /**
     * @notice Returns the address authorized to withdraw tokens
     * @return The receiver address
     */
    function receiver() external view returns (address);

    /**
     * @notice Returns the ERC20 token managed by this handler
     * @return The token contract
     */
    function token() external view returns (address);

    /**
     * @notice Transfers all tokens held by the contract to the receiver
     * @dev Only the designated receiver can call this function
     */
    function wipe() external;
}
