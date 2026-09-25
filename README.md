# secueji-demo

Sandbox smart contracts used as the demo target project for
secueji. They reproduce a common escrow control
gap: whoever holds the oracle key can release funds.

The demo story is a used-car escrow marketplace: a buyer deposits dUSD into an
escrow, the marketplace checks payment and the vehicle inspection, and an
operator then releases the funds to the seller. `titleId` is the vehicle id.

Not audited. Mock funds only. Deploy only to local chains and testnets.

## How the demo uses secueji

secueji is a general platform. It does not know how a customer's contracts
work internally and asks for no special on-chain integration. To onboard, the
customer (here: the marketplace, which is the escrow admin) gives secueji only:

1. **The ABI** of the contracts to manage and watch.
2. **An operator account** and the contract permissions that account holds.
   Here the Secueji operator is the `oracle` of every escrow secueji manages
   (so it can `release`) and the escrow `guardian` (so it can `pause`, never
   unpause or move funds). The admin role stays with the customer.
3. **A business description and policies**, for example "release only in
   dUSD", "a vehicle's payment comes only from that vehicle's escrow", "hold a
   release while the buyer disputes the deal".

A managed release is then: ABI form in secueji → policy decision → human
review in the secueji UI if the policy asks for it (nothing is sent before
approval) → secueji sends `release(id)` from the operator account. No approver
signature is checked on-chain. Monitoring watches the same contracts and, when
funds move outside secueji (a release whose caller is not the operator), the
operator pauses the escrow as guardian.

## Contracts

| Contract | Purpose |
|---|---|
| `DemoStablecoin` | Minimal 6-decimal ERC20 ("Demo USD", `dUSD`) used as settlement currency |
| `DemoEscrow` | Escrow whose release authority is only `msg.sender == escrow.oracle`. This is the control gap: the contract knows nothing about application-level approval. It also has a guardian pause, a buyer refund request flag and a `titleId` index |
| `GuardExecutor` | **Earlier design, not on the demo path.** An oracle contract that releases only with a human EIP-712 approval and a platform authorization over the same intent, i.e. the contract enforces platform signatures. It is kept in the repo and in the deployment record, but no current scenario escrow uses it |

The contracts have no external dependencies. `forge-std` is only used by the
tests and scripts.

### Operator and legacy escrows

Every escrow uses the same `DemoEscrow`. The oracle picked when an escrow is
created decides who can release it:

- **Operator escrow**: the oracle is the Secueji operator account. It is
  released only when secueji sends the transaction, after its policy (and, if
  needed, a human in the secueji UI) allowed it.
- **Legacy escrow**: the oracle is some other EOA, here an old oracle key the
  customer never rotated (or one that leaked). Whoever holds it can release
  with no policy and no review. This is the bypass the monitor has to catch.

### Pause, refund request and title lookup

- **Pause.** The guardian (the Secueji operator after onboarding) or the admin
  can call `pause()` (stops every `release` and `refund`) or `pauseEscrow(id)`
  (stops one escrow). Only the admin can `unpause()` / `unpauseEscrow(id)`, so
  the guardian can stop funds but never move them. A pause stops the operator's
  own releases too. Events: `Paused`, `Unpaused`, `EscrowPaused`,
  `EscrowUnpaused`, `GuardianSet`.
- **Refund request.** The buyer of a funded escrow can call
  `requestRefund(id, reason)`. It stores `refundRequestedAt[id]` (block
  timestamp) and emits `RefundRequested(escrowId, titleId, buyer, reason)`.
  **Demo design:** it deliberately does not block `release`. Deciding that a
  release conflicts with a pending refund request is left to the secueji
  policy. A production escrow would likely enforce it on-chain as well.
- **Title lookup.** `EscrowCreated` indexes `titleId`, and
  `escrowIdsByTitle(titleId)` returns every escrow of a vehicle, whatever its
  state.

## Roles and permissions

