// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC223Receiver} from "./interfaces/IERC223Receiver.sol";

/// @notice Fixed-supply ERC-223 token with explicit receiver acceptance.
/// @dev This implementation requires the acceptance selector even for fallback handlers.
///      Transfers do not accept ETH. There are no approvals or administrative transfers.
contract ERC223Token {
    string public name;
    string public symbol;
    uint8 public constant decimals = 18;
    uint256 public immutable totalSupply;
    mapping(address owner => uint256 balance) public balanceOf;

    error ZeroAddress();
    error InsufficientBalance(uint256 available, uint256 requested);
    error InvalidReceiverResponse(address receiver);

    event Transfer(address indexed from, address indexed to, uint256 value, bytes data);

    /// @notice Allocate initialSupply base units to the deploying address once.
    /// @dev Initial allocation is minting, not a transfer; no receiver hook is called.
    constructor(string memory tokenName, string memory tokenSymbol, uint256 initialSupply) {
        name = tokenName;
        symbol = tokenSymbol;
        totalSupply = initialSupply;
        balanceOf[msg.sender] = initialSupply;
        emit Transfer(address(0), msg.sender, initialSupply, "");
    }

    /// @notice Transfer tokens with an empty data payload.
    /// @dev Spec: https://eips.ethereum.org/EIPS/eip-223#transferaddress-uint
    function transfer(address to, uint256 value) external returns (bool) {
        return _transfer(msg.sender, to, value, "");
    }

    /// @notice Transfer tokens and pass data to a contract receiver.
    /// @dev Spec: https://eips.ethereum.org/EIPS/eip-223#transferaddress-uint-bytes
    function transfer(address to, uint256 value, bytes calldata data) external returns (bool) {
        return _transfer(msg.sender, to, value, data);
    }

    /// @dev Shared path ensures neither overload bypasses receiver validation.
    function _transfer(address from, address to, uint256 value, bytes memory data)
        internal
        returns (bool)
    {
        if (to == address(0)) revert ZeroAddress();
        uint256 available = balanceOf[from];
        if (value > available) revert InsufficientBalance(available, value);

        // Complete accounting before invoking untrusted receiver code.
        // Sequential updates also preserve balances for self-transfers.
        balanceOf[from] = available - value;
        balanceOf[to] += value;
        emit Transfer(from, to, value, data);

        // Code length is checked at this moment. Contracts under construction
        // and addresses where code will be deployed later have no runtime code yet.
        if (to.code.length > 0) {
            bytes4 response = IERC223Receiver(to).tokenReceived(from, value, data);
            if (response != IERC223Receiver.tokenReceived.selector) {
                revert InvalidReceiverResponse(to);
            }
        }
        // Hook failure rolls back balances, logs, and nested receiver changes.
        return true;
    }
}
