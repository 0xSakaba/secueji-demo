# Base 主網 demo 準備與部署檢查

目前狀態：**程式與本機測試已準備；尚未部署主網、尚未呼叫真實 Intercepta API。**

這不是生產環境安全認證。合約未經審計，刻意保留 oracle bypass、退款衝突等 demo 行為。
只用自己部署、無兌換價值的 dUSD／decoy dUSD；不得放入真實 USDC、客戶資產或正式錢包。
主網 gas、部署費及 operator 補款是真實 ETH，不能視為測試幣。

## 1. 環境隔離

- 保留 `deployments/base-sepolia.json` 與既有 Sepolia 地址，不覆蓋。
- `.env.base-mainnet.example` 是主網欄位清單；憑證全部留白。
- 將主網設定保存在 gitignored `.env.base-mainnet`，勿提交或貼出私鑰。
- 請使用獨立 demo 錢包，不沿用可能公開過的 Anvil／testnet 私鑰。
- Forge 也會讀根目錄 `.env`；切換時要載入完整目標設定，避免殘留的舊地址。
- 所有角色與合約地址必須在主網重新確認。`EXPECTED_CHAIN_ID=8453`，而非 `84532`。
- `ALLOW_BASE_MAINNET` 預設 false；人工確認後才改 true，包含 dry-run。
- `OPERATOR_GAS_WEI` 必填；`0` 禁止自動補款。非零代表 operator 的目標餘額。
  超出目標不會退回；低於目標會補差額。請先確認收款 operator 地址與金額。
- `PLATFORM_SIGNER_ADDRESS` 留白，不部署舊版 GuardExecutor。
- Intercepta key 只需填在 **Secueji 平台** `.env` 的 `INTERCEPTA_API_KEY`，本 repo 不讀取它。

## 2. 先做本機驗證

```sh
forge test --offline
forge build --offline
```

首次需先安裝 repo 已鎖定的 forge-std 與 Solidity 0.8.28，才可使用 offline。
測試中的 `vm.chainId(8453)` 只改本機 EVM，不連主網、不使用真實 ETH。
`ScriptsTest` 包含：八個腳本網路不符、未 opt-in、其他主網、未填 gas 目標等拒絕檢查，
以及 Anvil／Sepolia／Base 設定的完整 local EVM 流程。

## 3. 部署前唯讀檢查／模擬（由操作者執行）

以下命令**沒有 `--broadcast`**。勿開 shell trace (`set -x`)，勿把 RPC key／私鑰貼進命令列。

```sh
set -a
source .env.base-mainnet
set +a
export ETH_RPC_URL="$RPC_URL"
cast chain-id                    # 必須為 8453
forge script script/Deploy.s.sol --rpc-url "$ETH_RPC_URL"
```

確認角色地址、預計交易數、gas 估算與錢包預算。模擬產生的合約地址不是已部署地址。
實際 broadcast 是另一個人工授權步驟，不由此文件或測試自動執行。
**不要用 `--resume` 跳過這些檢查**；resume 可能直接重播先前交易，不重跑腳本防呆。

## 4. 正式部署順序（每一步先模擬、確認後才廣播）

1. `Deploy.s.sol`：部署 DemoStablecoin 與 DemoEscrow。
2. 等待成功 receipt，把真正的 `TOKEN_ADDRESS`、`ESCROW_ADDRESS` 填入主網設定並重新載入。
3. 驗證合約來源；比對鏈、程式碼、admin、minter，並記錄部署 block／transaction hash。
4. `OnboardOperator.s.sol`：交付 guardian；補 gas 只按明確填入的目標執行。
5. 在 buyer 錢包準備經核准的少量 gas ETH；`Seed.s.sol` 會由 buyer 部署 decoy、approve、fund。
6. `Seed.s.sol`：建立六個情境並印出實際 escrow id。不得假設是 Sepolia 的 7–12。
7. 依 `TITLE_SUFFIX` 與印出的 label/id 建立本次對照；记录 seed receipt 的事件與實際地址。
8. 以 `deployments/base-mainnet.example.json` 為欄位參考建立 **真正**的 `base-mainnet.json`。
   只有 receipt 驗證成功後才改部署狀態；未執行的 API／端到端驗證仍標 `NOT_RUN`。

如需 ABI，可在成功編譯後用 `forge inspect src/DemoEscrow.sol:DemoEscrow abi` 取得。
現有合約 Solidity 邏輯未改，不需要為 Intercepta 增加合約 hook。

## 5. 接到 Secueji 平台後

主網合約部署成功，**不代表平台已能執行主網操作**。平台仍須獨立設定：
chain 8453 RPC／事件來源、主網合約與 ABI、operator、政策，以及 Intercepta 模式。
先確認平台是否接受這個 chain id；不可為了 demo 直接解除整个平台的主網限制。

先用唯讀／OBSERVE 模式做分析，人工核對 provider 結果與平台畫面，再評估 REQUIRE。
API 支援 Base 並不保證新合約已被索引或能成功模擬；回應 incomplete 必須如實呈現。
請依 [Intercepta 情境指南](intercepta-scenarios.md) 分開驗證提供者、Agent、平台決策。

部署、API 真實驗證及錄影前，均另行確認；這份準備工作沒有執行任何一項。