| Role | Where | Can do |
|---|---|---|
| Minter | `DemoStablecoin.minter` (deployer, immutable) | `mint` |
| Admin (the customer) | `DemoEscrow.admin` (deployer, immutable) | `createEscrow`, `refund` (Funded), `cancel` (Created), `setGuardian`, `pause`, `pauseEscrow`, `unpause`, `unpauseEscrow` |
| Secueji operator | per-escrow `oracle` of operator escrows, and `DemoEscrow.guardian` | `release` of its own escrows, `pause`, `pauseEscrow` (never unpause) |
| Legacy oracle | per-escrow `oracle` of legacy escrows | `release` of those escrows |
| Buyer | per escrow | `fund` (moves `amount` from buyer to escrow; needs allowance), `requestRefund` (Funded, once) |
| GuardExecutor owner, approver, platform signer | `GuardExecutor` | Earlier design only (see below) |

The guardian defaults to the deployer; `script/OnboardOperator.s.sol` hands it
to the operator.

Escrow lifecycle: `Created → Funded → Released | Refunded`, or
`Created → Cancelled`. Terms are fixed at creation and release is one-shot, so
an escrow can never pay out twice. `release` and `refund` revert with
`ContractPaused` or `EscrowIsPaused(id)` while a pause applies.

### GuardExecutor (earlier design, not on the demo path)

GuardExecutor was a first attempt where the escrow's oracle is a contract that
checks an approver's EIP-712 `ReleaseIntent` and a platform `Authorization`
before calling `release`. It ties the customer's contract to secueji's
signature format, which a general platform should not require, so the demo no
longer uses it. It is still built, tested and deployed. Its checks, in order:

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
version `1`. Owner functions: `setApprover`, `setPlatformSigner`,
`transferOwnership`.

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
| `test/OperatorModel.t.sol` | Operator releases only its own escrows, has no admin powers, pauses as guardian after a bypass, is itself stopped by a pause until the admin unpauses, is not blocked on-chain by a refund request |
| `test/Scripts.t.sol` | Deploy, OnboardOperator, Seed, RetireEscrows and the scenario scripts end to end (the same sequence as the Base Sepolia re-seed) |
| `test/GuardExecutor.t.sol` | Earlier design: valid guarded release, missing/foreign approval, oracle EOA bypass, terms mismatches, nonce replay, expired intent/authorization, mismatched or forged authorization, wrong escrow contract |

Test names carry scenario (`S-xxx`) and acceptance-criterion (`AC-xxx`) IDs
from the secueji MVP spec. The tests run offline. forge loads `.env`
automatically, so `test/Scripts.t.sol` sets every variable the scripts read.

## Deploy to local anvil

1. Start a local chain in a separate terminal:

   ```sh
   anvil
   ```

   anvil prints ten funded accounts with their private keys.

2. Create `.env` from the template and fill it in with anvil accounts:

   ```sh
   cp .env.example .env
   ```

   - `DEPLOYER_PRIVATE_KEY`: the customer (minter and escrow admin)
   - `OPERATOR_ADDRESS`, `OPERATOR_PRIVATE_KEY`: the Secueji operator account
   - `BUYER_PRIVATE_KEY`, `SELLER_ADDRESS`, `LEGACY_ORACLE_ADDRESS`,
     `LEGACY_ORACLE_PRIVATE_KEY`: the scenario actors
   - leave `PLATFORM_SIGNER_ADDRESS` empty unless you also want GuardExecutor

3. Deploy, onboard the operator and seed the scenario escrows:

   ```sh
   set -a; source .env; set +a
   export ETH_RPC_URL="$RPC_URL"
   forge script script/Deploy.s.sol --rpc-url "$ETH_RPC_URL" --broadcast
   # put the printed TOKEN_ADDRESS and ESCROW_ADDRESS into .env, then source it again
   forge script script/OnboardOperator.s.sol --rpc-url "$ETH_RPC_URL" --broadcast
   forge script script/Seed.s.sol --rpc-url "$ETH_RPC_URL" --broadcast
   ```

   `OnboardOperator` makes the operator the escrow guardian and tops it up to
   `OPERATOR_GAS_WEI` (default 0.01 ETH). On a fresh deployment `Seed` creates
   escrows `1` to `6` with labels `vehicle-A` … `vehicle-F` and deploys a decoy
   dUSD token from the buyer. Set `DECOY_TOKEN_ADDRESS` to reuse a decoy, and
   `TITLE_SUFFIX` (for example `-2`) to give a re-seed fresh titles. Only
   missing token balances are minted.

