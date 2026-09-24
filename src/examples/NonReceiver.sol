// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @notice Deliberately has no tokenReceived hook or fallback.
/// @dev ERC-223 transfers here must revert instead of silently stranding tokens.
contract NonReceiver {
    function description() external pure returns (string memory) {
        return "This contract cannot receive ERC-223 tokens";
    }
}
