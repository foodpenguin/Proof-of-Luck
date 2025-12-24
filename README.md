# Proof Of Luck (Base Fork Edition) - System Design Document

## 1. 專案概述 (Project Overview)
*   **名稱**: Proof Of Luck
*   **目標**: 學習與研究型專案 (Fork Base Mainnet)。
*   **核心概念**: 結合「無損彩票」、「DeFi 收益聚合」與「大逃殺遊戲」的結構化資產管理協議。
*   **部署網路**: Base Mainnet (Local Fork via Anvil)。
*   **前端交互**: Next.js + Wagmi + OKX Wallet。

## 2. 核心架構 (Core Architecture)
系統採用 **"Master Vault + Hooks"** 的模組化設計，結合 **ERC-7540** 異步金庫標準。

*   **入口層 (Gateway)**:
    *   **Zap Router**: 聚合 Aerodrome/Uniswap，支援任意代幣 (ETH/DEGEN) 一鍵 Swap 轉 USDC 並存入 Vault。
*   **資金層 (Treasury)**:
    *   **Master Vault (Singleton)**:
        *   標準: **ERC-7540** (異步存取 Request/Claim) + **ERC-721** (Ticket NFT)。
        *   職責: 保管 USDC，鑄造 NFT 憑證，對接底層 Adapter。
*   **邏輯層 (Brain)**:
    *   **Hooks**: 純邏輯合約，無資金。Vault 在 `deposit/redeem` 前後呼叫 Hook。
    *   **Hook 列表**:
        1.  `GeneralHook`: 每日開獎邏輯，VRF 快照。
        2.  `AlphaHook`: 保險額度檢查，UMA 防賄賂。
        3.  `BattleHook`: 地圖座標記錄，縮圈淘汰邏輯。
*   **策略層 (Hands)**:
    *   **Adapters**: 統一接口，對接外部 DeFi。
    *   `AaveAdapter`: 對接 Aave V3 (一般池)。
    *   `AeroAdapter`: 對接 Aerodrome Gauge (Battle 池)。

## 3. 遊戲模式機制 (Game Mechanics)

| 模式 | 頻率 | 風險 | 收益來源 | 機制亮點 |
| :--- | :--- | :--- | :--- | :--- |
| **Savings (一般)** | 每日 | 零 | Aave V3 | 隨機 1% NFT 權重進化，隨存隨取。 |
| **Alpha (收益)** | 每週 | 低 | 透過治理投票 | **$POL 質押擔保**。巨額獎金效應。UMA + Slashing 雙重防護。 |
| **Battle (大逃殺)** | 賽季 | 零* | Aerodrome | **環狀地圖縮圈**。淘汰者利息充公。早退罰款。倖存者全拿。 |
*(備註: 大逃殺本金無損，但被淘汰會損失利息)*

## 4. 代幣經濟與治理 (Tokenomics & Governance)
*   **代幣**: `$POL` (ERC20Votes)。
*   **飛輪效應**:
    1.  協議收入 (20% Alpha 利潤 + 罰款) -> **回購 $POL** -> **分發給質押者**。
    2.  質押 $POL -> 提供 Alpha 池 **槓桿保險額度 (Cap)** -> 允許更多 TVL。
*   **治理安全**:
    *   **UMA**: 樂觀預言機，攔截惡意提案。
    *   **Slashing**: 若策略虧損，自動拍賣質押的 $POL 賠付 Alpha 池。

## 5. 技術棧 (Tech Stack)
*   **區塊鏈節點**: **Foundry (Anvil)** - Fork Base Mainnet。
*   **智能合約**: **Solidity**。
*   **數據索引**: **Ponder** (取代 The Graph，本地極速索引)。
*   **Mock 工具**: `VRFCoordinatorMock` (模擬 Chainlink), `vm.warp` (模擬時間), `vm.deal` (模擬資金)。
*   **前端**: **Next.js**, **RainbowKit**, **Wagmi (viem)**。
*   **錢包**: **OKX Wallet** (自定義 RPC: `http://127.0.0.1:8545`).

## 6. 開發路線圖 (Development Roadmap)

### Sprint 1: 地基 (The Core)
*   [ ] 定義 `IPOLHook` 接口。
*   [ ] 開發 `MasterVault` (ERC-7540 + ERC-721)。
*   [ ] 開發 `AaveAdapter` 並在 Fork 環境測試存取款。

### Sprint 2: 大腦 (The Brains)
*   [ ] 開發 `VRFCoordinatorMock`。
*   [ ] 開發 `GeneralHook`: 每日開獎與 NFT 權重進化。
*   [ ] 開發 `BattleHook`: 地圖座標解碼與縮圈邏輯。

### Sprint 3: 治理 (The Law)
*   [ ] 發行 `$POL` 代幣 (ERC20Votes)。
*   [ ] 部署 Governor 合約。
*   [ ] 開發 `AlphaHook`: 實作保險額度檢查 (Leverage Cap)。

### Sprint 4: 數據 (The Eyes)
*   [ ] 配置 Ponder。
*   [ ] 索引: NFT 鑄造、等級變化、開獎事件、提案狀態。

### Sprint 5: 入口 (The Gateway)
*   [ ] 開發 `ZapRouter`: 整合 Aerodrome Router。
*   [ ] 前端整合: 連接 OKX 錢包，讀取 Ponder API，呼叫合約。
