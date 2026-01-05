import { ponder } from "@/generated";
import { User, Ticket, Pool, Draw, Round, Treasury, Proposal, Vote, Listing } from "../ponder.schema";
import { MasterVaultABI } from "../abis/MasterVault";
import fs from "fs";
import { parseAbi } from "viem";

// --- 初始化 Debug Log ---
if (!fs.existsSync("debug.log")) {
    fs.writeFileSync("debug.log", `--- 系統重啟 ${new Date().toLocaleString()} ---\n`);
}

function logToFile(msg: string) {
  fs.appendFileSync("debug.log", `[${new Date().toLocaleTimeString()}] ${msg}\n`);
  console.log(msg);
}


/**
 * 從鏈上同步 Ticket 的最新狀態 (Assets & Multiplier)
 */
async function syncTicketFromChain(tokenId: string, isWinnerUpdate: boolean, context: any) {
  const { db, client } = context;
  const vaultAddress = process.env.PONDER_MASTER_VAULT_ADDRESS as `0x${string}`;

  try {
    const data = await client.readContract({
      address: vaultAddress,
      abi: parseAbi([
        "function tickets(uint256) view returns (uint128 assets, uint40 mintTime, uint16 multiplier, uint8 mode, bool isDead, uint16 x, uint16 y, uint24 extra)"
      ]),
      functionName: "tickets",
      args: [BigInt(tokenId)],
    }) as any;

    const assets = BigInt(data[0]);
    const multiplier = Number(data[2]);

    logToFile(`[SYNC] Ticket #${tokenId} -> Assets: ${assets}, Multiplier: ${multiplier}, WinStatus: ${isWinnerUpdate}`);

    await db.update(Ticket, { id: tokenId }).set({
      assets: assets,
      multiplier: multiplier,
      ...(isWinnerUpdate ? { isWinner: true } : {}),
    });

    return assets;
  } catch (error: any) {
    logToFile(`[ERROR] 同步 Ticket #${tokenId} 失敗: ${error.message}`);
    return null;
  }
}

/**
 * 處理 Alpha/Savings 開獎事件
 */
async function handleDrawCompleted({ event, context }: any) {
  const { db } = context;
  const { winnerTokenId, drawId } = event.args;
  const tid = winnerTokenId.toString();

  logToFile(`\n開獎事件: Draw #${drawId}, Winner: #${tid}`);

  const finalAssets = await syncTicketFromChain(tid, true, context);

  if (finalAssets !== null) {
    await db.insert(Draw).values({
      id: `${event.log.address}-${drawId}`,
      timestamp: event.block.timestamp,
      winnerTokenId: tid,
      prize: finalAssets,
    }).onConflictDoUpdate((row) => ({
      prize: finalAssets,
      winnerTokenId: tid,
    }));
  }
}

/**
 * 處理 Alpha/Savings 權重演化事件
 */
async function handleTicketEvolved({ event, context }: any) {
  const { tokenId, newWeight } = event.args;
  logToFile(`演化事件: Ticket #${tokenId} 權重變更為 ${newWeight}`);
  await syncTicketFromChain(tokenId.toString(), false, context);
}

// --- 1. MasterVault 核心事件 ---

ponder.on("MasterVault:Deposit", async ({ event, context }) => {
  const { db } = context;
  const { caller, owner, assets, tokenId, mode } = event.args;

  await db.insert(User).values({
    id: owner.toLowerCase(),
    totalDeposited: assets,
    totalWinnings: 0n,
    stakedAmount: 0n,
  }).onConflictDoUpdate((row) => ({
    totalDeposited: row.totalDeposited + assets,
  }));

  // Battle Mode (2) 需要關聯 Round
 let roundId = null;
  if (Number(mode) === 2) {
      const rounds = await db.find(Round, { limit: 10, orderBy: { startTime: "desc" } });
      
      // FIX: 加入安全檢查，避免資料庫為空時報錯
      if (rounds && rounds.items) {
          const activeRound = rounds.items.find(r => r.status === "Active" || r.status === "Joining" || r.status === "Battling");
          if (activeRound) {
              roundId = activeRound.id;
          }
      }
  }

  await db.insert(Ticket).values({
    id: tokenId.toString(),
    ownerId: owner.toLowerCase(),
    mode: Number(mode),
    assets: assets,
    mintTime: event.block.timestamp,
    isDead: false,
    isEliminated: false,
    isWinner: false,
    prize: 0n,
    multiplier: 100,
    roundId: roundId,
  });

  await db.insert(Pool).values({
    id: mode.toString(),
    totalAssets: assets,
    activeTicketsCount: 1,
  }).onConflictDoUpdate((row) => ({
    totalAssets: row.totalAssets + assets,
    activeTicketsCount: row.activeTicketsCount + 1,
  }));
});

