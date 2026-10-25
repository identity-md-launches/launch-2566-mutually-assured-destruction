# MAD token tests

The original deployment, metadata, transfer, event, and launch-transfer tests remain in
`MADToken.t.sol`. `MADToken.adversarial.t.sol` adds allowance isolation and replay cases,
maximum finite approvals, self-transfer failures, malformed calldata, nonpayable-call
failures, and recovery after a rejected delegated transfer. Its round-trip and split-spend
properties compare observable state across equivalent operations. State snapshots include
every balance and allowance pair reachable by that fixture.

`MADToken.invariant.t.sol` uses four actors and a separate balance/allowance ledger. Only
the handler is targeted. Its nine actions mix transfers, approvals, delegated transfers,
and expected rejections for insufficient balance, insufficient allowance, zero recipients,
and zero spenders. After each action, the suite checks:

- The actors' balances equal the ledger and sum to the original `10^27` units.
- Total supply remains fixed, and no tokens escape the tracked population.
- Every actor-to-actor allowance matches the approvals and successful spending recorded
  by the handler; rejected calls preserve that ledger.
- Zero-address allowances remain zero, and metadata remains unchanged.

Expected failures require the complete ERC-6093 error payload. Unexpected handler reverts
fail the campaign. A funded-actor action guarantees positive delegated spending without
waiting for unrelated random approvals to coincide. A deterministic regression drives all
nine actions and checks that spending still works after failures.

Inline configuration runs each fuzz property 1,000 times and runs 256 invariant sequences
of 128 calls. Amounts are bounded to the operation's domain; ordinary approval inputs also
exercise the full `uint256` range. No input-discarding assumptions are used.

From the repository root, the following commands keep generated artifacts in disposable
scratch space and use the assignment's seed:

```sh
forge build --offline --out test/scratch/out --cache-path test/scratch/cache
FOUNDRY_FUZZ_SEED=0x81e8965f7ce022072a148410da83272e0a0cc641eba1a11ba175ca4e59820c0b forge test --offline --out test/scratch/out --cache-path test/scratch/cache
```

The tests require no network or additional dependencies. These are local token tests;
the existing launch-flow fixture checks token delivery amounts, not actual Uniswap pool
settlement. The supplied protected launch harness is not part of this repository's runnable
suite. No production contract or repository configuration is changed by this contribution.
