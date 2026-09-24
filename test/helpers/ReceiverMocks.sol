// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC223Token} from "../../src/ERC223Token.sol";
import {IERC223Receiver} from "../../src/interfaces/IERC223Receiver.sol";
import {AcceptingReceiver} from "../../src/examples/AcceptingReceiver.sol";

/// @dev Test receiver that records exactly what it observes during the callback.
contract RecordingReceiver is IERC223Receiver {
    ERC223Token public immutable token;
    address public caller;
    address public sender;
    uint256 public amount;
    bytes public payload;
    uint256 public calls;
    uint256 public balanceDuringHook;
    uint256 public senderBalanceDuringHook;

    constructor(ERC223Token token_) {
        token = token_;
    }

    function tokenReceived(address from, uint256 value, bytes calldata data)
        external
        returns (bytes4)
    {
        caller = msg.sender;
        sender = from;
        amount = value;
        payload = data;
        calls++;
        balanceDuringHook = token.balanceOf(address(this));
        senderBalanceDuringHook = token.balanceOf(from);
        return IERC223Receiver.tokenReceived.selector;
    }
}

contract RejectingReceiver is IERC223Receiver {
    error DepositRejected();

    function tokenReceived(address, uint256, bytes calldata) external pure returns (bytes4) {
        revert DepositRejected();
    }
}

/// @dev Mutates storage before returning a wrong value to test cross-contract rollback.
contract WrongValueReceiver is IERC223Receiver {
    uint256 public calls;

    function tokenReceived(address, uint256, bytes calldata) external returns (bytes4) {
        calls++;
        return 0xdeadbeef;
    }
}

/// @dev A permissive fallback must not silently count as explicit acceptance.
contract EmptyFallbackReceiver {
    fallback() external {}
}

/// @dev A callback can spend newly received tokens, but cannot debit the original sender.
contract ForwardingReceiver is IERC223Receiver {
    ERC223Token public immutable token;
    address public immutable beneficiary;
    bool public immutable rejectAfterForward;

    error RejectedAfterForward();

    constructor(ERC223Token token_, address beneficiary_, bool reject_) {
        token = token_;
        beneficiary = beneficiary_;
        rejectAfterForward = reject_;
    }

    function tokenReceived(address, uint256 value, bytes calldata) external returns (bytes4) {
        require(msg.sender == address(token), "unexpected token");
        require(token.transfer(beneficiary, value), "forwarding failed");
        if (rejectAfterForward) revert RejectedAfterForward();
        return IERC223Receiver.tokenReceived.selector;
    }
}

/// @dev Tries to withdraw the same credit again from inside a withdrawal callback.
contract ReenteringDepositor is IERC223Receiver {
    ERC223Token public immutable token;
    AcceptingReceiver public immutable vault;
    bool public attacking;
    bool public nestedWithdrawalSucceeded;
    bool public rejectReceipt;

    error WithdrawalRejected();

    constructor(ERC223Token token_, AcceptingReceiver vault_) {
        token = token_;
        vault = vault_;
    }

    function deposit(uint256 value) external {
        require(token.transfer(address(vault), value), "deposit transfer failed");
    }

    function withdraw(uint256 value, bool reject_) external {
        attacking = true;
        rejectReceipt = reject_;
        vault.withdraw(value);
        attacking = false;
    }

    function tokenReceived(address, uint256 value, bytes calldata) external returns (bytes4) {
        require(msg.sender == address(token), "unexpected token");
        if (rejectReceipt) revert WithdrawalRejected();
        if (attacking) {
            attacking = false;
            (nestedWithdrawalSucceeded,) =
                address(vault).call(abi.encodeCall(AcceptingReceiver.withdraw, (value)));
        }
        return IERC223Receiver.tokenReceived.selector;
    }
}

/// @dev Demonstrates that runtime code detection cannot see a constructor in progress.
contract ConstructorRecipient {
    constructor(ConstructionSender sender) {
        sender.sendToCaller();
    }
}

contract ConstructionSender is IERC223Receiver {
    ERC223Token public immutable token;

    constructor(ERC223Token token_) {
        token = token_;
    }

    function sendToCaller() external {
        require(token.transfer(msg.sender, 1), "constructor transfer failed");
    }

    function tokenReceived(address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC223Receiver.tokenReceived.selector;
    }
}
