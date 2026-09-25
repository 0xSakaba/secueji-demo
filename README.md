# secueji-demo

Sandbox smart contracts used as the demo target project for
secueji. They reproduce a common escrow control
gap and show one way to close it on-chain.

The demo story is a used-car escrow marketplace: a buyer deposits dUSD into an
escrow, the marketplace checks payment and the vehicle inspection, and an
operator then releases the funds to the seller. `titleId` is the vehicle id.

Not audited. Mock funds only. Deploy only to local chains and testnets.

## Contracts

| Contract | Purpose |
|---|---|
| `DemoStablecoin` | Minimal 6-decimal ERC20 ("Demo USD", `dUSD`) used as settlement currency |
| `DemoEscrow` | Escrow whose release authority is only `msg.sender == escrow.oracle`. This is the control gap: the contract knows nothing about application-level approval. It also has a guardian pause, a buyer refund request flag and a `titleId` index |
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

### Pause, refund request and title lookup

- **Pause.** The guardian or the admin can call `pause()` (stops every
  `release` and `refund`) or `pauseEscrow(id)` (stops one escrow). Only the
  admin can `unpause()` / `unpauseEscrow(id)`, so the guardian can stop funds
  but never move them. A guarded release through `GuardExecutor` reverts while
  paused too. Events: `Paused`, `Unpaused`, `EscrowPaused`, `EscrowUnpaused`,
  `GuardianSet`.
- **Refund request.** The buyer of a funded escrow can call
  `requestRefund(id, reason)`. It stores `refundRequestedAt[id]` (block
  timestamp) and emits `RefundRequested(escrowId, titleId, buyer, reason)`.
  **Demo design:** it deliberately does not block `release`. Deciding that a
  release conflicts with a pending refund request is left to the policy that
  authorizes guarded releases. A production escrow would likely enforce it
  on-chain as well.
- **Title lookup.** `EscrowCreated` indexes `titleId`, and
  `escrowIdsByTitle(titleId)` returns every escrow of a vehicle.

## Roles and permissions

| Role | Where | Can do |
|---|---|---|
| Minter | `DemoStablecoin.minter` (deployer, immutable) | `mint` |
| Admin | `DemoEscrow.admin` (deployer, immutable) | `createEscrow`, `refund` (Funded), `cancel` (Created), `setGuardian`, `pause`, `pauseEscrow`, `unpause`, `unpauseEscrow` |
| Guardian | `DemoEscrow.guardian` (deployer by default, admin can change) | `pause`, `pauseEscrow` (never unpause) |
| Buyer | per escrow | `fund` (moves `amount` from buyer to escrow; needs allowance), `requestRefund` (Funded, once) |
| Oracle | per escrow (EOA or `GuardExecutor`) | `release` (pays the seller) |
| Owner | `GuardExecutor.owner` (deployer) | `setApprover`, `setPlatformSigner`, `transferOwnership` |
| Approver | `GuardExecutor.isApprover` | Signs `ReleaseIntent` (EIP-712) off-chain |
| Platform signer | `GuardExecutor.platformSigner` | Signs `Authorization` (EIP-712) off-chain |
| Anyone | | Submits a valid bundle to `GuardExecutor.execute`; the signatures are the authority |

Escrow lifecycle: `Created → Funded → Released | Refunded`, or
`Created → Cancelled`. Terms are fixed at creation and release is one-shot, so
an escrow can never pay out twice. `release` and `refund` revert with
`ContractPaused` or `EscrowIsPaused(id)` while a pause applies.

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

