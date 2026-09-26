# Demo 準備驗證紀錄 — 2026-09-27

## 已執行（本機）

- `forge test --offline --summary`：67 passed、0 failed；含 2 個 fuzz tests（各 256 runs）。
- `ScriptsTest` 單一測試內依序執行網路拒絕檢查，及 chain id 31337／84532／8453 的本機 EVM 流程。
  這些是本機模擬，不是對該網路 RPC 的測試。
- `InterceptaInspectionTest`：未簽名 release 參數、退款／暫停狀態、不存在 escrow 拒絕；
  確認查詢不造成資產轉移。ScriptsTest 額外驗證私鑰空白時可執行唯讀入口。
- `forge build --offline`：成功。既有 GuardExecutor timestamp 與 DemoStablecoin tests
  unchecked-transfer lint 警告保留，不等於合約安全審計通過。
- `forge fmt --check script test/NetworkSafety.t.sol test/Scripts.t.sol test/InterceptaInspection.t.sol`：通過。
- 全 repo `forge fmt --check`：既有 `src/DemoEscrow.sol`、`src/GuardExecutor.sol` 格式差異；未修改這兩份合約。
- 兩份新增 JSON 可解析，9 個 scenario id 不重複，主網紀錄樣板為 `NOT_DEPLOYED`。
- `git diff --check`：通過；`.env.base-mainnet` 被 gitignore 排除。

工具：Forge 1.7.1、Solidity 0.8.28、forge-std v1.16.2（既有 submodule revision 未更動）。
首次測試補齊缺少的編譯器與既有 submodule，後續測試均 offline。

## 未執行／不可宣稱已通過

- 主網 RPC 查詢、部署、broadcast、角色錢包充值。
- 真實 Intercepta API 呼叫、provider 風險命中率。
- Secueji 平台的 Agent／policy／前端完整整合驗收。
- 新版投影片、英文講稿及日文錄影注意事項；待平台整合與實測後依實際成果更新。

情境 manifest 是測試計畫，SYNTHETIC cases 需由平台的測試 adapter 執行；
沒有以合成結果冒充 provider 的真實回應。
