pragma solidity ^0.8.30;

import {IERC223Receiver} from "./interfaces/IERC223Receiver.sol";

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

    constructor(string memory tokenName, string memory tokenSymbol, uint256 initialSupply) {
        name = tokenName;
        symbol = tokenSymbol;
        totalSupply = initialSupply;
        balanceOf[msg.sender] = initialSupply;
        emit Transfer(address(0), msg.sender, initialSupply, "");
    }

    function transfer(address to, uint256 value) external returns (bool) {
        return _transfer(msg.sender, to, value, "");
    }

    function transfer(address to, uint256 value, bytes calldata data) external returns (bool) {
        return _transfer(msg.sender, to, value, data);
    }

    function _transfer(address from, address to, uint256 value, bytes memory data)
        internal
        returns (bool)
    {
        if (to == address(0)) revert ZeroAddress();
        uint256 available = balanceOf[from];
        if (value > available) revert InsufficientBalance(available, value);

        balanceOf[from] = available - value;
        balanceOf[to] += value;
        emit Transfer(from, to, value, data);

        if (to.code.length > 0) {
            bytes4 response = IERC223Receiver(to).tokenReceived(from, value, data);
            if (response != IERC223Receiver.tokenReceived.selector) {
                revert InvalidReceiverResponse(to);
            }
        }
        return true;
    }
}