4. To take an old scenario set out of play, the admin refunds it:

   ```sh
   ESCROW_IDS=1,2,3,4,5,6 forge script script/RetireEscrows.s.sol --rpc-url "$ETH_RPC_URL" --broadcast
   ```

Private keys are only read from environment variables. `.env` and
`broadcast/` are git-ignored. Keep the RPC URL in an environment variable
(`ETH_RPC_URL`) rather than typing it on the command line, so a provider key
in the URL does not end up in shell history or pasted logs.

## Base Sepolia deployment

The demo is deployed on Base Sepolia (chain id `84532`). The full record is
[`deployments/base-sepolia.json`](deployments/base-sepolia.json) (contracts
version 2). It has the contract addresses, deploy, onboarding and seed
transaction hashes, blocks, role addresses, the current scenario escrows with
their expected decisions, the retired escrows, the git commits and the
GuardExecutor EIP-712 domain. ABIs are in [`deployments/abi/`](deployments/abi).

| Contract | Address |
|---|---|
| `DemoStablecoin` (dUSD) | [`0x9A65b88635885Cd4f23d8B4F822eD064c94CbE78`](https://sepolia.basescan.org/address/0x9A65b88635885Cd4f23d8B4F822eD064c94CbE78) |
| `DemoEscrow` | [`0x8e14ca274AD1B249b99A1297b81eAFeDAa2EfD5B`](https://sepolia.basescan.org/address/0x8e14ca274AD1B249b99A1297b81eAFeDAa2EfD5B) |
| `GuardExecutor` (earlier design, not on the demo path) | [`0x375e5a2A56F1Bc4eE92B6137645661019cac375B`](https://sepolia.basescan.org/address/0x375e5a2A56F1Bc4eE92B6137645661019cac375B) |
| Decoy dUSD (scenario only, not a project contract) | [`0x0B49f8C8ACA62778c0C0f4BFebB7413e270DFa69`](https://sepolia.basescan.org/address/0x0B49f8C8ACA62778c0C0f4BFebB7413e270DFa69) |

| Role | Address |
|---|---|
| Deployer = customer (minter, escrow admin, guard owner) | [`0x65a7ce7F78f2031Bb8b69b602538153aAcBA5F90`](https://sepolia.basescan.org/address/0x65a7ce7F78f2031Bb8b69b602538153aAcBA5F90) |
| Secueji operator (oracle of operator escrows, escrow guardian) | [`0x90FbD16093440231B0F8eE3b52c0364FF80E6cc5`](https://sepolia.basescan.org/address/0x90FbD16093440231B0F8eE3b52c0364FF80E6cc5) |
| Buyer (also minter of the decoy token) | `0x7D6208024d17fbD699dE085e36bEaAD046f86120` |
| Seller | `0x007Bfb7f3aaAed103f0e21155814D2Ad0006054d` |
| Legacy oracle (old key outside secueji) | `0x1CAC9ba3a8DB03076daF6293bc36094079C522Fe` |
| GuardExecutor platform signer (earlier design) | `0x0804e7c36F61a416DB3155CdA388760C24DbDefc` |
| GuardExecutor approver (earlier design) | `0x32758061A72fEac22D549d7953B90dece1443731` |

The operator was onboarded with `setGuardian`
([`0x696a721b…60eb64`](https://sepolia.basescan.org/tx/0x696a721b3a704181910c0c052d11d2f934a342d8ad47b793abcfbc322460eb64))
and 0.01 ETH for gas. The contracts were not redeployed for the operator model:
`DemoEscrow` already lets every escrow pick its oracle and has the guardian
role.

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

Current scenario escrows on Base Sepolia. All are `Funded` by the buyer, pay
the seller and start unpaused. `titleId = keccak256(label)`; each label has
exactly one escrow, so `escrowIdsByTitle` returns one id.

| Id | Vehicle (`titleId` label) | Oracle | Token | Amount | Scenario | Expected decision |
|---|---|---|---|---|---|---|
| `7` | `vehicle-A-2` | Secueji operator | dUSD | 18,450 | Normal release | allow, operator sends `release(7)` |
| `8` | `vehicle-B-2` | Secueji operator | dUSD | 21,300 | Payment mapping | deny a vehicle-A-2 release that points here |
| `9` | `vehicle-C-2` | legacy oracle | dUSD | 12,800 | Bypass release | detect, operator pauses as guardian |
| `10` | `vehicle-D-2` | legacy oracle | dUSD | 9,750 | Bypass after pause | blocked on-chain (`ContractPaused`) |
| `11` | `vehicle-E-2` | Secueji operator | decoy dUSD | 18,450 | Token mismatch | deny |
| `12` | `vehicle-F-2` | Secueji operator | dUSD | 16,900 | Refund conflict (refund requested) | human review or deny |

Escrows `1` to `6` (labels `vehicle-A` … `vehicle-F`, GuardExecutor or legacy
oracle) belong to the first scenario set of this deployment. They are
**retired**: the admin refunded all of them to the buyer
(`RetireEscrows.s.sol`), so they are `Refunded` and play no part in the demo.
Their record is under `retiredSeeds` in the deployment JSON.

What secueji needs to run these scenarios: the `DemoEscrow` and
`DemoStablecoin` ABIs and addresses, the operator account (address and key,
held by secueji), the business description above (used-car escrow, `titleId`
is the vehicle, settlement only in dUSD `0x9A65…bE78`) and the policies. It
needs no GuardExecutor, approver or platform signer.

The commands below assume `.env` is loaded and `ETH_RPC_URL` is exported:

```sh
set -a; source .env; set +a
export ETH_RPC_URL="$RPC_URL"
export ESCROW_ADDRESS=0x8e14ca274AD1B249b99A1297b81eAFeDAa2EfD5B
ESCROW_TUPLE='getEscrow(uint256)((address,address,address,uint256,bytes32,address,uint8))'
```

`getEscrow` returns `(buyer, seller, token, amount, titleId, oracle, state)`
with state `2 = Funded`, `3 = Released`, `4 = Refunded`.

**Order during a live demo.** A pause also stops the operator's own releases.
Run the normal release (scenario 1) and the denials (2, 5, 6) before the
bypass (3, 4), or unpause in between (see [Reset](#reset)). Releases are
one-shot: once escrow `7` or `9` is released, seed a new set for the next run.

### 1. Normal release (vehicle-A-2, escrow 7)

- **Before:** escrow `7` is `Funded`, its oracle is the Secueji operator
  `0x90Fb…6cc5`, token is the configured dUSD, nothing is paused, no refund
  request.
- **Trigger:** in secueji, fill the ABI form `DemoEscrow.release(escrowId = 7)`
  for vehicle-A-2's order.
- **Expected platform decision:** allow. `getEscrow(7).titleId` is
  `keccak256("vehicle-A-2")`, the token is dUSD, the amount matches, nothing
  is paused, no refund was requested. secueji sends `release(7)` from the
  operator account.
- **Verify:** `EscrowReleased(7, seller, dUSD, 18450e6, caller = operator)`;
  state `3`.

  ```sh
  cast call $ESCROW_ADDRESS "$ESCROW_TUPLE" 7
  cast logs --address $ESCROW_ADDRESS --from-block 47296650 \
    'EscrowReleased(uint256 indexed,address indexed,address,uint256,address indexed)'
  ```

- **Manual fallback** (only after secueji allowed it, if secueji could not
  send the transaction itself):

  ```sh
  ESCROW_ID=7 forge script script/scenarios/OperatorRelease.s.sol --rpc-url "$ETH_RPC_URL" --broadcast
  ```

### 2. Payment mapping (vehicle-A-2 vs vehicle-B-2, escrow 8)

- **Before:** escrow `8` holds vehicle-B-2's 21,300 dUSD; its oracle is the
  operator, so the operator *could* release it.
- **Trigger:** a release request for vehicle-A-2's order whose form points at
  `release(escrowId = 8)`.
- **Expected platform decision:** deny, nothing is sent. Vehicle A's payment
  may only come from an escrow whose `titleId` is vehicle-A-2:
  `escrowIdsByTitle(vehicle-A-2)` is `[7]` and `getEscrow(8).titleId` is
  vehicle-B-2. The contract would accept the call, so the policy is the only
  check.
- **Verify:**

  ```sh
  cast call $ESCROW_ADDRESS "escrowIdsByTitle(bytes32)(uint256[])" $(cast keccak vehicle-A-2)   # [7]
  cast call $ESCROW_ADDRESS "escrowIdsByTitle(bytes32)(uint256[])" $(cast keccak vehicle-B-2)   # [8]
  cast call $ESCROW_ADDRESS "$ESCROW_TUPLE" 8                                                   # still state 2
  ```

### 3. Bypass release and automated pause (vehicle-C-2, escrow 9)

- **Before:** escrow `9`'s oracle is the legacy oracle
  `0x1CAC…22Fe`, an old key outside secueji that can call `release` with no
  policy and no review. The guardian is the Secueji operator. Nothing is
  paused. The legacy oracle has Base Sepolia ETH for gas.
- **Trigger (by hand, during the demo only):** with
  `LEGACY_ORACLE_PRIVATE_KEY` in `.env`,

  ```sh
  ESCROW_ID=9 forge script script/scenarios/BypassRelease.s.sol --rpc-url "$ETH_RPC_URL" --broadcast
  ```

  This pays the seller 12,800 dUSD with an `EscrowReleased` whose `caller` is
  the legacy oracle, not the operator, and no secueji operation behind it.
- **Expected platform response:** alert on a release that did not go through
  secueji (caller is not the operator, no approved operation). If the policy
  allows an automatic response, secueji calls `pause()` from the operator
  account (the guardian). secueji cannot undo this release; it stops the next
  one.
- **Verify:**

  ```sh
  cast call $ESCROW_ADDRESS "$ESCROW_TUPLE" 9          # state 3, oracle = legacy oracle
  cast call $ESCROW_ADDRESS "paused()(bool)"           # true after the response
  cast logs --address $ESCROW_ADDRESS --from-block 47296650 'Paused(address indexed)'   # account = operator
  ```

- **Manual fallback** for the response (operator key, must be the guardian):

  ```sh
  forge script script/scenarios/GuardianPause.s.sol --rpc-url "$ETH_RPC_URL" --broadcast   # ESCROW_ID=n pauses one escrow
  ```

### 4. Bypass attempt after the pause (vehicle-D-2, escrow 10)

- **Before:** scenario 3 ran and the contract is paused. Escrow `10` is
  `Funded` and its oracle is the same legacy key.
- **Trigger:** the legacy key tries again. Leave out `--broadcast`; the
  simulation already fails and nothing is sent:

  ```sh
  ESCROW_ID=10 forge script script/scenarios/BypassRelease.s.sol --rpc-url "$ETH_RPC_URL"
  # script failed: ContractPaused()
  ```

- **Expected result:** blocked on-chain by the pause; the platform only needs
  to record the attempt if it sees one.
- **Verify:** `cast call $ESCROW_ADDRESS "$ESCROW_TUPLE" 10` is still state `2`.

### 5. Token mismatch (vehicle-E-2, escrow 11)

- **Before:** escrow `11` is funded with the decoy token
  `0x0B49f8C8ACA62778c0C0f4BFebB7413e270DFa69`. It is the same
  `DemoStablecoin` code with the same name (`Demo USD`), symbol (`dUSD`) and
  decimals, deployed and minted by the buyer. Only the address (and the
  minter) differ from the real dUSD `0x9A65b88635885Cd4f23d8B4F822eD064c94CbE78`.
  Its oracle is the operator.
- **Trigger:** a release request `release(escrowId = 11)` for vehicle-E-2.
- **Expected platform decision:** deny, nothing is sent. The rule compares
  the escrow's token **address** with the configured settlement token, not its
  name or symbol.
- **Verify:**

  ```sh
  cast call $ESCROW_ADDRESS "$ESCROW_TUPLE" 11     # token = 0x0B49…Fa69
  cast call 0x0B49f8C8ACA62778c0C0f4BFebB7413e270DFa69 "symbol()(string)"    # "dUSD"
  cast call 0x0B49f8C8ACA62778c0C0f4BFebB7413e270DFa69 "minter()(address)"   # buyer, not the deployer
  ```

### 6. Release vs refund request (vehicle-F-2, escrow 12)

- **Before:** escrow `12` is `Funded`, its oracle is the operator, and the
  buyer called
  `requestRefund(12, "Inspection failed: odometer reading does not match the listing")`
  (`RefundRequested` event, `refundRequestedAt[12] > 0`).
- **Trigger:** a release request `release(escrowId = 12)` for vehicle-F-2.
- **Expected platform decision:** send to human review in the secueji UI, or
  deny. Paying the seller while the buyer disputes the deal is a conflict. The
  contract does not block it (demo design, see above), so the policy must.
  Nothing is sent unless a reviewer approves.
- **Verify:**

  ```sh
  cast call $ESCROW_ADDRESS "isRefundRequested(uint256)(bool)" 12      # true
  cast call $ESCROW_ADDRESS "refundRequestedAt(uint256)(uint256)" 12   # timestamp
  ```

### 7. Pull request review: seller changed after approval

- **Not deployed.** `updateSeller` does not exist on `main` or in the Base
  Sepolia deployment. It lives only on the branch `feat/update-seller`, which
  is meant to be opened as a pull request for secueji to review.
- **The change:** the admin can change the seller of a funded escrow, with a
  test that looks reasonable.
- **Expected review findings:** a legacy escrow then pays the new seller on
  the next oracle `release` with no review at all; a release secueji already
  allowed (or a reviewer approved) for the old seller is not re-evaluated; it
  ignores pauses and pending refund requests; the event does not say who the
  previous seller was or which vehicle it concerns; and it breaks the "terms
  are fixed at creation" invariant the rest of the system relies on.

### Reset

```sh
forge script script/scenarios/AdminUnpause.s.sol --rpc-url "$ETH_RPC_URL" --broadcast   # admin; ESCROW_ID=n for one escrow
```

A released escrow stays released. For a fresh set, retire the old one and
seed again with a new suffix:

```sh
ESCROW_IDS=7,8,9,10,11,12 forge script script/RetireEscrows.s.sol --rpc-url "$ETH_RPC_URL" --broadcast
TITLE_SUFFIX=-3 DECOY_TOKEN_ADDRESS=0x0B49f8C8ACA62778c0C0f4BFebB7413e270DFa69 \
  forge script script/Seed.s.sol --rpc-url "$ETH_RPC_URL" --broadcast --slow
```

`RetireEscrows` skips escrows that are already closed and needs the contract
unpaused. Then update `deployments/base-sepolia.json`.

## Redeploying to a testnet

1. In `.env`, set `RPC_URL` to the provider's HTTPS endpoint (for example
   Alchemy) and `DEPLOYER_PRIVATE_KEY` to a funded key that is only used on
   testnets. Set the operator and scenario variables as for anvil. Set
   `PLATFORM_SIGNER_ADDRESS` (and `APPROVER_ADDRESS`) only if you also want
   GuardExecutor.
2. Deploy, then onboard and seed as described for anvil (add `--slow`):

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
script/           Deploy, OnboardOperator, Seed, RetireEscrows
script/scenarios/ demo triggers and fallbacks: OperatorRelease, BypassRelease,
                  GuardianPause, AdminUnpause
deployments/      deployment records and ABIs per network (v1 kept as retired)
lib/              forge-std (git submodule)
```

## Open items

- License is `UNLICENSED` pending a decision.
- The admin, the Secueji operator and the guardian are single keys; no
  multisig or rotation policy. The operator key is a hot key held by secueji.
- The refund-request conflict is only enforced by the secueji policy, not
  on-chain (demo design).
- `GuardExecutor` is kept as the earlier design and is not maintained for the
  demo path.
- Sources are not verified on Basescan yet (they are verified on Blockscout).
