// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title TokenHandler
 * @dev A simple contract that allows a designated receiver to withdraw
 * all tokens of a specific ERC20 token held by this contract.
 *
 * This contract is useful for scenarios where tokens need to be collected
 * and transferred to a specific address, such as fee collection or
 * token recovery mechanisms.
 */
contract TokenHandler {
    /// @notice The address authorized to withdraw tokens from this contract
    address public immutable receiver;

    /// @notice The ERC20 token that this handler manages
    ERC20 public immutable token;

    /**
     * @notice Constructor
     * @param _receiver The address that will be authorized to withdraw tokens
     * @param _token The address of the ERC20 token to handle
     */
    constructor(address _receiver, address _token) {
        receiver = _receiver;
        token = ERC20(_token);
    }

    /**
     * @notice Transfers all tokens held by this contract to the receiver
     * @dev Only the designated receiver can call this function
     *
     * This function will transfer the entire balance of the managed token
     * from this contract to the receiver address.
     *
     * Requirements:
     * - Only the receiver can call this function
     * - The contract must have a token balance to transfer
     */
    // slither-disable-next-line unchecked-transfer
    function wipe() external {
        require(msg.sender == receiver, "unauthorized");
        uint256 balance = token.balanceOf(address(this));
        if (balance > 0) token.transfer(receiver, balance);
    }
}
