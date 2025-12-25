# Migration Summary

## 1. Battle Royale Game Lock Fix
- **File**: `packages/contracts/src/hooks/BattleHook.sol`
- **Change**: Added `resetGame()` function.
- **Purpose**: Allows admin to manually reset game state (`isGameActive`, `currentRadius`, `activeTickets`) if the game gets stuck.

## 2. NFT Metadata Sync Fix
- **File**: `packages/contracts/src/MasterVault.sol`
- **Change**: Added `updateTicketMultiplier(uint256 tokenId, uint16 newMultiplier)` function.
- **File**: `packages/contracts/src/hooks/GeneralHook.sol` & `AlphaHook.sol`
- **Change**: Updated `fulfillRandomWords` to call `masterVault.updateTicketMultiplier` when a ticket's weight changes (e.g., evolution or win).
- **Purpose**: Ensures that the `multiplier` in `MasterVault` (and thus the NFT metadata) always reflects the current state in the Hook.

## 3. Pending Draw Fix (Frontend)
- **File**: `packages/web/src/app/lotto/page.tsx`
- **Change**: Removed the `useEffect` that automatically triggered `performDraw`.
- **Purpose**: Prevents the frontend from getting stuck in a loop trying to trigger a draw. Users/Admins should use the `AdminControls` panel instead.

## 4. Blind Map Fix (Frontend)
- **File**: `packages/web/src/components/BattleMap.tsx`
- **Change**: Updated component to accept `radius`, `centerX`, and `centerY` props instead of using hardcoded constants.
- **File**: `packages/web/src/app/lotto/page.tsx`
- **Change**: Added `useReadContract` hooks to fetch `currentCenterX` and `currentCenterY` from `BattleHook` and passed them to `<BattleMap />`.
- **Purpose**: Ensures the Battle Map correctly displays the current safe zone location and size.

## 5. Zombie Orders Fix (Indexer)
- **File**: `packages/ponder/src/index.ts`
- **Change**: Updated `MasterVault:RedeemClaim` handler to set `isActive = false` and `isCancelled = true` for any corresponding `Listing`.
- **Purpose**: Automatically removes listings from the marketplace when the underlying ticket is redeemed or burned, preventing "zombie" orders.
