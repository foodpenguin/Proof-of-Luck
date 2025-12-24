import { ponder } from "@/generated";
import { User, Ticket, Pool, Draw, Battle, Treasury, Proposal, Vote, Listing } from "../ponder.schema";

ponder.on("MasterVault:Deposit", async ({ event, context }) => {
  const { db } = context;
  const { caller, owner, assets, tokenId, mode } = event.args;

  // Update User
  await db.insert(User).values({
    id: owner.toLowerCase(),
    totalDeposited: assets,
    totalWinnings: 0n,
    stakedAmount: 0n,
  }).onConflictDoUpdate((row) => ({
    totalDeposited: row.totalDeposited + assets,
  }));

  // Create Ticket
  await db.insert(Ticket).values({
    id: tokenId.toString(),
    ownerId: owner.toLowerCase(),
    mode: Number(mode),
    assets: assets,
    mintTime: event.block.timestamp,
    isDead: false,
    isWinner: false,
    prize: 0n,
    multiplier: 100,
  });

  // Update Pool
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

  // Mark Ticket as Dead
  await db.update(Ticket, { id: tokenId.toString() }).set({ isDead: true });

  // Update Pool
  await db.update(Pool, { id: ticket.mode.toString() }).set((row) => ({
    totalAssets: row.totalAssets - ticket.assets,
    activeTicketsCount: row.activeTicketsCount - 1,
  }));
  
  // If assets > ticket.assets, it's a win
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

  if (from === "0x0000000000000000000000000000000000000000") return; // Mint handled by Deposit
  if (to === "0x0000000000000000000000000000000000000000") return; // Burn handled by RedeemClaim (keep owner for history)

  // Ensure 'to' user exists
  await db.insert(User).values({
    id: to.toLowerCase(),
    totalDeposited: 0n,
    totalWinnings: 0n,
    stakedAmount: 0n,
  }).onConflictDoUpdate((row) => ({})); 

  await db.update(Ticket, { id: tokenId.toString() }).set({ ownerId: to.toLowerCase() });
});

ponder.on("AlphaHook:DrawCompleted", async ({ event, context }) => {
  const { db } = context;
  const { drawId, winnerTokenId, randomWord } = event.args;

  // Create Draw Record
  await db.insert(Draw).values({
    id: drawId.toString(),
    timestamp: event.block.timestamp,
    winnerTokenId: winnerTokenId.toString(),
    prize: 0n, 
  });

  // Mark Winner
  await db.update(Ticket, { id: winnerTokenId.toString() }).set({ isWinner: true });
});

ponder.on("BattleHook:GameStarted", async ({ event, context }) => {
  const { db } = context;
  const { startTime } = event.args;

  await db.insert(Battle).values({
    id: startTime.toString(),
    startTime: startTime,
    prize: 0n,
  });
});

ponder.on("BattleHook:WinnerDeclared", async ({ event, context }) => {
  const { db } = context;
  const { tokenId, prize } = event.args;

  await db.update(Ticket, { id: tokenId.toString() }).set({
    isWinner: true,
    prize: prize,
  });

  const ticket = await db.find(Ticket, { id: tokenId.toString() });

  if (ticket) {
      await db.update(User, { id: ticket.ownerId }).set((row) => ({
          totalWinnings: row.totalWinnings + prize
      }));
  }
});

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


