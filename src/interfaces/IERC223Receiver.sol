// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @notice Interface for a contract that accepts ERC-223 transfers.
/// @dev Spec: https://eips.ethereum.org/EIPS/eip-223#erc-223-token-receiver
interface IERC223Receiver {
    /// @param from Original token sender; msg.sender is the token contract.
    /// @param value Amount in the token's smallest units.
    /// @param data Optional data supplied by the sender.
    /// @return The acceptance selector, 0x8943ec02.
    function tokenReceived(address from, uint256 value, bytes calldata data)
        external
        returns (bytes4);
}
