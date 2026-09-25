# ERC-223 Token Design Note

**Standard and scope.** This project implements the assignment's ERC-223 transfer
scope: a fixed-supply token, ordinary transfers to addresses without code, and a
receiver callback for destinations with deployed code. It includes
`AcceptingReceiver`, which credits deposits and supports withdrawal, and
`NonReceiver`, which deliberately lacks the hook. Both transfer overloads enforce
the same checks. Approvals, administrative transfers, freezing, and ETH transfers
are outside this implementation's scope.

**The exact ERC-20 failure prevented.** ERC-20's ordinary `transfer()` updates
balances without requiring the recipient contract to execute a receiving hook.
Consequently, a transfer can succeed even though the contract cannot credit or
recover the tokens. This is an unhandled contract receipt, not a failure to update
the token's balances. See [ERC-20 transfer](https://eips.ethereum.org/EIPS/eip-20#transfer).

For a concrete example, suppose Alice owns 100 tokens. A vault credits users only
through its `deposit()` function, which calls `transferFrom()` after approval.
Alice mistakenly calls `token.transfer(vault, 10)` instead. Her token balance
becomes 90 and the vault's becomes 10, but `deposits[Alice]` remains zero because
`deposit()` never ran. If withdrawals require recorded credit and the vault has
no recovery function, Alice cannot retrieve those 10 tokens. This illustrates the
failure described in [ERC-223's compatibility example](https://eips.ethereum.org/EIPS/eip-223#backwards-compatibility).

With this project's token, sending to that vault without a compatible hook
reverts: Alice retains 100 tokens and the vault receives none. Sending instead
to `AcceptingReceiver` invokes `tokenReceived()`, credits Alice with 10, and allows
her to withdraw later. A reverting hook or incorrect acceptance response also
reverses the transfer. Gas spent on a reverted transaction is still charged.

**Function-to-spec mapping.** Public token variables generate the standard getter
functions automatically; internal helpers and example-only functions are
identified separately below.

| Implemented function or event | Specification section or project role |
| --- | --- |
| `name()`, `symbol()`, `decimals()` | [name](https://eips.ethereum.org/EIPS/eip-223#name), [symbol](https://eips.ethereum.org/EIPS/eip-223#symbol), [decimals](https://eips.ethereum.org/EIPS/eip-223#decimals) |
| `totalSupply()`, `balanceOf(address)` | [totalSupply](https://eips.ethereum.org/EIPS/eip-223#totalsupply), [balanceOf](https://eips.ethereum.org/EIPS/eip-223#balanceof) |
| `transfer(address,uint256)` | [Two-argument transfer](https://eips.ethereum.org/EIPS/eip-223#transferaddress-uint) |
| `transfer(address,uint256,bytes)` | [Transfer with data](https://eips.ethereum.org/EIPS/eip-223#transferaddress-uint-bytes) |
| `tokenReceived(address,uint256,bytes)` interface and implementation | [Receiver methods](https://eips.ethereum.org/EIPS/eip-223#receiver-methods) |
| `Transfer` event | [Transfer event](https://eips.ethereum.org/EIPS/eip-223#transfer) |
| Token constructor; `_transfer()` | Project-specific initial allocation; shared implementation of both transfer sections |
| Receiver constructor; `token()`; `deposits(address)`; `withdraw(uint256)` | Example configuration, accounting, and recovery; not standard-required methods |
| `NonReceiver.description()` | Example-only explanatory function |

**Three design decisions.** First, require the receiver's `0x8943ec02` acceptance
value. The [receiver section](https://eips.ethereum.org/EIPS/eip-223#receiver-methods)
also permits fallback handling without that value; this implementation deliberately
uses a stricter policy, rejecting empty or incorrect responses. A fallback that
returns the correct encoded value can still satisfy the check.
The trade-off is explicit acknowledgement at the cost of compatibility with
fallback receivers that the specification permits to return no acceptance value.

Second, complete balance updates before calling receiver code. Withdrawals also
debit credit before transferring. Callbacks therefore observe updated accounting;
a failure rolls back all associated changes. The receiver authenticates the token
caller to prevent forged deposits, and withdrawal checks the transfer's Boolean
result. Tests exercise nested transfers and attempts to withdraw credit twice.
This follows the ordering required by the
[transfer specification](https://eips.ethereum.org/EIPS/eip-223#transferaddress-uint-bytes).
The implementation permits callbacks to forward their newly received tokens;
it does not prohibit reentrancy generally. Each receiving application must protect
its own accounting before making external calls.

Third, use `to.code.length` to decide whether to invoke the hook. This is simple,
but cannot identify contracts during construction or before deployment. A test
demonstrates this limit. Acceptance also cannot prove that a receiver provides
safe recovery, and transfers to an unintended ordinary wallet remain possible.
Initial supply allocation to the deployer is separate from transfers and does not
invoke a hook.

**Meaningful coverage and failure cases.** Tests check resulting balances, deposit
credits, callback arguments, events, and rollback, rather than only successful
return values. Negative cases include missing hooks, explicit rejection, wrong
acceptance values, empty fallback responses, insufficient funds, zero destinations,
forged deposits, untrusted tokens, and excessive withdrawals. Callback tests
verify that an outer rejection reverses a nested transfer and that a withdrawal
cannot spend the same credit twice. The two fuzz tests exercise supply conservation
and deposit-withdrawal round trips. The constructor test documents a known limit;
it does not demonstrate that the limit has been eliminated. See the
[test guide](test/README.md) and [test implementation](test/ERC223Token.t.sol).
Passing 37 tests is not a line or branch coverage percentage, a security audit,
or proof that all possible receiver behaviour is safe. No gas benchmark was run,
so this project does not claim a measured gas saving over ERC-20.

**Validation and AI disclosure.** The last verified Foundry run passed 37 tests,
including two fuzz tests with 256 generated cases each. Both overloads are tested
for success and receiver failures. The [discussion thread](https://ethereum-magicians.org/t/erc-223-token-standard/12894)
also informed zero-value callback tests. Codex generated the contracts, tests,
configuration, and documentation and ran the checks. Corrections to AI output
included a test `bytes` conversion, changing exact pragmas to `^0.8.30` for editor
compatibility while retaining Foundry's compiler pin, and checking previously
ignored transfer results. One intentional rejection test has a documented,
line-specific lint exemption. Human review is not claimed by this note.
