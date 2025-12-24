// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../src/MasterVault.sol";
import "../src/hooks/GeneralHook.sol";
import "../src/adapters/AaveAdapter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../src/mocks/VRFCoordinatorMock.sol";

contract GeneralPoolTest is Test {
    MasterVault vault;
    GeneralHook hook;
    AaveAdapter adapter;
    VRFCoordinatorMock vrfCoordinator;

    // Base Mainnet 地址
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant AAVE_POOL = 0xA238Dd80C259a72e81d7e4664a9801593F98d1c5;
    address constant WHALE = 0x3304e22DdAA22bCdc5fca2269b4180919E639828; // Base 上的 USDC 巨鯨

    function setUp() public {
        // Fork Base Mainnet
        string memory rpcUrl = vm.envString("BASE_RPC_API_URL");
        vm.createSelectFork(rpcUrl);
        // 假設 Fork 已經透過 CLI flag 啟動

        // 部署 Mock
        vrfCoordinator = new VRFCoordinatorMock();

        // 部署合約
        vault = new MasterVault(USDC);
        hook = new GeneralHook(
            address(vault),
            address(vrfCoordinator),
            bytes32(0), // keyHash
            1 // subId
        );
        // Base aUSDC: 0x4e65fE4DbA92790696d040ac24Aa414708F5c0AB
        adapter = new AaveAdapter(USDC, AAVE_POOL, 0x4e65fE4DbA92790696d040ac24Aa414708F5c0AB, address(vault));

        // 設定 Vault
        vault.setAdapter(address(hook), address(adapter));
        vault.registerMode(2, address(hook));
    }

    function testDepositAndRedeem() public {
        console.log("=== Starting testDepositAndRedeem ===");
        uint256 amount = 100 * 1e6; // 100 USDC

        // 使用 Foundry deal 給予巨鯨 (或任意地址) USDC
        deal(USDC, WHALE, amount);

        // 模擬巨鯨
        vm.startPrank(WHALE);
        
        // 授權 Vault
        IERC20(USDC).approve(address(vault), amount);

        // 存款
        console.log("Depositing", amount, "USDC...");
        // General Pool 目前不需要額外 data
        bytes memory data = abi.encode(uint256(0), uint256(0));
        uint256 tokenId = vault.deposit(amount, WHALE, 2, data);
        console.log("Deposit successful. Token ID:", tokenId);

        // 驗證 Ticket
        (uint128 assets, , , uint8 mode, , , , ) = vault.tickets(tokenId);
        assertEq(uint256(assets), amount);
        assertEq(mode, 2);

        // 驗證資金已移至 Aave (Adapter 應持有 aUSDC)
        // Base 上的 aUSDC 地址: 0x4e65fE4DbA92790696d040ac24Aa414708F5c0AB
        address aUSDC = 0x4e65fE4DbA92790696d040ac24Aa414708F5c0AB;
        uint256 adapterBalance = IERC20(aUSDC).balanceOf(address(adapter));
        
        // Aave aTokens 會 Rebase，所以餘額可能會有微小差異
        console.log("Adapter aUSDC Balance:", adapterBalance);
        assertApproxEqAbs(adapterBalance, amount, 100); // 允許微小的捨入誤差

        // 快轉時間以累積利息 (避免餘額 < 本金的捨入問題)
        console.log("Warping time by 1 day...");
        vm.warp(block.timestamp + 1 days);

        // 請求贖回
        console.log("Requesting redeem...");
        // vault.requestRedeem(tokenId, ""); // Removed
        
        // 領取贖回
        console.log("Claiming redeem...");
        uint256 redeemedAmount = vault.claimRedeem(tokenId);
        console.log("Redeemed Amount:", redeemedAmount);
        
        // 驗證 1: 使用者僅取回本金 (No-Loss Lottery 機制)
        assertEq(redeemedAmount, amount); 

        // 驗證 2: 利息留在 Adapter 中 (作為獎金池)
        // 檢查 Adapter 剩餘的 aUSDC 餘額
        uint256 remainingYield = IERC20(aUSDC).balanceOf(address(adapter));
        console.log("Yield generated (remaining in Adapter):", remainingYield);
        
        // 確保確實產生了利息 (因為我們 warp 了 1 天)
        assertTrue(remainingYield > 0, "Yield should be generated and stay in protocol");

        vm.stopPrank();
        console.log("=== testDepositAndRedeem Completed ===");
    }

    function testLotteryDraw() public {
        console.log("=== Starting testLotteryDraw ===");
        uint256 amount = 100 * 1e6;
        deal(USDC, WHALE, amount * 2);

        vm.startPrank(WHALE);
        IERC20(USDC).approve(address(vault), amount * 2);

        // 1. 存款 (產生 2 張 Ticket)
        console.log("Depositing 2 tickets...");
        bytes memory data = abi.encode(uint256(0), uint256(0));
        uint256 tokenId1 = vault.deposit(amount, WHALE, 2, data);
        uint256 tokenId2 = vault.deposit(amount, WHALE, 2, data);
        vm.stopPrank();
        console.log("Tickets created:", tokenId1, tokenId2);

        // 驗證初始權重
        assertEq(hook.nftWeight(tokenId1), 100);
        assertEq(hook.nftWeight(tokenId2), 100);

        // 2. 快轉時間 (滿足 drawInterval)
        console.log("Warping time by 1 day + 1 second...");
        vm.warp(block.timestamp + 1 days + 1);

        // 3. 觸發開獎
        // 任何人都可以呼叫 performDraw
        console.log("Performing draw...");
        hook.performDraw();

        // 驗證狀態: 開獎進行中
        assertTrue(hook.isDrawPending());

        // 4. 模擬 VRF 回調
        // 獲取 Request ID (從 Mock 的事件或狀態獲取，這裡簡化假設是 1，因為是第一次請求)
        // 在 Mock 中 nextRequestId 從 1 開始，第一個請求 ID 為 1
        uint256 requestId = 1;

        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 12345; // 隨機數

        // 呼叫 Mock 履行隨機數
        console.log("Fulfilling random words (Mock VRF)...");
        vrfCoordinator.fulfillRandomWords(requestId, randomWords);

        // 5. 驗證開獎結果
        // 贏家索引 = 12345 % 2 = 1
        // activeTickets = [tokenId1, tokenId2]
        // 贏家應該是 tokenId2
        
        // 驗證狀態: 開獎結束
        assertFalse(hook.isDrawPending());
        
        uint256 w1 = hook.nftWeight(tokenId1);
        uint256 w2 = hook.nftWeight(tokenId2);
        console.log("Weight Token1:", w1);
        console.log("Weight Token2:", w2);

        // 驗證權重變化
        // tokenId2 應該增加 5 (變為 105)
        // tokenId1 保持 100 (Winner resets)
        assertEq(w2, 105);
        assertEq(w1, 100);
        assertEq(w1, 100);
        
        console.log("=== testLotteryDraw Completed ===");
    }
}
