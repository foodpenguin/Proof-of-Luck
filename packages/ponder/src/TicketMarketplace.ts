import { ponder } from "@/generated";
import { Listing, Ticket, User } from "../ponder.schema";

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
  
  // Update Listing
  await db.update(Listing, { id: tokenId.toString() }).set({
    isActive: false,
    isSold: true,
  });

  // Update Ticket Owner
  await db.update(Ticket, { id: tokenId.toString() }).set({
    ownerId: buyer.toLowerCase(),
  });

  // Ensure Buyer exists
  await db.insert(User).values({
    id: buyer.toLowerCase(),
    totalDeposited: 0n,
    totalWinnings: 0n,
    stakedAmount: 0n,
  }).onConflictDoUpdate((row) => ({}));
});