GuardExecutor does not know which token the business accepts or whether the
buyer asked for a refund. An intent over a lookalike token, or over an escrow
with a pending refund request, passes these checks if both parties signed it.
Those decisions belong to the platform policy (see [Demo scenarios](#demo-scenarios)).

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
| `test/DemoEscrow.t.sol` | Create/fund, indexed `titleId` and `escrowIdsByTitle`, legacy release with no approval, one-shot release, oracle-only release (fuzz), refund, cancel, buyer refund request (buyer only, Funded only, once, does not block release) |
| `test/DemoEscrowPause.t.sol` | Guardian role, global and per-escrow pause, who can pause and unpause (fuzz), events, pause blocks legacy release, guarded release and refund |
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
   - `GUARDIAN_ADDRESS` (optional): account allowed to pause; defaults to the
     deployer

3. Deploy:

   ```sh
   set -a; source .env; set +a
   export ETH_RPC_URL="$RPC_URL"
   forge script script/Deploy.s.sol --rpc-url "$ETH_RPC_URL" --broadcast
   ```

   The script logs the `DemoStablecoin`, `DemoEscrow` and `GuardExecutor`
   addresses. The deployer becomes minter, escrow admin, default guardian and
   guard owner.

4. Optional: seed the scenario escrows. Put the deployed addresses and
   `BUYER_PRIVATE_KEY`, `SELLER_ADDRESS`, `LEGACY_ORACLE_ADDRESS` into `.env`,
   then:

   ```sh
   set -a; source .env; set +a
   export ETH_RPC_URL="$RPC_URL"
   forge script script/Seed.s.sol --rpc-url "$ETH_RPC_URL" --broadcast
   ```

   On a fresh deployment this creates escrows `1` to `6` (see
   [Demo scenarios](#demo-scenarios)) and deploys the decoy dUSD token from the
   buyer account.

Private keys are only read from environment variables. `.env` and
`broadcast/` are git-ignored. Keep the RPC URL in an environment variable
(`ETH_RPC_URL`) rather than typing it on the command line, so a provider key
in the URL does not end up in shell history or pasted logs.

## Base Sepolia deployment

The demo is deployed on Base Sepolia (chain id `84532`). The full record is
[`deployments/base-sepolia.json`](deployments/base-sepolia.json) (version 2).
It has the contract addresses, deploy and seed transaction hashes, blocks,
role addresses, the seeded escrows, the git commit that was deployed and the
EIP-712 domain. ABIs are in [`deployments/abi/`](deployments/abi).

| Contract | Address |
|---|---|
| `DemoStablecoin` (dUSD) | [`0x9A65b88635885Cd4f23d8B4F822eD064c94CbE78`](https://sepolia.basescan.org/address/0x9A65b88635885Cd4f23d8B4F822eD064c94CbE78) |
| `DemoEscrow` | [`0x8e14ca274AD1B249b99A1297b81eAFeDAa2EfD5B`](https://sepolia.basescan.org/address/0x8e14ca274AD1B249b99A1297b81eAFeDAa2EfD5B) |
| `GuardExecutor` | [`0x375e5a2A56F1Bc4eE92B6137645661019cac375B`](https://sepolia.basescan.org/address/0x375e5a2A56F1Bc4eE92B6137645661019cac375B) |
| Decoy dUSD (scenario only, not a project contract) | [`0x0B49f8C8ACA62778c0C0f4BFebB7413e270DFa69`](https://sepolia.basescan.org/address/0x0B49f8C8ACA62778c0C0f4BFebB7413e270DFa69) |

| Role | Address |
|---|---|
| Deployer (minter, escrow admin, escrow guardian, guard owner) | [`0x65a7ce7F78f2031Bb8b69b602538153aAcBA5F90`](https://sepolia.basescan.org/address/0x65a7ce7F78f2031Bb8b69b602538153aAcBA5F90) |
| Platform signer | `0x0804e7c36F61a416DB3155CdA388760C24DbDefc` |
| Approver | `0x32758061A72fEac22D549d7953B90dece1443731` |
| Buyer (also minter of the decoy token) | `0x7D6208024d17fbD699dE085e36bEaAD046f86120` |
| Seller | `0x007Bfb7f3aaAed103f0e21155814D2Ad0006054d` |
| Legacy oracle (EOA) | `0x1CAC9ba3a8DB03076daF6293bc36094079C522Fe` |

The sources of all four contracts are verified on
[Blockscout](https://base-sepolia.blockscout.com/address/0x8e14ca274AD1B249b99A1297b81eAFeDAa2EfD5B).
They are not verified on Basescan yet because that needs an Etherscan API key.

These are testnet-only wallets and mock funds. The keys live only in the
deployer's local `.env`.

The first deployment (no guardian, pause, title index or refund request) is
retired. Its record is kept in
[`deployments/base-sepolia-v1.json`](deployments/base-sepolia-v1.json) with
its ABIs in [`deployments/abi/v1/`](deployments/abi/v1).

## Demo scenarios

Seeded escrows on the current deployment. All are `Funded` by the buyer, pay
the seller and start unpaused. `titleId = keccak256(label)`.

| Id | Vehicle (`titleId` label) | Mode | Token | Amount | Scenario |
|---|---|---|---|---|---|
| `1` | `vehicle-A` | guarded | dUSD | 18,450 | Normal release |
| `2` | `vehicle-B` | guarded | dUSD | 21,300 | Payment mapping |
| `3` | `vehicle-C` | legacy | dUSD | 12,800 | Bypass release |
| `4` | `vehicle-D` | legacy | dUSD | 9,750 | Bypass attempt after pause |
| `5` | `vehicle-E` | guarded | decoy dUSD | 18,450 | Token mismatch |
| `6` | `vehicle-F` | guarded | dUSD | 16,900 | Refund conflict (refund requested) |

The commands below assume `.env` is loaded and `ETH_RPC_URL` is exported:

```sh
set -a; source .env; set +a
export ETH_RPC_URL="$RPC_URL"
export ESCROW_ADDRESS=0x8e14ca274AD1B249b99A1297b81eAFeDAa2EfD5B
ESCROW_TUPLE='getEscrow(uint256)((address,address,address,uint256,bytes32,address,uint8))'
```

`getEscrow` returns `(buyer, seller, token, amount, titleId, oracle, state)`
with state `2 = Funded`, `3 = Released`, `4 = Refunded`.

### 1. Normal guarded release (vehicle-A, escrow 1)

- **Before:** escrow `1` is `Funded`, oracle is `GuardExecutor`, token is the
  configured dUSD, no pause, no refund request.
- **Trigger:** an operator asks secueji to release vehicle-A's escrow to the
  seller. The platform signs an `Authorization`, the approver signs the
  `ReleaseIntent`, and the bundle goes to `GuardExecutor.execute`.
- **Expected policy decision:** allow. Every fact matches: `titleId` of
  vehicle-A resolves to escrow `1`, token and amount match, nothing is paused,
  no refund was requested.
- **Verify:** `GuardedRelease` and `EscrowReleased` events; escrow `1` state is
  `3`.

  ```sh
  cast call $ESCROW_ADDRESS "$ESCROW_TUPLE" 1
  ```

### 2. Payment mapping (vehicle-A vs vehicle-B, escrow 2)

- **Before:** escrow `2` holds vehicle-B's 21,300 dUSD.
- **Trigger:** a release request for vehicle-A's order that points at escrow
  `2` (or an intent whose `titleId` is vehicle-A but whose `escrowId` is `2`).
- **Expected policy decision:** deny. Vehicle A's payment may only be released
  from an escrow whose `titleId` is vehicle-A. `escrowIdsByTitle(vehicle-A)`
  is `[1]`, so escrow `2` is not vehicle-A's. On-chain, a signed intent with a
  wrong `titleId` would also fail with `TermsMismatch("titleId")`, but the
  platform should refuse before signing anything.
- **Verify:**

  ```sh
  cast call $ESCROW_ADDRESS "escrowIdsByTitle(bytes32)(uint256[])" $(cast keccak vehicle-A)   # [1]
  cast call $ESCROW_ADDRESS "escrowIdsByTitle(bytes32)(uint256[])" $(cast keccak vehicle-B)   # [2]
  ```

### 3. Token mismatch (vehicle-E, escrow 5)

- **Before:** escrow `5` is funded with the decoy token
  `0x0B49f8C8ACA62778c0C0f4BFebB7413e270DFa69`. It is the same
  `DemoStablecoin` code with the same name (`Demo USD`), symbol (`dUSD`) and
  decimals, deployed and minted by the buyer. Only the address (and the
  minter) differ from the real dUSD `0x9A65b88635885Cd4f23d8B4F822eD064c94CbE78`.
- **Trigger:** a release request for vehicle-E.
- **Expected policy decision:** deny. The fixed rule compares the escrow's
  token **address** with the configured settlement token, not its name or
  symbol. GuardExecutor alone would release it, because the intent's token
  matches the escrow's on-chain token.
- **Verify:**

  ```sh
  cast call $ESCROW_ADDRESS "$ESCROW_TUPLE" 5     # token = 0x0B49…Fa69
  cast call 0x0B49f8C8ACA62778c0C0f4BFebB7413e270DFa69 "symbol()(string)"    # "dUSD"
  cast call 0x0B49f8C8ACA62778c0C0f4BFebB7413e270DFa69 "minter()(address)"   # buyer, not the deployer
  ```

### 4. Release vs refund request (vehicle-F, escrow 6)

- **Before:** escrow `6` is `Funded` and the buyer called
  `requestRefund(6, "Inspection failed: odometer reading does not match the listing")`
  (`RefundRequested` event, `refundRequestedAt[6] > 0`).
- **Trigger:** a release request for vehicle-F.
- **Expected policy decision:** escalate to human review or deny. Paying the
  seller while the buyer disputes the deal is a conflict. The escrow contract
  does not block it (demo design, see above), so the platform must.
- **Verify:**

  ```sh
  cast call $ESCROW_ADDRESS "isRefundRequested(uint256)(bool)" 6      # true
  cast call $ESCROW_ADDRESS "refundRequestedAt(uint256)(uint256)" 6   # timestamp
  ```

### 5. Bypass release and automated pause (vehicle-C / vehicle-D, escrows 3 and 4)

- **Before:** escrows `3` and `4` are legacy: their oracle is the legacy oracle
  EOA, which can call `release` directly with no approval. Nothing is paused.
  The legacy oracle has Base Sepolia ETH for gas.
- **Trigger (by hand, during the demo):** put `LEGACY_ORACLE_PRIVATE_KEY` in
  `.env`, then

  ```sh
  ESCROW_ID=3 forge script script/scenarios/BypassRelease.s.sol --rpc-url "$ETH_RPC_URL" --broadcast
  ```

  This pays the seller 12,800 dUSD with an `EscrowReleased` whose `caller` is
  the EOA and no `GuardedRelease` in the same transaction.
- **Expected platform response:** alert on a release that did not go through
  `GuardExecutor`. If the policy authorizes an automatic response, the
  guardian calls `pause()` (or `pauseEscrow(id)`). secueji cannot undo the
  release; it can only stop the next one.
- **Verify:**

  ```sh
  cast call $ESCROW_ADDRESS "paused()(bool)"          # true after the response
  ESCROW_ID=4 forge script script/scenarios/BypassRelease.s.sol --rpc-url "$ETH_RPC_URL"
  # simulation reverts with ContractPaused(); nothing is broadcast
  ```

- **Manual fallback and reset:**

  ```sh
  forge script script/scenarios/GuardianPause.s.sol --rpc-url "$ETH_RPC_URL" --broadcast   # guardian pause (ESCROW_ID=n for one escrow)
  forge script script/scenarios/AdminUnpause.s.sol --rpc-url "$ETH_RPC_URL" --broadcast    # admin unpause (ESCROW_ID=n for one escrow)
  ```

  `GuardianPause` uses `GUARDIAN_PRIVATE_KEY`, or `DEPLOYER_PRIVATE_KEY` (the
  default guardian) when it is unset. A released escrow stays released; run
  `Seed.s.sol` again to get fresh escrows (they get the next ids).

### 6. Pull request review: seller changed after approval

- **Not deployed.** `updateSeller` does not exist on `main` or in the Base
  Sepolia deployment. It lives only on the branch `feat/update-seller`, which
  is meant to be opened as a pull request for secueji to review.
- **The change:** the admin can change the seller of a funded escrow, with a
  test that looks reasonable.
- **Expected review findings:** a legacy escrow then pays the new seller on
  the next oracle `release` with no approval at all; approvals and policy
  decisions made for the old seller are not re-evaluated; it ignores pauses and
  pending refund requests; the event does not say who the previous seller was
  or which vehicle it concerns; and it breaks the "terms are fixed at
  creation" invariant the rest of the system relies on.

## Redeploying to a testnet

1. In `.env`, set `RPC_URL` to the provider's HTTPS endpoint (for example
   Alchemy) and `DEPLOYER_PRIVATE_KEY` to a funded key that is only used on
   testnets. Also set `PLATFORM_SIGNER_ADDRESS`, `APPROVER_ADDRESS` and,
   optionally, `GUARDIAN_ADDRESS`.
2. Deploy, then seed as described for anvil:

   ```sh
   set -a; source .env; set +a
   export ETH_RPC_URL="$RPC_URL"
   forge script script/Deploy.s.sol --rpc-url "$ETH_RPC_URL" --broadcast --slow
   ```

3. Verify the sources. Blockscout needs no API key:

   ```sh
   forge verify-contract --chain 84532 --verifier blockscout \
     --verifier-url https://base-sepolia.blockscout.com/api/ \
     <address> src/DemoEscrow.sol:DemoEscrow
   ```

   For `GuardExecutor`, add
   `--constructor-args $(cast abi-encode "constructor(address,address)" <escrow> <platformSigner>)`.
   If Blockscout reports it as already verified through a partial match, add
   `--skip-is-verified-check` to get a full match. To verify on Basescan
   instead, set `ETHERSCAN_API_KEY` and pass `--verify` to `forge script`.

4. Update `deployments/<network>.json`. The raw data is in
   `broadcast/<Script>.s.sol/<chainId>/run-latest.json`, which stays local.

## Layout

```
src/              contracts
test/             forge tests
script/           Deploy.s.sol, Seed.s.sol
script/scenarios/ demo triggers: BypassRelease, GuardianPause, AdminUnpause
deployments/      deployment records and ABIs per network (v1 kept as retired)
lib/              forge-std (git submodule)
```

## Open items

- License is `UNLICENSED` pending a decision.
- Approver set, platform signer and guardian are single keys; no multisig or
  rotation policy.
- `GuardExecutor` always needs a human approval signature. A policy path where
  the platform authorization alone is enough is not implemented on-chain.
- Sources are not verified on Basescan yet (they are verified on Blockscout).
