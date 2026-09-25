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

## Base Sepolia deployment

The demo is deployed on Base Sepolia (chain id `84532`). The full record is
[`deployments/base-sepolia.json`](deployments/base-sepolia.json). It has the
contract addresses, deploy and seed transaction hashes, blocks, role
addresses, the git commit that was deployed and the EIP-712 domain. ABIs are in
[`deployments/abi/`](deployments/abi).

| Contract | Address |
|---|---|
| `DemoStablecoin` (dUSD) | [`0x783BE7bec1a1f1DEFC2fcD77d535E29aBE945200`](https://sepolia.basescan.org/address/0x783BE7bec1a1f1DEFC2fcD77d535E29aBE945200) |
| `DemoEscrow` | [`0xab5fB13532B38043CDc6bf22D4c9e753d10b73B0`](https://sepolia.basescan.org/address/0xab5fB13532B38043CDc6bf22D4c9e753d10b73B0) |
| `GuardExecutor` | [`0x06F0b593C999e45fB0514584D8C15E17673c09FB`](https://sepolia.basescan.org/address/0x06F0b593C999e45fB0514584D8C15E17673c09FB) |

| Role | Address |
|---|---|
| Deployer (minter, escrow admin, guard owner) | [`0x65a7ce7F78f2031Bb8b69b602538153aAcBA5F90`](https://sepolia.basescan.org/address/0x65a7ce7F78f2031Bb8b69b602538153aAcBA5F90) |
| Platform signer | `0x0804e7c36F61a416DB3155CdA388760C24DbDefc` |
| Approver | `0x32758061A72fEac22D549d7953B90dece1443731` |
| Buyer | `0x7D6208024d17fbD699dE085e36bEaAD046f86120` |
| Seller | `0x007Bfb7f3aaAed103f0e21155814D2Ad0006054d` |
| Legacy oracle (EOA) | `0x1CAC9ba3a8DB03076daF6293bc36094079C522Fe` |

Seeded escrows. Both are `Funded` with 18,450 dUSD from the buyer to the
seller:

| Id | Mode | Oracle |
|---|---|---|
| `1` | legacy | legacy oracle EOA |
| `2` | guarded | `GuardExecutor` |

The sources are verified on
[Blockscout](https://base-sepolia.blockscout.com/address/0x06F0b593C999e45fB0514584D8C15E17673c09FB).
They are not verified on Basescan yet because that needs an Etherscan API key.

These are testnet-only wallets and mock funds. The keys live only in the
deployer's local `.env`.

### Redeploying to a testnet

1. In `.env`, set `RPC_URL` to the provider's HTTPS endpoint (for example
   Alchemy) and `DEPLOYER_PRIVATE_KEY` to a funded key that is only used on
   testnets. Also set `PLATFORM_SIGNER_ADDRESS` and `APPROVER_ADDRESS`.
2. Deploy, then seed as described for anvil:

   ```sh
   set -a; source .env; set +a
   forge script script/Deploy.s.sol --rpc-url "$RPC_URL" --broadcast --slow
   ```

3. Verify the sources. Blockscout needs no API key:

   ```sh
   forge verify-contract --chain 84532 --verifier blockscout \
     --verifier-url https://base-sepolia.blockscout.com/api/ \
     <address> src/DemoEscrow.sol:DemoEscrow
   ```

   For `GuardExecutor`, add
   `--constructor-args $(cast abi-encode "constructor(address,address)" <escrow> <platformSigner>)`.
   To verify on Basescan instead, set `ETHERSCAN_API_KEY` and pass `--verify`
   to `forge script`.

4. Update `deployments/<network>.json`. The raw data is in
   `broadcast/<Script>.s.sol/<chainId>/run-latest.json`, which stays local.

## Layout

```
src/          contracts
test/         forge tests
script/       Deploy.s.sol, Seed.s.sol
deployments/  deployment records and ABIs per network
lib/          forge-std (git submodule)
```

## Open items

- License is `UNLICENSED` pending a decision.
- Approver set and platform signer are owner-managed single keys; no multisig
  or rotation policy.
- Sources are not verified on Basescan yet (they are verified on Blockscout).
