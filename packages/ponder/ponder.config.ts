import { createConfig } from "@ponder/core";
import { http } from "viem";
import { MasterVaultABI } from "./abis/MasterVault";
import { POLStakingABI } from "./abis/POLStaking";
import { ERC20ABI } from "./abis/ERC20";
import { POLGovernorABI } from "./abis/POLGovernor";
import { POLTimelockABI } from "./abis/POLTimelock";
import { TicketMarketplaceABI } from "./abis/TicketMarketplace";
import { AlphaHookABI } from "./abis/AlphaHook";
import { BattleHookABI } from "./abis/BattleHook";
import { GeneralHookABI } from "./abis/GeneralHook";

export default createConfig({
  networks: {
    foundry: {
      chainId: 31337,
      transport: http(process.env.PONDER_RPC_URL_31337),
    },
  },
  contracts: {
    MasterVault: {
      network: "foundry",
      abi: MasterVaultABI,
      address: process.env.PONDER_MASTER_VAULT_ADDRESS as `0x${string}`,
      startBlock: Number(process.env.PONDER_START_BLOCK) || 0,
    },
    POLStaking: {
      network: "foundry",
      abi: POLStakingABI,
      address: process.env.PONDER_POL_STAKING_ADDRESS as `0x${string}`,
      startBlock: Number(process.env.PONDER_START_BLOCK) || 0,
    },
    POLToken: {
      network: "foundry",
      abi: ERC20ABI,
      address: process.env.PONDER_POL_TOKEN_ADDRESS as `0x${string}`,
      startBlock: Number(process.env.PONDER_START_BLOCK) || 0,
    },
    POLGovernor: {
      network: "foundry",
      abi: POLGovernorABI,
      address: process.env.PONDER_POL_GOVERNOR_ADDRESS as `0x${string}`,
      startBlock: Number(process.env.PONDER_START_BLOCK) || 0,
    },
    POLTimelock: {
      network: "foundry",
      abi: POLTimelockABI,
      address: process.env.PONDER_POL_TIMELOCK_ADDRESS as `0x${string}`,
      startBlock: Number(process.env.PONDER_START_BLOCK) || 0,
    },
    TicketMarketplace: {
      network: "foundry",
      abi: TicketMarketplaceABI,
      address: process.env.PONDER_TICKET_MARKETPLACE_ADDRESS as `0x${string}`,
      startBlock: Number(process.env.PONDER_START_BLOCK) || 0,
    },
    AlphaHook: {
      network: "foundry",
      abi: AlphaHookABI,
      address: process.env.PONDER_ALPHA_HOOK_ADDRESS as `0x${string}`,
      startBlock: Number(process.env.PONDER_START_BLOCK) || 0,
    },
    BattleHook: {
      network: "foundry",
      abi: BattleHookABI,
      address: process.env.PONDER_BATTLE_HOOK_ADDRESS as `0x${string}`,
      startBlock: Number(process.env.PONDER_START_BLOCK) || 0,
    },
    GeneralHook: {
      network: "foundry",
      abi: GeneralHookABI,
      address: process.env.PONDER_GENERAL_HOOK_ADDRESS as `0x${string}`,
      startBlock: Number(process.env.PONDER_START_BLOCK) || 0,
    },
  },
});
