import { getDefaultConfig } from '@rainbow-me/rainbowkit';
import { foundry } from 'wagmi/chains';
import { 
  metaMaskWallet, 
  okxWallet, 
  rainbowWallet, 
  walletConnectWallet 
} from '@rainbow-me/rainbowkit/wallets';

// 取得環境變數，並強制 Fallback 到你的 Azure IP
const rpcUrl = process.env.NEXT_PUBLIC_RPC_URL;

const azureAnvil = {
  id: 31337,
  name: 'Azure Anvil',
  nativeCurrency: { name: 'Ether', symbol: 'ETH', decimals: 18 },
  rpcUrls: {
    default: { http: [rpcUrl] },
    public: { http: [rpcUrl] },
  },
} as const;

export const config = getDefaultConfig({
  appName: 'Proof of Luck',
  projectId: '3a8170812b534d0ff9d794f19a901d64',
  chains: [azureAnvil], // 確保這裡只放自定義的物件
  wallets: [{
    groupName: 'Recommended',
    wallets: [metaMaskWallet, okxWallet, rainbowWallet, walletConnectWallet],
  }],
  ssr: true,
});