ponder.on("MasterVault:RedeemClaim", async ({ event, context }) => {
  const { db } = context;
  const { tokenId, assets } = event.args;

  const ticket = await db.find(Ticket, { id: tokenId.toString() });
  if (!ticket) return;

  await db.update(Ticket, { id: tokenId.toString() }).set({ isDead: true });

  try {
    await db.update(Listing, { id: tokenId.toString() }).set({ 
        isActive: false,
        isCancelled: true 
    });
  } catch (e) {}

  await db.update(Pool, { id: ticket.mode.toString() }).set((row) => ({
    totalAssets: row.totalAssets - ticket.assets,
    activeTicketsCount: row.activeTicketsCount - 1,
  }));
  
  if (assets > ticket.assets) {
      const profit = assets - ticket.assets;
      await db.update(User, { id: ticket.ownerId.toLowerCase() }).set((row) => ({
          totalWinnings: row.totalWinnings + profit
      }));
  }
});

ponder.on("MasterVault:Transfer", async ({ event, context }) => {
  const { db } = context;
  const { from, to, tokenId } = event.args;

  if (from === "0x0000000000000000000000000000000000000000") return;
  if (to === "0x0000000000000000000000000000000000000000") return;

  await db.insert(User).values({
    id: to.toLowerCase(),
    totalDeposited: 0n,
    totalWinnings: 0n,
    stakedAmount: 0n,
  }).onConflictDoUpdate((row) => ({})); 

  await db.update(Ticket, { id: tokenId.toString() }).set({ ownerId: to.toLowerCase() });
});

// --- 2. Alpha & Savings Hook 事件 ---
ponder.on("AlphaHook:DrawCompleted", handleDrawCompleted);
ponder.on("GeneralHook:DrawCompleted", handleDrawCompleted);
ponder.on("AlphaHook:TicketEvolved", handleTicketEvolved);
ponder.on("GeneralHook:TicketEvolved", handleTicketEvolved);

// --- 3. Battle Hook 事件 (修正後) ---

// 事件 1: 開放報名 (對應 startNewRound)
ponder.on("BattleHook:GameRoundOpened", async ({ event, context }) => {
  const { db } = context;
  const { roundId } = event.args;

  logToFile(`Battle Round #${roundId} 開放報名 (Joining)`);

  await db.insert(Round).values({
    id: roundId.toString(),
    startTime: event.block.timestamp,
    prize: 0n,
    radius: 500n,
    x: 500n,
    y: 500n,
    status: "Joining",
  });
});

// 事件 2: 正式開戰 (對應 performShrink - Start)
ponder.on("BattleHook:GameBattlingStarted", async ({ event, context }) => {
  const { db } = context;
  const { roundId, startCenterX, startCenterY } = event.args;

  logToFile(`Battle Round #${roundId} 正式開戰！中心: (${startCenterX}, ${startCenterY})`);

  await db.update(Round, { id: roundId.toString() }).set({
    x: startCenterX,
    y: startCenterY,
    status: "Battling",
  });
});

// 事件 3: 縮圈
ponder.on("BattleHook:ZoneShrunk", async ({ event, context }) => {
  const { db } = context;
  const { roundId, newRadius, newX, newY } = event.args;

  logToFile(`Battle Round #${roundId} 縮圈 -> R: ${newRadius}`);

  await db.update(Round, { id: roundId.toString() }).set({
    x: newX,
    y: newY,
    radius: newRadius,
  });
});

// 事件 4: 玩家淘汰
ponder.on("BattleHook:PlayerEliminated", async ({ event, context }) => {
  const { db } = context;
  const { roundId, tokenId } = event.args;

  logToFile(`Ticket #${tokenId} 在 Round #${roundId} 被淘汰`);

  await db.update(Ticket, { id: tokenId.toString() }).set({
    isEliminated: true,
  });
  
  try {
    await db.update(Listing, { id: tokenId.toString() }).set({ 
        isActive: false,
        isCancelled: true 
    });
  } catch (e) {}
});

// 事件 5: 贏家誕生
ponder.on("BattleHook:WinnerDeclared", async ({ event, context }) => {
  const { db } = context;
  const { roundId, tokenId } = event.args;
  const winnerId = tokenId.toString();
  const rId = roundId.toString();

  logToFile(`Battle Round #${rId} 贏家誕生: Ticket #${winnerId}`);

  // 1. 更新 Round 狀態
  await db.update(Round, { id: rId }).set({
    winnerId: winnerId,
    status: "Ended",
    endTime: event.block.timestamp,
  });

  // 2. 更新贏家 Ticket
  await db.update(Ticket, { id: winnerId }).set({
    isWinner: true,
    isEliminated: false,
  });

  // 3. 淘汰同回合其他輸家
  const roundTickets = await db.find(Ticket, { limit: 1000 }); 
  
  // *** FIX: 這裡加入安全檢查，避免資料庫回傳 null 時崩潰 ***
  if (roundTickets && roundTickets.items) {
      for (const t of roundTickets.items) {
        // 如果是這一回合的票，且不是贏家
        if (t.roundId === rId && t.id !== winnerId) {
            await db.update(Ticket, { id: t.id }).set({ isEliminated: true });
            
            // 取消市場掛單
            try {
                await db.update(Listing, { id: t.id }).set({ isActive: false, isCancelled: true });
            } catch (e) {}
        }
      }
  }
});

