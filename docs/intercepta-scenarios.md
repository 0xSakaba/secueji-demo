# Intercepta demo 測試指南

這份文件是測試規劃，**不是已取得的 Intercepta 結果**。
機器可讀情境在 [`fixtures/intercepta/scenarios.json`](../fixtures/intercepta/scenarios.json)。
`LIVE_CANDIDATE` 表示部署後可送真實查詢，不表示已執行或一定有警告。

## 責任分界

- demo：提供真實合約、交易與可查詢狀態；不直接呼叫 Intercepta、不保存 key。
- Intercepta：外部交易行為與風險訊號，不知道我們完整的訂單、退款、核准流程。
- Secueji Agent：結合工具資料與 provider 訊號分析，保留引用與不確定性。
- Secueji policy：整合規則與分析，決定拒絕／待審／允許；provider 沒警告不能直接等同允許。

## OPERATION：準備未簽名交易

先載入該網路完整設定，選擇 Seed 實際印出的 `ESCROW_ID`：

```sh
forge script script/InspectIntercepta.s.sol --rpc-url "$ETH_RPC_URL"
```

這個腳本沒有 `startBroadcast`，不讀私鑰，也不放款。
輸出 chain id、合約內 oracle (`from`)、escrow (`to`)、`release(id)` 的 calldata、value=0、
token、退款與暫停狀態。**這是某個時間點的讀取，不是操作授權或最終執行參數鎖定。**
平台正式建立操作時仍須重新準備與綁定版本、驗證 operator，不能直接信任複製的輸出。

送 Intercepta 的 unsigned transaction 使用 `from/to/data`，`value` 以 `0x0` 表示；
chain id 放 API 的 query。不要傳私鑰、退款說明、repo 原始碼或完整案件內容。

## CHAIN_ACTIVITY：觀察真實交易

由操作者另外核准後執行既有 BypassRelease 情境，以 receipt 驗證成功後的 tx hash 為輸入。
需要同時驗證 chain id、contract、receipt status、event/log index、block hash、實際 caller。
Secueji 的即時監聽需產生新事件才能完整驗證；只查歷史 hash 只能驗證歷史分析。
已完成的交易無法撤回；暫停只影響後續操作，且是平台另行授權的動作。

## 情境與判讀

| Case | 資料／觸發 | 要驗證的內容 |
|---|---|---|
| OP-CLEAN | vehicle-A，正常 unsigned release | 記錄真實 API 結果，再看 Agent 與政策；不預設一定安全 |
| OP-TOKEN-MISMATCH | vehicle-E，decoy dUSD | 即使 provider 沒警告，token 地址政策仍可拒絕 |
| OP-REFUND-CONFLICT | vehicle-F，退款申請未處理 | Agent／退款政策的 review 或 deny，不假稱由 provider 發現 |
| CHAIN-BYPASS | vehicle-C，legacy oracle 的真實 release hash | 平台依 caller 與操作紀錄發現繞過流程；provider 分開記錄 |
| OP-RISK / CHAIN-RISK | 僅測試 adapter 注入已標示 synthetic 的風險 | 檢查 warning 保存、Agent 引用、畫面與 REQUIRE 決策；不是 live 成果 |
| OP-STALE | 僅測試 adapter／時鐘控制 | 新操作執行前過期需重查；不阻止已送出交易的 receipt 核對 |
| PROVIDER-FAILURE | 僅測試 adapter 注入逾時、429、502、壞 JSON | 不顯示安全；REQUIRE 不允許不完整結果放行 |
| UNSUPPORTED-NETWORK | Anvil／Base Sepolia | 無正式支援時不送 API，顯示不支援，不混用主網 chain id |

用 `vehicle-* + TITLE_SUFFIX` 找本次 escrow，不固定 7／9／12。
decoy dUSD 與真正 dUSD 是同份 demo 合約、不同地址；**不是已被 Intercepta 列為惡意的 token**。
不要為了產生 provider 紅色警告而接觸真實惡意合約或批准陌生 spender。

## API 能力與驗收紀錄

[官方 Scan Transaction](https://docs.web3antivirus.io/reference/scan-transaction) 列出 Base `8453`，
未列 Base Sepolia `84532`；各 API 支援範圍不同，不能套用 Token API 的鏈清單。
新部署資料尚未索引、方案權限不足或模擬失敗都可能使 live 查詢不完整。

每次真實測試記錄：時間、chain id、合約／escrow id、操作版本或 tx hash、
provider 原始結論的安全摘要、Agent 結論、平台決策、畫面是否顯示，以及是否 synthetic。
任何 key、完整 HTTP header 或帶憑證的 RPC URL 都不能進紀錄。

目前已驗證：本機合約／腳本與 unsigned 參數準備。
尚未驗證：Base 主網部署、真實 Intercepta 回應、Secueji 完整 UI／Agent／policy 串接。
後三項必須在平台整合與部署完成後實測，不得用本 repo 的 Forge 測試取代。
