pragma solidity ^0.8.30;

import {ERC223Token} from "../ERC223Token.sol";
import {IERC223Receiver} from "../interfaces/IERC223Receiver.sol";

contract AcceptingReceiver is IERC223Receiver {
    ERC223Token public immutable token;
    mapping(address depositor => uint256 amount) public deposits;

    error InvalidToken();
    error UnauthorizedToken(address caller);
    error InsufficientDeposit(uint256 available, uint256 requested);
    error TransferFailed();

    event DepositReceived(address indexed from, uint256 value, bytes data);

    constructor(ERC223Token acceptedToken) {
        if (address(acceptedToken).code.length == 0) revert InvalidToken();
        token = acceptedToken;
    }

    function tokenReceived(address from, uint256 value, bytes calldata data)
        external
        override
        returns (bytes4)
    {
        if (msg.sender != address(token)) revert UnauthorizedToken(msg.sender);
        deposits[from] += value;
        emit DepositReceived(from, value, data);
        return IERC223Receiver.tokenReceived.selector;
    }

    function withdraw(uint256 value) external {
        uint256 available = deposits[msg.sender];
        if (value > available) revert InsufficientDeposit(available, value);
        deposits[msg.sender] = available - value;
        if (!token.transfer(msg.sender, value)) revert TransferFailed();
    }
}
