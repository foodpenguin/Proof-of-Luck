import { ponder } from "@/generated";
import { User, Ticket, Pool, Draw, Round, Treasury, Proposal, Vote, Listing } from "../ponder.schema";
import { desc } from "@ponder/core";

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

  // Determine Round ID for Battle Mode (Mode 2)
  let roundId = null;
  if (mode === 2) {
      // Find the latest active round
      // Fallback to simple find and sort in memory to avoid API issues
      const rounds = await db.find(Round, { limit: 50 });
      if (rounds && rounds.items) {
          const activeRound = rounds.items
              .sort((a, b) => Number(b.startTime - a.startTime))
              .find(r => r.status === "Active");
          
          if (activeRound) {
              roundId = activeRound.id;
          }
      }
  }

  // Create Ticket
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

  // Cancel any active listing (Zombie Order Fix)
  try {
    await db.update(Listing, { id: tokenId.toString() }).set({ 
        isActive: false,
        isCancelled: true 
    });
  } catch (e) {
    // Listing might not exist, ignore
  }

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

// --- Battle Hook Events ---

ponder.on("BattleHook:GameStarted", async ({ event, context }) => {
  const { db } = context;
  const { roundId, startTime } = event.args;

  await db.insert(Round).values({
    id: roundId.toString(),
    startTime: startTime,
    prize: 0n,
    radius: 500n, // Initial Radius
    x: 500n, // Initial Center
    y: 500n, // Initial Center
    status: "Active",
  });
});

ponder.on("BattleHook:ZoneShrunk", async ({ event, context }) => {
  const { db } = context;
  const { roundId, newRadius, centerX, centerY } = event.args;

  await db.update(Round, { id: roundId.toString() }).set({
    x: centerX,
    y: centerY,
    radius: newRadius,
  });
});

ponder.on("BattleHook:PlayerEliminated", async ({ event, context }) => {
  const { db } = context;
  const { roundId, player } = event.args;

  // Find ticket for this player in this round
  // Note: This is inefficient if there are many tickets. 
  // Ideally we should filter by roundId and ownerId in the DB query.
  const tickets = await db.find(Ticket, { limit: 1000 });
  const ticket = tickets.items.find(t => t.ownerId.toLowerCase() === player.toLowerCase() && t.roundId === roundId.toString());

  if (ticket) {
    await db.update(Ticket, { id: ticket.id }).set({
      isEliminated: true,
    });
    
    // Also remove from marketplace
    try {
      await db.update(Listing, { id: ticket.id }).set({ 
          isActive: false,
          isCancelled: true 
      });
    } catch (e) {}
  }
});

ponder.on("BattleHook:WinnerDeclared", async ({ event, context }) => {
  const { db } = context;
  const { roundId, winner, prize } = event.args;

  // Find ticket for this player in this round
  const tickets = await db.find(Ticket, { limit: 1000 });
  const ticket = tickets.items.find(t => t.ownerId.toLowerCase() === winner.toLowerCase() && t.roundId === roundId.toString());

  if (ticket) {
      // Update Round
      await db.update(Round, { id: roundId.toString() }).set({
        winnerId: ticket.id,
        prize: prize,
        status: "Ended",
        endTime: event.block.timestamp,
      });

      // Update Winner Ticket
      await db.update(Ticket, { id: ticket.id }).set({
        isWinner: true,
        prize: prize,
      });

      // Update User Winnings
      await db.update(User, { id: ticket.ownerId }).set((row) => ({
          totalWinnings: row.totalWinnings + prize
      }));
  }

  // Marketplace Cleanup: Eliminate all losers in this round
  // We already fetched tickets, so we can reuse the list or fetch again if needed.
  // For simplicity and correctness (in case of pagination), we'll use the existing logic but adapted.
  
  const allTickets = await db.find(Ticket, { 
      limit: 1000 
  }); 
  
  for (const t of allTickets.items) {
      if (t.roundId === roundId.toString() && (!ticket || t.id !== ticket.id)) {
          await db.update(Ticket, { id: t.id }).set({ isEliminated: true });
          
          // Remove from marketplace
          try {
            await db.update(Listing, { id: t.id }).set({ 
                isActive: false,
                isCancelled: true 
            });
          } catch (e) {}
      }
  }
});

// --- Governance ---

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


