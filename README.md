# Mutually Assured Destruction (MAD)

MAD is a fixed-supply ERC-20. Its constructor mints **1,000,000,000 MAD with 18 decimals**, all to the immediate deployer, exactly once.

## Contract and assumptions

| Parameter | Value |
| --- | --- |
| Solidity contract | `src/MADToken.sol:MADToken` |
| Name | `Mutually Assured Destruction` |
| Symbol | `MAD` |
| Decimals | `18` |
| Total supply in smallest units | `1000000000000000000000000000` (`10^27`) |
| Supply constant | `INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18` |
| Constructor arguments / native value | None / zero |
| Initial recipient | Constructor `msg.sender` |
| Administration / initialization | None |

The name is branding: the brief specifies no destruction or other special transfer mechanic. The implementation has no public mint or burn, fees, rebasing, pausing, blacklisting, confiscation, owner, upgrade mechanism, or external callbacks. Supply remains constant after construction. Transferring to the zero address reverts, including for zero amounts. Zero-value transfers between valid addresses succeed and emit `Transfer`.

The token uses the unmodified OpenZeppelin Contracts v5.1.0 ERC-20 implementation. Successful `transfer`, `approve` and `transferFrom` return `true`; invalid operations revert with ERC-6093 custom errors. A transfer requires sufficient balance. Delegated transfers additionally require the caller's allowance, including when the caller is the holder. Finite allowances decrease when spent; `type(uint256).max` represents unlimited allowance and is not decreased. `approve` replaces the existing allowance and emits `Approval`; `transferFrom` emits `Transfer` but does not emit an allowance-update `Approval`.

## Build and check

Run from the repository root with Foundry and Solidity **0.8.26** installed:

```sh
forge build
FOUNDRY_FUZZ_SEED=0x81e8965f7ce022072a148410da83272e0a0cc641eba1a11ba175ca4e59820c0b forge test
forge fmt --check
```

`foundry.toml` pins Solidity 0.8.26, Cancun EVM, optimizer enabled with 200 runs, and `bytecode_hash = "none"`. It enables neither FFI nor filesystem permissions. All Solidity dependencies are ordinary files under `lib/`; builds and tests need no network, package installation, RPC, keys, environment lookups, or Git submodules. The seed above is optional for running locally but reproduces the assignment's fuzz seed. Test code never reads or changes environment variables.

The unit and fuzz suite covers exact metadata and supply, a single constructor mint event, direct and factory deployment (including CREATE2), transfers and events, zero and maximum values, self-transfers, approvals, revocation, finite and unlimited allowances, rejected unauthorized operations, rollback after failures, and absence of common administrative entry points. Launch-flow tests model the token transfers for distribution, claims, purchases and sales; they do not simulate Uniswap pricing or settlement. Stateful invariants exercise sequences of transfers, approvals and delegated transfers against a separate balance and allowance ledger across four actors. Fuzz tests run 512 cases each; invariants run 128 sequences of up to 64 calls each with unexpected reverts treated as failures. Test addresses are local fixtures, not deployment parameters.

## Deployment and launch integration

Deploy the creation bytecode for **`MADToken`** directly with no appended arguments and no ETH. Both CREATE and CREATE2 work. The compiled artifact is `out/MADToken.sol/MADToken.json`; there are no linked libraries, proxy, initializer or companion application contracts. The constructor does not call any external contract and can run on an empty chain. A factory deployment gives the entire supply to the factory, not the factory's caller or transaction origin. A direct deployment gives the supply to that direct deployer. The constructor emits `Transfer(address(0), deployer, 10^27)`.

The intended launch chain is Ethereum (chain ID 1). The token itself needs no chain addresses or owner settings. All factory, distributor and pool transfers receive exactly the requested amount, with no exemptions to configure. Launch allocations are performed by the launch factory after construction; they are not performed or reserved by this token:

- 10% (`100,000,000 MAD`) goes to the launch's MerkleDistributor.
- 50% (`500,000,000 MAD`) is the pool allocation.
- The remaining 40% (`400,000,000 MAD`) goes to `0xee2aaa315cf7ed169f93148d30d24af9318dbb66`.

The supplied launch terms name paired currency IMD at `0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7`, pool fee `12500` (1.25%), tick spacing `60`, provenance initial price `79228162514264337593543950336`, and initial market cap `2500000000000000000000` paired-currency minor units. The launch system derives the actual opening price and handles liquidity. These terms are documented inputs, not addresses called by MAD or network state verified by this project. They add no constructor parameters. The subsequent manifest step owns `launch.json`; this project supplies the token artifact and no application contracts.

## After launch

No owner settings, privileged keys, maintenance transactions or external services are required by MAD. The launch operator is responsible for deploying the reviewed artifact with the pinned settings, verifying source and deployed bytecode, checking metadata and the constructor supply/event, and completing the factory's distribution and pool operations under the supplied launch terms. No deployment or transaction broadcast is included here.

Holders control their balances and approvals. Applications should request only the allowance they need and handle reverts. When replacing a nonzero allowance, holders should first set it to zero and wait for confirmation to mitigate the standard ERC-20 allowance-change race; this cannot undo spending that already happened. Allowance tracking should query `allowance`, since spending does not emit `Approval` in this implementation. Sending tokens to the token contract or another contract without a withdrawal mechanism may strand them permanently; there is no administrator or rescue function. Ordinary ETH transfers are rejected.

## Review scope

The implementation limits custom logic to a constructor mint and a supply constant. Review considered access control, fixed supply, arithmetic, exact transfers, allowances, rollback, zero addresses, deployment context and external-call exposure. Production token code makes no external calls, so transfers cannot invoke a recipient or reenter through a hook. There are no signatures, oracles, randomness, vaults, proxies or dependencies on time. OpenZeppelin's internal `_mint` and `_burn` helpers have no post-construction external entry point in `MADToken`.

Local build, unit tests, fuzz tests and invariant tests are the project's checks. The supplied protected launch checks depend on the network's separate factory harness, manifest inputs and Uniswap dependencies; their execution belongs to independent launch verification. Slither and Mythril were not run. An independent adversarial review and deployment verification remain the launch process's responsibilities; passing this suite is not a security audit.

## Dependency provenance and licenses

`dependencies.lock.json` records upstream release archive URLs, SHA-256 archive digests and per-file SHA-256 hashes. Vendored files are unmodified upstream copies:

- [OpenZeppelin Contracts v5.1.0](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.1.0): only ERC-20 and its transitive Solidity imports, plus the MIT license, under `lib/openzeppelin-contracts/`.
- [forge-std v1.9.4](https://github.com/foundry-rs/forge-std/tree/v1.9.4): test sources and both MIT/Apache-2.0 licenses under `lib/forge-std/`.

ERC-20 behavior follows the [token standard](https://eips.ethereum.org/EIPS/eip-20). Project code is MIT licensed; dependency license notices are retained in their respective directories.
