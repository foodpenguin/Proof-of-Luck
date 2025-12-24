import { getDefaultConfig } from '@rainbow-me/rainbowkit';
import { foundry } from 'wagmi/chains';
import { 
  metaMaskWallet, 
  okxWallet, 
  rainbowWallet, 
  walletConnectWallet 
} from '@rainbow-me/rainbowkit/wallets';

export const config = getDefaultConfig({
  appName: 'Proof of Luck',
  projectId: '3a8170812b534d0ff9d794f19a901d64', // Public testing ID
  chains: [foundry],
  wallets: [{
    groupName: 'Recommended',
    wallets: [
      metaMaskWallet,
      okxWallet,
      rainbowWallet,
      walletConnectWallet
    ],
  }],
  ssr: true,
});