// --- 4. Governance 事件 ---

ponder.on("POLStaking:Staked", async ({ event, context }) => {
  const { db } = context;
  const { user, amount } = event.args;

  await db.insert(User).values({
    id: user,
    totalDeposited: 0n,
    totalWinnings: 0n,
    stakedAmount: amount,
  }).onConflictDoUpdate((row) => ({
    stakedAmount: row.stakedAmount + amount,
  }));
});

ponder.on("POLStaking:Unstaked", async ({ event, context }) => {
  const { db } = context;
  const { user, amount } = event.args;

  await db.update(User, { id: user }).set((row) => ({
    stakedAmount: row.stakedAmount - amount,
  }));
});

ponder.on("POLToken:Transfer", async ({ event, context }) => {
    const { db } = context;
    const { to, value } = event.args;
    const TREASURY_ADDRESS = "0x0000000000000000000000000000000000000000"; 

    if (to.toLowerCase() === TREASURY_ADDRESS.toLowerCase()) {
        await db.insert(Treasury).values({
            id: "main",
            balance: value,
        }).onConflictDoUpdate((row) => ({
            balance: row.balance + value,
        }));
    }
});

ponder.on("POLGovernor:ProposalCreated", async ({ event, context }) => {
  const { db } = context;
  const { proposalId, proposer, targets, values, signatures, calldatas, voteStart, voteEnd, description } = event.args;

  await db.insert(Proposal).values({
    id: proposalId.toString(),
    proposer: proposer,
    targets: targets as string[],
    values: values as bigint[],
    signatures: signatures as string[],
    calldatas: calldatas as string[],
    startBlock: voteStart,
    endBlock: voteEnd,
    description: description,
    status: "Created",
    forVotes: 0n,
    againstVotes: 0n,
    abstainVotes: 0n,
  });
});

ponder.on("POLGovernor:VoteCast", async ({ event, context }) => {
  const { db } = context;
  const { voter, proposalId, support, weight, reason } = event.args;

  await db.insert(Vote).values({
    id: `${proposalId}-${voter}`,
    proposalId: proposalId.toString(),
    voter: voter,
    support: support,
    weight: weight,
    reason: reason,
  });

  await db.update(Proposal, { id: proposalId.toString() }).set((row) => ({
    forVotes: support === 1 ? row.forVotes + weight : row.forVotes,
    againstVotes: support === 0 ? row.againstVotes + weight : row.againstVotes,
    abstainVotes: support === 2 ? row.abstainVotes + weight : row.abstainVotes,
  }));
});

ponder.on("POLGovernor:ProposalCanceled", async ({ event, context }) => {
  const { db } = context;
  const { proposalId } = event.args;
  await db.update(Proposal, { id: proposalId.toString() }).set({ status: "Canceled" });
});

ponder.on("POLGovernor:ProposalQueued", async ({ event, context }) => {
  const { db } = context;
  const { proposalId, eta } = event.args;
  await db.update(Proposal, { id: proposalId.toString() }).set({ status: "Queued", eta: eta });
});

ponder.on("POLGovernor:ProposalExecuted", async ({ event, context }) => {
  const { db } = context;
  const { proposalId } = event.args;
  await db.update(Proposal, { id: proposalId.toString() }).set({ status: "Executed" });
});

// --- 5. TicketMarketplace 事件 ---

ponder.on("TicketMarketplace:ItemListed", async ({ event, context }) => {
  const { db } = context;
  const { seller, tokenId, price } = event.args;

  await db.insert(Listing).values({
    id: tokenId.toString(),
    seller: seller.toLowerCase(),
    tokenId: tokenId.toString(),
    price: price,
    isActive: true,
    isSold: false,
    isCancelled: false,
  }).onConflictDoUpdate((row) => ({
    seller: seller.toLowerCase(),
    price: price,
    isActive: true,
    isSold: false,
    isCancelled: false,
  }));
});

ponder.on("TicketMarketplace:ItemCanceled", async ({ event, context }) => {
  const { db } = context;
  const { tokenId } = event.args;
  
  await db.update(Listing, { id: tokenId.toString() }).set({
    isActive: false,
    isCancelled: true,
  });
});

ponder.on("TicketMarketplace:ItemBought", async ({ event, context }) => {
  const { db } = context;
  const { tokenId, buyer } = event.args;
  
  await db.update(Listing, { id: tokenId.toString() }).set({
    isActive: false,
    isSold: true,
  });

  await db.update(Ticket, { id: tokenId.toString() }).set({
    ownerId: buyer.toLowerCase(),
  });

  await db.insert(User).values({
    id: buyer.toLowerCase(),
    totalDeposited: 0n,
    totalWinnings: 0n,
    stakedAmount: 0n,
  }).onConflictDoUpdate((row) => ({}));
});