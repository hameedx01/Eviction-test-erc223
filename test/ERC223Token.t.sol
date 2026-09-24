// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC223Token} from "../src/ERC223Token.sol";
import {IERC223Receiver} from "../src/interfaces/IERC223Receiver.sol";
import {AcceptingReceiver} from "../src/examples/AcceptingReceiver.sol";
import {NonReceiver} from "../src/examples/NonReceiver.sol";
import {
    RecordingReceiver,
    RejectingReceiver,
    WrongValueReceiver,
    EmptyFallbackReceiver,
    ForwardingReceiver,
    ReenteringDepositor,
    ConstructionSender,
    ConstructorRecipient
} from "./helpers/ReceiverMocks.sol";

/// @dev Minimal interface to Foundry's built-in cheatcodes, not a deployed dependency.
interface Vm {
    function prank(address sender) external;
    function expectRevert() external;
    function expectRevert(bytes calldata revertData) external;
    function expectEmit(bool topic1, bool topic2, bool topic3, bool data, address emitter) external;
    function mockCall(address target, bytes calldata callData, bytes calldata returnData) external;
}

contract ERC223TokenTest {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    uint256 private constant SUPPLY = 1_000_000 ether;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    uint256 private constant AMOUNT = 10 ether;

    ERC223Token private token;
    AcceptingReceiver private receiver;
    NonReceiver private nonReceiver;

    event Transfer(address indexed from, address indexed to, uint256 value, bytes data);
    event DepositReceived(address indexed from, uint256 value, bytes data);

    function setUp() public {
        vm.prank(ALICE);
        token = new ERC223Token("Assignment Token", "ASG", SUPPLY);
        receiver = new AcceptingReceiver(token);
        nonReceiver = new NonReceiver();
    }

    function testInitialSupplyAndMetadata() public view {
        require(keccak256(bytes(token.name())) == keccak256("Assignment Token"), "name");
        require(keccak256(bytes(token.symbol())) == keccak256("ASG"), "symbol");
        require(token.decimals() == 18, "decimals");
        require(token.totalSupply() == SUPPLY, "supply");
        require(token.balanceOf(ALICE) == SUPPLY, "initial allocation");
        require(token.balanceOf(BOB) == 0, "unfunded wallet");
        require(IERC223Receiver.tokenReceived.selector == bytes4(0x8943ec02), "hook selector");
    }

    function testWalletTransferWithoutData() public {
        _walletTransfer(false);
    }

    function testWalletTransferWithData() public {
        _walletTransfer(true);
    }

    function testReceiverTransferWithoutData() public {
        _receiverTransfer(false);
    }

    function testReceiverTransferWithData() public {
        _receiverTransfer(true);
    }

    function testMissingHookRevertsWithoutData() public {
        _missingHook(false);
    }

    function testMissingHookRevertsWithData() public {
        _missingHook(true);
    }

    function testRejectingHookRevertsWithoutData() public {
        _rejectingHook(false);
    }

    function testRejectingHookRevertsWithData() public {
        _rejectingHook(true);
    }

    function testWrongReturnRollsBackWithoutData() public {
        _wrongReturn(false);
    }

    function testWrongReturnRollsBackWithData() public {
        _wrongReturn(true);
    }

    function testEmptyFallbackRevertsWithoutData() public {
        _emptyFallback(false);
    }

    function testEmptyFallbackRevertsWithData() public {
        _emptyFallback(true);
    }

    function testInsufficientBalanceWithoutData() public {
        _insufficientBalance(false);
    }

    function testInsufficientBalanceWithData() public {
        _insufficientBalance(true);
    }

    function testZeroAddressRevertsWithoutData() public {
        _zeroAddress(false);
    }

    function testZeroAddressRevertsWithData() public {
        _zeroAddress(true);
    }

    function testSelfTransferPreservesBalance() public {
        _send(ALICE, SUPPLY, false);
        _send(ALICE, SUPPLY, true);
        require(token.balanceOf(ALICE) == SUPPLY, "self-transfer changed balance");
    }

    function testZeroTransferToWallet() public {
        _send(BOB, 0, false);
        _send(BOB, 0, true);
        _assertUnchanged(BOB);
    }

    function testZeroTransferStillCallsHook() public {
        RecordingReceiver recorder = new RecordingReceiver(token);
        _send(address(recorder), 0, false);
        _send(address(recorder), 0, true);
        require(recorder.calls() == 2, "zero transfer bypassed hook");
        _assertUnchanged(address(recorder));
    }

    function testZeroTransferToNonReceiverStillReverts() public {
        vm.expectRevert();
        _send(address(nonReceiver), 0, false);
        vm.expectRevert();
        _send(address(nonReceiver), 0, true);
        _assertUnchanged(address(nonReceiver));
    }

    function testHookObservesUpdatedBalancesAndOriginalSender() public {
        RecordingReceiver recorder = new RecordingReceiver(token);
        _send(address(recorder), AMOUNT, true);
        require(recorder.caller() == address(token), "hook caller must be token");
        require(recorder.sender() == ALICE, "original sender lost");
        require(recorder.amount() == AMOUNT, "wrong callback amount");
        require(keccak256(recorder.payload()) == keccak256(hex"1234"), "payload lost");
        require(recorder.calls() == 1, "duplicate callback");
        require(recorder.balanceDuringHook() == AMOUNT, "recipient balance stale");
        require(recorder.senderBalanceDuringHook() == SUPPLY - AMOUNT, "sender balance stale");
    }

    function testNoDataOverloadPassesEmptyBytes() public {
        RecordingReceiver recorder = new RecordingReceiver(token);
        _send(address(recorder), AMOUNT, false);
        require(recorder.payload().length == 0, "expected truly empty bytes");
    }

    function testWithdrawalReturnsCreditedTokens() public {
        _send(address(receiver), AMOUNT, true);
        vm.prank(ALICE);
        receiver.withdraw(AMOUNT);
        _assertUnchanged(address(receiver));
        require(receiver.deposits(ALICE) == 0, "credit not debited");
    }

    function testFalseTransferReturnRestoresWithdrawalCredit() public {
        _send(address(receiver), AMOUNT, false);
        // Our token normally returns true or reverts. Simulate a false result
        // to exercise the receiver's defensive return-value check.
        vm.mockCall(
            address(token),
            abi.encodeWithSignature("transfer(address,uint256)", ALICE, AMOUNT),
            abi.encode(false)
        );
        vm.expectRevert(abi.encodeWithSelector(AcceptingReceiver.TransferFailed.selector));
        vm.prank(ALICE);
        receiver.withdraw(AMOUNT);
        require(receiver.deposits(ALICE) == AMOUNT, "credit was not restored");
        require(token.balanceOf(address(receiver)) == AMOUNT, "vault balance changed");
        require(token.balanceOf(ALICE) == SUPPLY - AMOUNT, "sender balance changed");
    }

    function testOverWithdrawalReverts() public {
        _send(address(receiver), AMOUNT, false);
        vm.expectRevert(
            abi.encodeWithSelector(
                AcceptingReceiver.InsufficientDeposit.selector, AMOUNT, AMOUNT + 1
            )
        );
        vm.prank(ALICE);
        receiver.withdraw(AMOUNT + 1);
        require(receiver.deposits(ALICE) == AMOUNT, "credit changed");
        require(token.balanceOf(address(receiver)) == AMOUNT, "receiver balance changed");
    }

    function testAnotherUserCannotWithdrawAliceDeposit() public {
        _send(address(receiver), AMOUNT, false);
        vm.expectRevert(
            abi.encodeWithSelector(AcceptingReceiver.InsufficientDeposit.selector, 0, AMOUNT)
        );
        vm.prank(BOB);
        receiver.withdraw(AMOUNT);
        require(receiver.deposits(ALICE) == AMOUNT, "alice credit changed");
        require(token.balanceOf(BOB) == 0, "unauthorized withdrawal");
    }

    function testForgedDirectHookCallReverts() public {
        vm.expectRevert(abi.encodeWithSelector(AcceptingReceiver.UnauthorizedToken.selector, BOB));
        vm.prank(BOB);
        receiver.tokenReceived(BOB, AMOUNT, "");
        require(receiver.deposits(BOB) == 0, "fabricated credit");
    }

    function testUntrustedTokenIsRejectedAndRolledBack() public {
        vm.prank(ALICE);
        ERC223Token otherToken = new ERC223Token("Other", "OTHER", SUPPLY);
        vm.expectRevert(
            abi.encodeWithSelector(
                AcceptingReceiver.UnauthorizedToken.selector, address(otherToken)
            )
        );
        vm.prank(ALICE);
        // This call must revert with the exact error above; there is no successful
        // transfer result to assert. Suppress only this intentional negative test.
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        otherToken.transfer(address(receiver), AMOUNT);
        require(otherToken.balanceOf(ALICE) == SUPPLY, "untrusted sender balance changed");
        require(otherToken.balanceOf(address(receiver)) == 0, "untrusted transfer persisted");
        require(receiver.deposits(ALICE) == 0, "untrusted deposit credited");
    }

    function testReceiverRejectsTokenAddressWithoutCode() public {
        vm.expectRevert(abi.encodeWithSelector(AcceptingReceiver.InvalidToken.selector));
        new AcceptingReceiver(ERC223Token(BOB));
    }

    function testCallbackCanForwardOnlyItsOwnBalance() public {
        ForwardingReceiver forwarder = new ForwardingReceiver(token, BOB, false);
        _send(address(forwarder), AMOUNT, false);
        require(token.balanceOf(ALICE) == SUPPLY - AMOUNT, "sender debited twice");
        require(token.balanceOf(address(forwarder)) == 0, "forwarder retained tokens");
        require(token.balanceOf(BOB) == AMOUNT, "forwarding failed");
        require(token.totalSupply() == SUPPLY, "supply changed");
    }

    function testOuterRejectionRollsBackNestedTransfer() public {
        ForwardingReceiver forwarder = new ForwardingReceiver(token, BOB, true);
        vm.expectRevert(abi.encodeWithSelector(ForwardingReceiver.RejectedAfterForward.selector));
        _send(address(forwarder), AMOUNT, true);
        _assertUnchanged(address(forwarder));
        require(token.balanceOf(BOB) == 0, "nested transfer survived revert");
    }

    function testReentrantWithdrawalCannotSpendCreditTwice() public {
        ReenteringDepositor depositor = new ReenteringDepositor(token, receiver);
        _send(address(depositor), AMOUNT, false);
        depositor.deposit(AMOUNT);
        depositor.withdraw(AMOUNT, false);
        require(!depositor.nestedWithdrawalSucceeded(), "double withdrawal succeeded");
        require(receiver.deposits(address(depositor)) == 0, "credit remained");
        require(token.balanceOf(address(depositor)) == AMOUNT, "wrong withdrawal amount");
        require(token.balanceOf(address(receiver)) == 0, "vault balance remained");
    }

    function testRejectedWithdrawalRestoresDepositCredit() public {
        ReenteringDepositor depositor = new ReenteringDepositor(token, receiver);
        _send(address(depositor), AMOUNT, false);
        depositor.deposit(AMOUNT);
        vm.expectRevert(abi.encodeWithSelector(ReenteringDepositor.WithdrawalRejected.selector));
        depositor.withdraw(AMOUNT, true);
        require(receiver.deposits(address(depositor)) == AMOUNT, "credit was not restored");
        require(token.balanceOf(address(receiver)) == AMOUNT, "vault balance was not restored");
        require(token.balanceOf(address(depositor)) == 0, "rejected withdrawal persisted");
    }

    function testConstructorCodeDetectionLimitation() public {
        ConstructionSender sender = new ConstructionSender(token);
        _send(address(sender), 2, false);
        ConstructorRecipient recipient = new ConstructorRecipient(sender);
        require(token.balanceOf(address(recipient)) == 1, "constructor transfer did not occur");
        vm.expectRevert();
        _send(address(recipient), 1, false);
        require(token.balanceOf(address(recipient)) == 1, "post-construction transfer persisted");
    }

    function testFuzzWalletTransferConservesSupply(uint256 rawAmount, bool withData) public {
        uint256 value = rawAmount % (SUPPLY + 1);
        _send(BOB, value, withData);
        require(token.balanceOf(ALICE) == SUPPLY - value, "sender accounting");
        require(token.balanceOf(BOB) == value, "recipient accounting");
        require(token.balanceOf(ALICE) + token.balanceOf(BOB) == SUPPLY, "conservation");
        require(token.totalSupply() == SUPPLY, "supply mutated");
    }

    function testFuzzDepositWithdrawalRoundTrip(uint256 rawAmount, bool withData) public {
        uint256 value = rawAmount % (SUPPLY + 1);
        _send(address(receiver), value, withData);
        require(receiver.deposits(ALICE) == value, "wrong deposit credit");
        vm.prank(ALICE);
        receiver.withdraw(value);
        _assertUnchanged(address(receiver));
        require(receiver.deposits(ALICE) == 0, "credit remained after withdrawal");
    }

    function _walletTransfer(bool withData) internal {
        bytes memory data = withData ? bytes(hex"1234") : bytes("");
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(ALICE, BOB, AMOUNT, data);
        require(_send(BOB, AMOUNT, withData), "wallet transfer returned false");
        require(token.balanceOf(ALICE) == SUPPLY - AMOUNT, "sender balance");
        require(token.balanceOf(BOB) == AMOUNT, "wallet balance");
    }

    function _receiverTransfer(bool withData) internal {
        bytes memory data = withData ? bytes(hex"1234") : bytes("");
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(ALICE, address(receiver), AMOUNT, data);
        vm.expectEmit(true, false, false, true, address(receiver));
        emit DepositReceived(ALICE, AMOUNT, data);
        require(_send(address(receiver), AMOUNT, withData), "receiver transfer returned false");
        require(token.balanceOf(ALICE) == SUPPLY - AMOUNT, "sender balance");
        require(token.balanceOf(address(receiver)) == AMOUNT, "receiver balance");
        require(receiver.deposits(ALICE) == AMOUNT, "deposit credit");
    }

    function _missingHook(bool withData) internal {
        vm.expectRevert();
        _send(address(nonReceiver), AMOUNT, withData);
        _assertUnchanged(address(nonReceiver));
    }

    function _rejectingHook(bool withData) internal {
        RejectingReceiver rejector = new RejectingReceiver();
        vm.expectRevert(abi.encodeWithSelector(RejectingReceiver.DepositRejected.selector));
        _send(address(rejector), AMOUNT, withData);
        _assertUnchanged(address(rejector));
    }

    function _wrongReturn(bool withData) internal {
        WrongValueReceiver wrong = new WrongValueReceiver();
        vm.expectRevert(
            abi.encodeWithSelector(ERC223Token.InvalidReceiverResponse.selector, address(wrong))
        );
        _send(address(wrong), AMOUNT, withData);
        _assertUnchanged(address(wrong));
        require(wrong.calls() == 0, "receiver state did not roll back");
    }

    function _emptyFallback(bool withData) internal {
        EmptyFallbackReceiver fallbackReceiver = new EmptyFallbackReceiver();
        vm.expectRevert();
        _send(address(fallbackReceiver), AMOUNT, withData);
        _assertUnchanged(address(fallbackReceiver));
    }

    function _insufficientBalance(bool withData) internal {
        vm.expectRevert(
            abi.encodeWithSelector(ERC223Token.InsufficientBalance.selector, SUPPLY, SUPPLY + 1)
        );
        _send(address(receiver), SUPPLY + 1, withData);
        _assertUnchanged(address(receiver));
        require(receiver.deposits(ALICE) == 0, "failed transfer credited");
    }

    function _zeroAddress(bool withData) internal {
        vm.expectRevert(abi.encodeWithSelector(ERC223Token.ZeroAddress.selector));
        _send(address(0), AMOUNT, withData);
        _assertUnchanged(address(0));
    }

    function _send(address to, uint256 value, bool withData) internal returns (bool) {
        vm.prank(ALICE);
        // Forward the result for happy-path assertions. Negative tests instead
        // use expectRevert, which intercepts the failure and supplies dummy data.
        if (withData) return token.transfer(to, value, hex"1234");
        return token.transfer(to, value);
    }

    function _assertUnchanged(address recipient) internal view {
        require(token.balanceOf(ALICE) == SUPPLY, "sender balance not restored");
        require(token.balanceOf(recipient) == 0, "recipient balance not restored");
        require(token.totalSupply() == SUPPLY, "supply changed");
    }
}
