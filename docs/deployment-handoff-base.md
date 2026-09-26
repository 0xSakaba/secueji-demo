# 給部署同事：Base 主網 demo 交接

## 本次要部署什麼

沿用現有 `DemoStablecoin` 與 `DemoEscrow`，**合約 src/ 沒有因 Intercepta 改動**。
不必部署惡意合約、drainer 或舊版 GuardExecutor。Base chain id 必須為 **8453**。
先依 [主網操作指南](base-mainnet-demo.md) 檢查角色、預算、dry-run，再由你人工決定廣播。
本次程式修改沒有部署、簽名或充值任何主網帳戶。

部署修改已可交接；**不代表 Intercepta 風險案例已通過真實 API**。
新的 demo 是「準備高風險 token 授權 → Intercepta 發現風險 → Secueji 顯示並限制操作」。

## 操作順序

1. 準備獨立 demo 錢包與經核准的少量 gas ETH；不沿用公開測試私鑰。
2. 依 `.env.base-mainnet.example` 填入私有設定，確認 `EXPECTED_CHAIN_ID=8453`。
3. 人工確認後才開 `ALLOW_BASE_MAINNET=true`；operator 補款金額需明確填寫。
4. 先模擬 `Deploy.s.sol`，核對費用與角色，再依團隊授權部署 token／escrow。
5. 驗證 source，保存成功 receipt、地址與部署 block。
6. 如需完整 escrow demo，再跑 OnboardOperator 與 Seed，保留实际 id／title 對照。
7. 高風險授權案例的 owner 使用平台 operator 地址；如需要餘額，可由 minter 給它少量
   自製 dUSD（例如 10 dUSD），不要送真實穩定幣。這不需要給任何外部 spender 授權。

## 請回傳以下公開資料，勿回傳私鑰或 RPC key

- chain id `8453`、實際部署 source commit。
- DemoStablecoin、DemoEscrow 地址及對應 deployment transaction hash／block。
- operator／admin／buyer 公開地址、operator 是否已設為 guardian。
- source verification explorer 連結；如有 seed，附本次 escrow id／title 對照。
- operator 的 demo token 餘額（若有 mint，附其 transaction hash）。

紀錄欄位可參考 `deployments/base-mainnet.example.json`，真正驗證後才建立主網部署紀錄。

## 不需要你做的事

- 不需填 Intercepta key；它只放 Secueji 平台的 server 環境。
- 不需挑選或連線惡意網站；spender 候選及風險命中由平台工程師實測。
- **不要簽名或 broadcast 高風險 approve，也不要真的讓候選 spender 取得 allowance。**
- 不需為了 Intercepta 去修改 escrow 漏洞；這個案例掃描的是未簽名 token 授權。

部署後平台工程師會使用 `PrepareRiskyApproval.s.sol` 產生 calldata。
這個腳本僅編碼資料，不呼叫 `approve`、不讀私鑰，也不執行任何交易。
真正 API 命中前不得宣稱 Intercepta 已發現這個案例的風險。
