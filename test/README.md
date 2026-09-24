# Foundry tests

Run from the project root:

```sh
forge test -vv
forge fmt --check
```

Foundry downloads Solidity 0.8.30 on the first build if it is not cached.
Source pragmas allow versions from 0.8.30 up to (but excluding) 0.9.0, so an
editor using 0.8.37 does not report an exact-version mismatch. `foundry.toml`
still pins test compilation to 0.8.30 for reproducibility.
No `forge-std` installation is required. The tests import the project contracts
and local receiver mocks. The small `Vm` interface declares only the built-in
Foundry cheatcodes used here:

- `prank`: make the next contract call originate from a chosen test address.
- `expectRevert`: require the next call to revert, optionally matching its exact error.
- `expectEmit`: check the next expected event's emitting contract, topics and data.
- `mockCall`: simulate a false transfer result to verify withdrawal credit rollback.

Solidity `require` statements are assertions: a false condition fails the test.
`setUp()` creates a fresh token and example receivers before every test case.
Mock contracts in `helpers/ReceiverMocks.sol` simulate receiver behavior and are
test fixtures, not contracts intended for deployment.

## Coverage of assignment behavior

| Behavior | Tests |
| --- | --- |
| Wallet transfers | Both overloads; balances and transfer events |
| Accepting contract | Both overloads; balances, deposit credits and events |
| Missing hook | Both overloads revert and preserve balances |
| Hook explicitly rejects | Both overloads propagate rejection and preserve balances |
| Incorrect acceptance value | Both overloads revert; token and receiver storage roll back |
| Empty fallback | Both overloads reject a fallback that returns no acceptance value |
| Insufficient balance | Both overloads revert without creating a deposit |
| Zero destination | Both overloads reject the zero address |
| Hook arguments and ordering | Original sender, token caller, amount, data and updated balances |
| Boundary behavior | Zero transfers, self-transfer of full supply and empty payload |
| Receiver authentication | Direct forged calls and transfers from another token revert |
| Withdrawals | Return deposited tokens; reject excess or another user's withdrawal |
| Callback interaction | Forwarding works; outer rejection reverses nested transfers |
| Withdrawal callback | Cannot spend the same credit twice; rejection restores credit |
| Constructor limitation | No hook during construction; missing hook rejected after deployment |
| Fuzz properties | Supply conservation and deposit/withdrawal round trips |

The two fuzz tests each ran 256 generated cases in the verified run. They vary
the amount from zero through the entire supply and select either transfer overload.
Dedicated tests cover full-supply self-transfer and zero values independently.

## Verified result

`forge test -vv`: **37 passed, 0 failed, 0 skipped**, using Foundry 1.7.1 and
Solidity 0.8.30. The four production Solidity files also compiled successfully.

In the restricted workspace, Foundry printed a non-failing warning that it could
not write its global signature cache. The test command still exited successfully.
Transfer return values are checked in the withdrawal and test mocks. The shared
test helper returns the result for assertions in successful wallet and receiver
tests. One intentional negative test has a line-specific lint exemption: its
`expectRevert` verifies the exact rejection error rather than a return value.
This example is configured for this project's token; it is not a receiver for
arbitrary ERC-20 implementations.

These tests establish the listed behaviors; they are not a security audit or a
claim that receiver hooks prevent every possible loss. In particular, a recipient
can accept tokens without providing recovery, and code detection cannot identify
a contract while its constructor is running.

## AI work record for the design note

Codex generated the test suite, mocks and these testing instructions, ran Foundry,
and interpreted the results. The first test compilation failed because the
conditional expression `withData ? hex"1234" : bytes("")` mixed inferred types.
Codex changed the first branch to `bytes(hex"1234")`; compilation and all tests
then passed. No changes to production contracts were needed during this test stage.
In a later compiler-compatibility fix, Codex changed all six source pragmas from
`0.8.30` to `^0.8.30` after the user's editor reported that its 0.8.37 compiler
could not compile an exact-0.8.30 source. The Foundry compiler pin was retained.
Human review and understanding must not be claimed until actually performed.
Codex subsequently addressed unchecked-transfer warnings by checking return values
in the receiver and mocks, asserting successful results in transfer tests, and
documenting a single-line exemption for an intentionally reverting test call.
An additional test simulates a false transfer result and verifies that the new
withdrawal check reverts while preserving the user's deposit credit and balances.
