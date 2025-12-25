# Proof Of Luck (Base Fork Edition)

**Proof Of Luck** 是一個基於 **Base 鏈** 的去中心化遊戲化儲蓄協議。  
它結合了 **無損彩票**、**收益聚合** 與 **大逃殺遊戲** 機制，透過模組化的 **Master Vault + Hooks** 架構，讓使用者在存入 USDC 賺取收益的同時，體驗多元的遊戲樂趣。

本專案為 **Base Mainnet Fork** 版本，使用 **Foundry (Anvil)** 進行本地模擬，並整合 **Ponder** 進行數據索引。

---

##  核心特色 (Key Features)

- **無損彩票 (No-Loss Lottery)**  
  本金存入 Aave / Aerodrome 生息，收益用於獎金分配，本金安全無虞。

- **大逃殺模式 (Battle Royale)**  
  獨創的 DeFi 遊戲機制。存入資金作為「門票」進入地圖，隨著時間推移「縮圈」，倖存者獨得該回合所有收益。

- **Zap 一鍵存款**  
  整合 Uniswap V3 Router，支援任意代幣（ETH、DEGEN、AERO…）自動兌換為 USDC 並存入遊戲池。

- **動態 NFT**  
  每一筆存款都會鑄造一張 ERC-721 票券，SVG 圖片完全鏈上生成，即時顯示資產餘額、遊戲狀態與地圖座標。

- **治理代幣 ($POL)**  
  結合 Staking 與 Governor 機制，質押 $POL 可獲得投票權並影響協議參數。

---

##  架構說明

### Master Vault
- 資金託管核心  
- 負責鑄造 NFT  
- 路由資金至各個 Adapter

---

### Hooks（純邏輯合約）

- **GeneralHook**  
  每日開獎，權重進化機制

- **AlphaHook**  
  每週開獎，槓桿保險額度檢查（Leverage Cap）

- **BattleHook**  
  回合制大逃殺，負責地圖、縮圈與淘汰邏輯

---

### Adapters（策略適配器）

- **AaveAdapter**  
  存入 Aave V3 借貸池

- **AeroAdapter**  
  將 USDC 轉為 LP（如 USDC–USDbC），並質押至 Aerodrome Gauge

---

### Indexer
- 使用 **Ponder** 取代 The Graph  
- 實現極速本地索引

---

## 遊戲模式 (Game Modes)

| 模式 | Hook | 底層策略 | 機制說明 |
|----|----|----|----|
| Savings（儲蓄） | GeneralHook | Aave V3 | 每日開獎，隨存隨取，未中獎 NFT 權重隨時間進化 |
| Alpha（進階） | AlphaHook | DAO決定 | 每週開獎，高額獎金池，TVL 上限由 $POL 質押量決定，20% 收益回購 $POL |
| Battle（大逃殺） | BattleHook | Aerodrome | 回合制生存遊戲，VRF 隨機縮圈，圈外淘汰，倖存者獨得全部利息 |

---

## 🛠 技術棧 (Tech Stack)

- **Smart Contracts**：Solidity ^0.8.30, Foundry（Forge / Cast / Anvil）
- **Indexer**：Ponder（TypeScript）
- **Frontend**：Next.js 14, Wagmi, Viem, RainbowKit, Styled-components
- **Chain**：Base Mainnet（Local Fork）

---

## 快速開始 (Getting Started)

### 1. 環境準備

請確保已安裝：

- Foundry  
- Node.js（v18+）  
- pnpm 或 Bun  

---

### 2. 啟動區塊鏈（Base Fork）

```bash
# 在 packages/contracts 目錄下
cd packages/contracts

# 建立 .env 並填入 RPC
echo "BASE_RPC_URL=https://mainnet.base.org" > .env

# 啟動 Anvil（Fork 模式）
anvil --fork-url https://mainnet.base.org --chain-id 31337 --block-time 2
```

---

### 3. 部署合約
```bash
cd packages/contracts

forge script script/DeployFork.s.sol:DeployFork \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast \
  --unlocked
```

- 部署完成後會自動更新：

- packages/web/src/utils/contracts.ts

- packages/ponder/.env.local

---

### 4. 啟動 Indexer（Ponder）
```bash
cd packages/ponder
pnpm install
pnpm dev
Ponder 運行於：http://localhost:42069
```
---

### 5. 啟動前端（Web）
```bash
cd packages/web
pnpm install
pnpm dev
```

- 前端運行於：http://localhost:3000

## 測試與操作指南
### 獲取測試代幣
- 部署腳本會自動從 Base 鏈巨鯨帳戶轉移 USDC 到測試帳戶（Account #0）。

- 若需要更多代幣：

```bash 
forge script script/FundAccount.s.sol \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast \
  --unlocked
```
---

## 前端功能
**Lotto Page** 
- Savings / Alpha：輸入 USDC 存款（支援 Zap）

- Battle：點擊 Enter Battle，在地圖上選擇落點座標

- Admin Bot：支援 evm_increaseTime

- Mock VRF 開獎 / 縮圈

**NFT Page**
- 查看、上架、購買 Ticket NFT

**Governance Page**
- 質押 $POL

- 建立與投票提案

**POL Page**
- USDC ↔ $POL 兌換

## 目錄結構
```text
packages/
├── contracts/
│   ├── src/
│   │   ├── MasterVault.sol
│   │   ├── hooks/
│   │   ├── adapters/
│   │   └── governance/
│   └── script/
├── ponder/
│   ├── ponder.schema.ts
│   └── src/index.ts
└── web/
    ├── src/app/
    └── src/components/
```

## 授權
MIT License