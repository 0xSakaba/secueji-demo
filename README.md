# secueji-demo

Sandbox smart contracts used as the demo target project for
secueji. They reproduce a common escrow control
gap and show one way to close it on-chain.

Not audited. Mock funds only. Deploy only to local chains and testnets.

## Contracts

| Contract | Purpose |
|---|---|
| `DemoStablecoin` | Minimal 6-decimal ERC20 ("Demo USD", `dUSD`) used as settlement currency |
| `DemoEscrow` | Escrow whose release authority is only `msg.sender == escrow.oracle`. This is the control gap: the contract knows nothing about application-level approval |
| `GuardExecutor` | Acts as the oracle for guarded escrows. Releases only with a human EIP-712 approval and a platform authorization over the same intent |

The contracts have no external dependencies. `forge-std` is only used by the
tests and scripts.

### Legacy and guarded mode

Both modes use the same `DemoEscrow`. The oracle picked when an escrow is
created decides the mode:

- **Legacy**: the oracle is an EOA. Whoever holds that key can release funds
  without any approval.
- **Guarded**: the oracle is `GuardExecutor`. Funds move only through
  `GuardExecutor.execute` with valid signatures. The old oracle EOA can no
  longer release.

Because of this, one fixture can be replayed in both modes.

## Roles and permissions

| Role | Where | Can do |
|---|---|---|
| Minter | `DemoStablecoin.minter` (deployer, immutable) | `mint` |
| Admin | `DemoEscrow.admin` (deployer, immutable) | `createEscrow`, `refund` (Funded), `cancel` (Created) |
| Buyer | per escrow | `fund` (moves `amount` from buyer to escrow; needs allowance) |
| Oracle | per escrow (EOA or `GuardExecutor`) | `release` (pays the seller) |
| Owner | `GuardExecutor.owner` (deployer) | `setApprover`, `setPlatformSigner`, `transferOwnership` |
| Approver | `GuardExecutor.isApprover` | Signs `ReleaseIntent` (EIP-712) off-chain |
| Platform signer | `GuardExecutor.platformSigner` | Signs `Authorization` (EIP-712) off-chain |
| Anyone | | Submits a valid bundle to `GuardExecutor.execute`; the signatures are the authority |

Escrow lifecycle: `Created → Funded → Released | Refunded`, or
`Created → Cancelled`. Terms are fixed at creation and release is one-shot, so
an escrow can never pay out twice.

### What GuardExecutor checks, in order

1. Intent targets the configured escrow contract → `WrongEscrowContract`
2. Intent nonce unused → `NonceUsed`
3. Intent not expired → `IntentExpired`
4. Approval signer is a registered approver → `ApprovalInvalid`
5. Authorization binds the same intent hash, nonce and policy version → `AuthorizationMismatch`
6. Authorization not expired → `AuthorizationExpired`
7. Authorization signed by the platform signer → `AuthorizationInvalid`
8. Intent matches on-chain terms (oracle, Funded state, beneficiary, token, amount, titleId) → `TermsMismatch(field)`

Then it consumes the nonce, emits `GuardedRelease` and calls `release`.
Nonces are global per `GuardExecutor`. EIP-712 domain: name `GuardExecutor`,
version `1`.

## Requirements

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
  (tested with forge 1.5.1). `solc 0.8.28` is fetched automatically.
- git (dependencies are git submodules)

## Setup

```sh
git clone --recurse-submodules https://github.com/0xsakaba/secueji-demo.git
cd secueji-demo
# already cloned without submodules?
git submodule update --init --recursive
```

The only dependency is `forge-std`, pinned to `v1.16.2` in `lib/forge-std`.

## Build and test

```sh
forge build
forge test          # add -vvv for traces
```

| Suite | Covers |
|---|---|
| `test/DemoStablecoin.t.sol` | Minting, transfers, allowances |
| `test/DemoEscrow.t.sol` | Create/fund, legacy release with no approval, one-shot release, oracle-only release (fuzz), refund, cancel |
| `test/GuardExecutor.t.sol` | Valid guarded release, missing/foreign approval, oracle EOA bypass, terms mismatches, nonce replay, expired intent/authorization, mismatched or forged authorization, wrong escrow contract |

Test names carry scenario (`S-xxx`) and acceptance-criterion (`AC-xxx`) IDs
from the secueji MVP spec.

## Deploy to local anvil

1. Start a local chain in a separate terminal:

   ```sh
   anvil
   ```

   anvil prints ten funded accounts with their private keys.

2. Create `.env` from the template and fill it in:

   ```sh
   cp .env.example .env
   ```

   - `DEPLOYER_PRIVATE_KEY`: one of anvil's private keys
   - `PLATFORM_SIGNER_ADDRESS`, `APPROVER_ADDRESS`: two other anvil addresses
     (keep their keys for signing intents and authorizations off-chain)

3. Deploy:

   ```sh
   set -a; source .env; set +a
   forge script script/Deploy.s.sol --rpc-url "$RPC_URL" --broadcast
   ```

   The script logs the `DemoStablecoin`, `DemoEscrow` and `GuardExecutor`
   addresses. The deployer becomes minter, escrow admin and guard owner.

4. Optional: seed one funded escrow per mode. Put the deployed addresses and
   `BUYER_PRIVATE_KEY`, `SELLER_ADDRESS`, `LEGACY_ORACLE_ADDRESS` into `.env`,
   then:

   ```sh
   set -a; source .env; set +a
   forge script script/Seed.s.sol --rpc-url "$RPC_URL" --broadcast
   ```

   This creates escrow `1` (legacy, EOA oracle) and escrow `2` (guarded,
   `GuardExecutor` oracle), each funded with 18,450 dUSD.

Private keys are only read from environment variables. `.env` and
`broadcast/` are git-ignored.

## Deploy to a testnet (placeholder)

Not set up yet. The target testnet, the RPC provider account (for example
Alchemy) and the deployer key will be provided later. No credentials are
stored in this repository.

When they are available:

1. Set `RPC_URL` in `.env` to the provider's HTTPS endpoint for the chosen
   testnet, and set `DEPLOYER_PRIVATE_KEY` to a funded testnet-only key.
2. Set `PLATFORM_SIGNER_ADDRESS` and `APPROVER_ADDRESS`.
3. Run the same command as for anvil. To verify the sources, also set
   `ETHERSCAN_API_KEY` and add `--verify`:

   ```sh
   set -a; source .env; set +a
   forge script script/Deploy.s.sol --rpc-url "$RPC_URL" --broadcast --verify
   ```

4. Record the deployed addresses (they are also in
   `broadcast/Deploy.s.sol/<chainId>/run-latest.json`, which stays local).

## Layout

```
src/        contracts
test/       forge tests
script/     Deploy.s.sol, Seed.s.sol
lib/        forge-std (git submodule)
```

## Open items

- License is `UNLICENSED` pending a decision.
- Approver set and platform signer are owner-managed single keys; no multisig
  or rotation policy.
- Testnet choice, RPC endpoint and deployer key are still to be provided.
