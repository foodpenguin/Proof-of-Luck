import { onchainTable, relations } from "@ponder/core";

export const User = onchainTable("user", (t) => ({
  id: t.text().primaryKey(), // Wallet Address
  totalDeposited: t.bigint().notNull(),
  totalWinnings: t.bigint().notNull(),
  stakedAmount: t.bigint().notNull(),
}));

export const UserRelations = relations(User, ({ many }) => ({
  tickets: many(Ticket),
}));

export const Ticket = onchainTable("ticket", (t) => ({
  id: t.text().primaryKey(), // Token ID
  ownerId: t.text().notNull(),
  mode: t.integer().notNull(),
  assets: t.bigint().notNull(),
  mintTime: t.bigint().notNull(),
  isDead: t.boolean().notNull(),
  isEliminated: t.boolean().notNull().default(false),
  isWinner: t.boolean().notNull(),
  prize: t.bigint().notNull(),
  multiplier: t.integer().notNull(),
  roundId: t.text(),
}));

export const TicketRelations = relations(Ticket, ({ one }) => ({
  owner: one(User, {
    fields: [Ticket.ownerId],
    references: [User.id],
  }),
  round: one(Round, {
    fields: [Ticket.roundId],
    references: [Round.id],
  }),
}));

export const Pool = onchainTable("pool", (t) => ({
  id: t.text().primaryKey(), // Mode ID (1, 2, 3)
  totalAssets: t.bigint().notNull(),
  activeTicketsCount: t.integer().notNull(),
}));

export const Draw = onchainTable("draw", (t) => ({
  id: t.text().primaryKey(), // Draw ID
  timestamp: t.bigint().notNull(),
  winnerTokenId: t.text(),
  prize: t.bigint().notNull(),
}));

export const DrawRelations = relations(Draw, ({ one }) => ({
  winnerToken: one(Ticket, {
    fields: [Draw.winnerTokenId],
    references: [Ticket.id],
  }),
}));

export const Round = onchainTable("round", (t) => ({
  id: t.text().primaryKey(), // Round ID
  startTime: t.bigint().notNull(),
  endTime: t.bigint(),
  winnerId: t.text(),
  prize: t.bigint().notNull(),
  radius: t.bigint().notNull(),
  x: t.bigint().notNull(),
  y: t.bigint().notNull(),
  status: t.text().notNull(), // Active, Ended
}));

export const RoundRelations = relations(Round, ({ one, many }) => ({
  winner: one(Ticket, {
    fields: [Round.winnerId],
    references: [Ticket.id],
  }),
  tickets: many(Ticket),
}));

export const Treasury = onchainTable("treasury", (t) => ({
  id: t.text().primaryKey(), // "main"
  balance: t.bigint().notNull(),
}));

export const Proposal = onchainTable("proposal", (t) => ({
  id: t.text().primaryKey(), // Proposal ID
  proposer: t.text().notNull(),
  targets: t.text().array().notNull(),
  values: t.bigint().array().notNull(),
  signatures: t.text().array().notNull(),
  calldatas: t.text().array().notNull(),
  startBlock: t.bigint().notNull(),
  endBlock: t.bigint().notNull(),
  description: t.text().notNull(),
  status: t.text().notNull(), // Created, Canceled, Queued, Executed
  forVotes: t.bigint().notNull(),
  againstVotes: t.bigint().notNull(),
  abstainVotes: t.bigint().notNull(),
  eta: t.bigint(), // For Timelock
}));

export const Vote = onchainTable("vote", (t) => ({
  id: t.text().primaryKey(), // proposalId-voter
  proposalId: t.text().notNull(),
  voter: t.text().notNull(),
  support: t.integer().notNull(), // 0=Against, 1=For, 2=Abstain
  weight: t.bigint().notNull(),
  reason: t.text(),
}));

export const VoteRelations = relations(Vote, ({ one }) => ({
  proposal: one(Proposal, {
    fields: [Vote.proposalId],
    references: [Proposal.id],
  }),
  voter: one(User, {
    fields: [Vote.voter],
    references: [User.id],
  }),
}));

export const Listing = onchainTable("listing", (t) => ({
  id: t.text().primaryKey(), // Listing ID
  seller: t.text().notNull(),
  tokenId: t.text().notNull(),
  price: t.bigint().notNull(),
  isActive: t.boolean().notNull(),
  isSold: t.boolean().notNull(),
  isCancelled: t.boolean().notNull(),
}));

export const ListingRelations = relations(Listing, ({ one }) => ({
  ticket: one(Ticket, {
    fields: [Listing.tokenId],
    references: [Ticket.id],
  }),
  seller: one(User, {
    fields: [Listing.seller],
    references: [User.id],
  }),
}));
