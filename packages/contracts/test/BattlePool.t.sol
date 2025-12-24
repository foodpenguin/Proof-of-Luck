// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../src/MasterVault.sol";
import "../src/hooks/BattleHook.sol";
import "../src/adapters/AaveAdapter.sol";
import "../src/adapters/AeroAdapter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract BattlePoolTest is Test {
    MasterVault vault;
    BattleHook hook;
    AeroAdapter adapter;

    // Base Mainnet 地址
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant AAVE_POOL = 0xA238Dd80C259a72e81d7e4664a9801593F98d1c5;
    address constant WHALE = 0x3304e22DdAA22bCdc5fca2269b4180919E639828;

    // Aerodrome Addresses
    address constant AERO_ROUTER = 0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43;
    address constant AERO_FACTORY = 0x420DD381b31aEf6683db6B902084cB0FFECe40Da;
    address constant USDbC = 0xd9aAEc86B65D86f6A7B5B1b0c42FFA531710b6CA;
    address constant AERO_TOKEN = 0x940181a94A35A4569E4529A3CDfB74e38FD98631;
    address constant AERO_USDC_USDBC_POOL = 0x27a8Afa3Bd49406e48a074350fB7b2020c43B2bD;
    address constant AERO_USDC_USDBC_GAUGE = 0x1Cfc45C5221A07DA0DE958098A319a29FbBD66fE;

    function setUp() public {
        string memory rpcUrl = vm.envString("BASE_RPC_API_URL");
        vm.createSelectFork(rpcUrl);

        vault = new MasterVault(USDC);
        hook = new BattleHook(address(vault));
        
        // Use AeroAdapter (Real)
        adapter = new AeroAdapter(
            USDC,
            USDbC,
            AERO_TOKEN,
            AERO_ROUTER,
            AERO_USDC_USDBC_GAUGE,
            AERO_USDC_USDBC_POOL,
            AERO_FACTORY,
            true, // stable
            address(vault)
        );

        vault.setAdapter(address(hook), address(adapter));
        vault.registerMode(1, address(hook));
        
        // 啟動遊戲
        hook.startGame();
    }

    function testBattleRoyaleFlow() public {
        console.log("=== Starting testBattleRoyaleFlow ===");
        uint256 ticketPrice = 100 * 1e6;
        deal(USDC, WHALE, ticketPrice * 2);

        vm.startPrank(WHALE);
        IERC20(USDC).approve(address(vault), ticketPrice * 2);

        // 1. 玩家 A: 位於中心 (500, 500) - 安全
        bytes memory dataA = abi.encode(uint256(500), uint256(500));
        uint256 tokenA = vault.deposit(ticketPrice, WHALE, 1, dataA);
        console.log("Player A deposited at (500, 500). Token ID:", tokenA);

        // 2. 玩家 B: 位於邊緣 (900, 900) - 初始安全，但會被淘汰
        // 距離中心: dx=400, dy=400. distSq = 160000 + 160000 = 320000
        // 初始半徑 500 => r^2 = 250000. 
        // 等等，320000 > 250000. 玩家 B 一開始就在圈外？
        // 讓我們算一下 Toroidal Distance.
        // x1=900, x2=500. dx=400. MAP_SIZE=1000. dx < 500. 正確。
        // 距離確實是 sqrt(320000) = 565.6.
        // 初始半徑 500.
        // 所以 (900, 900) 一開始就在圈外！
        
        // 讓我們換個位置給 B，讓他一開始在圈內，後來被淘汰。
        // 目標距離: < 500 但 > 未來半徑。
        // 設半徑縮小到 400 (10天後)。
        // 我們需要距離在 400~500 之間。
        // 設 dx=0, dy=450. (500, 950).
        // distSq = 0 + 450^2 = 202500.
        // r=500 => r^2 = 250000. (Safe)
        // r=400 => r^2 = 160000. (Eliminated)
        
        bytes memory dataB = abi.encode(uint256(500), uint256(950));
        uint256 tokenB = vault.deposit(ticketPrice, WHALE, 1, dataB);
        console.log("Player B deposited at (500, 950). Token ID:", tokenB);

        // 驗證初始狀態
        assertFalse(hook.checkElimination(tokenA), "Player A should be safe");
        assertFalse(hook.checkElimination(tokenB), "Player B should be safe initially");

        // 3. 玩家 A 提早退出 (Early Withdrawal)
        // 預期: 扣除 10% 罰金
        console.log("Player A requesting early redeem...");
        // vault.requestRedeem(tokenA, ""); // Removed
        uint256 redeemedA = vault.claimRedeem(tokenA);
        console.log("Player A redeemed:", redeemedA);
        
        assertEq(redeemedA, ticketPrice * 90 / 100, "Player A should pay 10% penalty");

        // 4. 快轉時間 (15 天)
        // 縮圈速率 10/天。15天 => 縮小 150。
        // 新半徑 = 500 - 150 = 350。
        // 玩家 B 距離 450。 450 > 350 => 淘汰。
        console.log("Warping 15 days...");
        vm.warp(block.timestamp + 15 days);
        
        uint256 currentRadius = hook.getCurrentRadius();
        console.log("Current Radius:", currentRadius);
        assertEq(currentRadius, 350);

        // 驗證 B 被淘汰
        assertTrue(hook.checkElimination(tokenB), "Player B should be eliminated");

        // 5. 玩家 B 贖回 (Eliminated)
        // 預期: 取回本金 (無罰金)
        console.log("Player B requesting redeem (Eliminated)...");
        // vault.requestRedeem(tokenB, ""); // Removed
        uint256 redeemedB = vault.claimRedeem(tokenB);
        console.log("Player B redeemed:", redeemedB);

        assertEq(redeemedB, ticketPrice, "Player B should get full principal");

        // 6. 玩家 C: 贏家 (最後倖存者)
        // 為了測試贏家邏輯，我們需要一個新玩家 C，他在安全區內。
        // 由於 A 已退出，B 已淘汰。如果我們再加一個 C，他就是唯一倖存者。
        // 但現在時間已經過了 15 天，半徑 350。
        // 我們讓 C 在 (500, 500) 加入 (假設允許中途加入)。
        
        // 重置狀態或新局比較乾淨，但這裡繼續用。
        // 為了讓 C 成為贏家，我們需要確保 activeTickets 只有 C 是 safe 的。
        // 目前 activeTickets 裡有 B (Eliminated)。A 已經退出 (removed)。
        // 所以如果 C 加入，activeTickets = [B, C]。
        // B is eliminated. C is safe. Survivor count = 1. C wins!
        
        console.log("Player C joining at (500, 500)...");
        deal(USDC, WHALE, ticketPrice * 2); // 確保有足夠餘額
        IERC20(USDC).approve(address(vault), ticketPrice * 2); // 重新授權
        bytes memory dataC = abi.encode(uint256(500), uint256(500));
        uint256 tokenC = vault.deposit(ticketPrice, WHALE, 1, dataC);
        
        // 驗證 C 是贏家
        uint256 winner = hook.getWinner();
        console.log("Winner Token ID:", winner);
        assertEq(winner, tokenC, "Player C should be the winner");

        vm.stopPrank();
        // Set Governance (as Owner)
        address governance = address(0x999);
        hook.setGovernance(governance);
        vm.startPrank(WHALE);

        // 7. 贏家領獎
        // 預期: 本金 + 累積的 Yield (不含罰金)
        // 罰金去 Governance
        
        console.log("Player C claiming prize...");
        uint256 govBalanceBefore = IERC20(USDC).balanceOf(governance);
        
        // vault.requestRedeem(tokenC, ""); // Removed
        uint256 redeemedC = vault.claimRedeem(tokenC);
        console.log("Player C redeemed:", redeemedC);
        
        // C gets Principal (100) + Interest.
        // Interest is small.
        assertTrue(redeemedC >= 100 * 1e6, "Winner should get principal");
        assertTrue(redeemedC < 110 * 1e6, "Winner should NOT get penalties");
        
        uint256 govBalanceAfter = IERC20(USDC).balanceOf(governance);
        console.log("Governance Balance:", govBalanceAfter);
        assertEq(govBalanceAfter - govBalanceBefore, 10 * 1e6, "Governance should get penalties");

        vm.stopPrank();
        console.log("=== testBattleRoyaleFlow Completed ===");
    }
}
