'use client';

import styled from 'styled-components';
import { BattleMap } from '../../components/BattleMap';
import { useAccount, useWriteContract, useWaitForTransactionReceipt, useReadContract, useReadContracts, useBalance } from 'wagmi';
import { parseAbi, encodeAbiParameters, parseUnits, formatUnits, erc20Abi, maxUint256, createWalletClient, http, publicActions } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { foundry } from 'viem/chains';
import { CONTRACTS } from '../../utils/contracts';
import { POPULAR_TOKENS } from '../../utils/tokenList';
import { useState, useEffect, useMemo, useRef } from 'react';
import { usePonderQuery } from '../../hooks/usePonder';
import { gql } from '../../utils/ponder';

// --- ABIs ---

const ALPHA_HOOK_ABI = parseAbi([
  'function lastDrawTimestamp() view returns (uint256)',
  'function drawInterval() view returns (uint256)',
  'function performDraw() external',
  'function isDrawPending() view returns (bool)'
]);

const VRF_COORDINATOR_MOCK_ADDRESS = '0x498c67a44f26a8a217f5ee8e01a6c005411f1688';
const VRF_COORDINATOR_MOCK_ABI = parseAbi([
    'function nextRequestId() view returns (uint256)',
    'function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) external',
    'function requestNumWords(uint256 requestId) view returns (uint256)'
]);

// Battle Hook ABI 更新：加入 getRoundState
const BATTLE_ABI = parseAbi([
    'function currentRoundId() view returns (uint256)',
    'function getRoundState(uint256 roundId) view returns (uint8)', // 0=Inactive, 1=Joining, 2=Battling
    'function getCurrentRadius() view returns (uint256)',
    'function currentCenterX() view returns (uint256)',
    'function currentCenterY() view returns (uint256)',
    'function startNewRound() external',
    'function performShrink() external', 
    'function isGameActive() view returns (bool)',
    'function checkUpkeep(bytes calldata) view returns (bool upkeepNeeded, bytes memory)',
    'function performUpkeep(bytes calldata) external'
]);

// --- Styles ---

const Container = styled.div`
  padding: 2rem;
  min-height: 100vh;
  background-color: ${({ theme }) => theme.colors.background};
`;

const Header = styled.div`
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 3rem;
`;

const Title = styled.h1`
  font-size: 3rem;
  color: ${({ theme }) => theme.colors.primary};
  text-shadow: 3px 3px 0px ${({ theme }) => theme.colors.black};
`;

const PoolsContainer = styled.div`
  display: flex;
  flex-direction: column;
  gap: 3rem;
`;

const PoolSection = styled.div`
  display: flex;
  gap: 2rem;
  align-items: flex-start;
  
  @media (max-width: ${({ theme }) => theme.breakpoints.tablet}) {
    flex-direction: column;
  }
`;

const PoolCard = styled.div`
  flex: 1;
  background-color: ${({ theme }) => theme.colors.white};
  border: 3px solid ${({ theme }) => theme.colors.black};
  padding: 2rem;
  box-shadow: ${({ theme }) => theme.shadows.card};
  position: relative;
  overflow: hidden;
`;

const PoolHeader = styled.div`
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  margin-bottom: 1.5rem;
  border-bottom: 2px solid ${({ theme }) => theme.colors.black};
  padding-bottom: 1rem;
`;

const PoolName = styled.h2`
  font-size: 2rem;
  text-transform: uppercase;
  color: ${({ theme }) => theme.colors.black};
`;

const PoolTag = styled.span`
  background-color: ${({ theme }) => theme.colors.secondary};
  padding: 0.5rem 1rem;
  font-family: ${({ theme }) => theme.fonts.mono};
  font-weight: bold;
  border: 1px solid ${({ theme }) => theme.colors.black};
  box-shadow: 2px 2px 0px 0px ${({ theme }) => theme.colors.black};
`;

const StatsGrid = styled.div`
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 1.5rem;
  margin-bottom: 2rem;
`;

const StatBox = styled.div`
  display: flex;
  flex-direction: column;
`;

const StatLabel = styled.span`
  font-family: ${({ theme }) => theme.fonts.mono};
  font-size: 0.8rem;
  color: #666;
  margin-bottom: 0.2rem;
`;

const StatValue = styled.span`
  font-size: 1.5rem;
  font-weight: 900;
  color: ${({ theme }) => theme.colors.primary};
`;

const ActionArea = styled.div`
  margin-top: 1rem;
`;

const JoinButton = styled.button`
  width: 100%;
  padding: 1.2rem;
  font-weight: 900;
  font-size: 1.2rem;
  text-transform: uppercase;
  background-color: ${({ theme }) => theme.colors.secondary};
  border: none;
  cursor: pointer;
  transition: transform 0.1s;
  
  &:hover {
    background-color: ${({ theme }) => theme.colors.primary};
    color: ${({ theme }) => theme.colors.white};
    transform: translateY(-2px);
  }
  
  &:disabled {
    background-color: #ccc;
    cursor: not-allowed;
    transform: none;
  }
`;

const ModalOverlay = styled.div`
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  background-color: rgba(0, 0, 0, 0.8);
  display: flex;
  justify-content: center;
  align-items: center;
  z-index: 1000;
`;

const ModalContent = styled.div`
  background-color: ${({ theme }) => theme.colors.white};
  border: 4px solid ${({ theme }) => theme.colors.black};
  padding: 2rem;
  max-width: 600px;
  width: 90%;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 1rem;
  box-shadow: 10px 10px 0px 0px ${({ theme }) => theme.colors.secondary};
`;

const CloseButton = styled.button`
  background: none;
  border: none;
  font-size: 2rem;
  cursor: pointer;
  color: ${({ theme }) => theme.colors.black};
  &:hover {
    color: ${({ theme }) => theme.colors.primary};
  }
`;

const AmountInput = styled.input`
  width: 100%;
  padding: 1rem;
  margin-bottom: 1rem;
  font-size: 1.2rem;
  font-family: ${({ theme }) => theme.fonts.mono};
  border: 2px solid ${({ theme }) => theme.colors.black};
  background-color: #f0f0f0;
  
  &:focus {
    outline: none;
    border-color: ${({ theme }) => theme.colors.primary};
  }
`;

const HistorySection = styled.div`
  margin-top: 4rem;
  padding: 2rem;
  background-color: ${({ theme }) => theme.colors.white};
  border: 3px solid ${({ theme }) => theme.colors.black};
  box-shadow: ${({ theme }) => theme.shadows.card};
`;

const HistoryTable = styled.table`
  width: 100%;
  border-collapse: collapse;
  margin-top: 1rem;
`;

const Th = styled.th`
  background-color: ${({ theme }) => theme.colors.black};
  color: ${({ theme }) => theme.colors.white};
  padding: 1rem;
  text-align: left;
  font-family: ${({ theme }) => theme.fonts.mono};
  text-transform: uppercase;
`;

const Td = styled.td`
  padding: 1rem;
  border-bottom: 1px solid #eee;
  font-family: ${({ theme }) => theme.fonts.mono};
  vertical-align: middle;
`;

const Tr = styled.tr`
  &:hover {
    background-color: #f5f5f5;
  }
`;

const StatusBadge = styled.span<{ $status: 'active' | 'winner' | 'redeemed' | 'dead' }>`
  padding: 0.3rem 0.6rem;
  font-weight: bold;
  font-size: 0.8rem;
  text-transform: uppercase;
  border: 2px solid ${({ theme }) => theme.colors.black};
  background-color: ${({ $status, theme }) => {
    switch ($status) {
      case 'active': return '#fff';
      case 'winner': return theme.colors.secondary;
      case 'redeemed': return '#ddd';
      case 'dead': return '#ffcccc';
      default: return '#fff';
    }
  }};
  color: ${({ theme }) => theme.colors.black};
`;

const RedeemButton = styled.button`
  padding: 0.5rem 1rem;
  background-color: ${({ theme }) => theme.colors.secondary};
  border: 2px solid ${({ theme }) => theme.colors.black};
  font-family: ${({ theme }) => theme.fonts.mono};
  font-weight: bold;
  cursor: pointer;
  
  &:hover {
    background-color: ${({ theme }) => theme.colors.primary};
    color: white;
  }
  
  &:disabled {
    background-color: #ccc;
    cursor: not-allowed;
  }
`;

const ZapContainer = styled.div`
  margin-bottom: 1rem;
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
  padding: 0.5rem;
  background-color: #eee;
  border: 1px dashed #999;
`;

const CheckboxLabel = styled.label`
  display: flex;
  align-items: center;
  gap: 0.5rem;
  font-family: ${({ theme }) => theme.fonts.mono};
  font-size: 0.9rem;
  cursor: pointer;
`;

const TokenSelect = styled.select`
  width: 100%;
  padding: 1rem;
  margin-bottom: 1rem;
  font-size: 1.2rem;
  font-family: ${({ theme }) => theme.fonts.mono};
  border: 2px solid ${({ theme }) => theme.colors.black};
  background-color: #f0f0f0;
  
  &:focus {
    outline: none;
    border-color: ${({ theme }) => theme.colors.primary};
  }
`;

// --- Admin Bot ---

const ADMIN_KEY = '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80';
const adminAccount = privateKeyToAccount(ADMIN_KEY);
const adminClient = createWalletClient({ 
    account: adminAccount, 
    chain: foundry, 
    transport: http() 
}).extend(publicActions);

const AdminControls = ({ onLog, onRefresh }: { onLog: (msg: string) => void, onRefresh: () => void }) => {
    const [loading, setLoading] = useState(false);

    const log = (msg: string) => {
        console.log(msg);
        onLog(`[${new Date().toLocaleTimeString()}] ${msg}`);
    };

    const advanceTime = async (seconds: number) => {
        setLoading(true);
        try {
            log(`Advancing time by ${seconds}s...`);
            await adminClient.request({ method: 'evm_increaseTime', params: [seconds] });
            await adminClient.request({ method: 'evm_mine' });
            log(`Time advanced.`);
            setTimeout(onRefresh, 1000);
        } catch (e: any) {
            log(`Error: ${e.message}`);
        }
        setLoading(false);
    };

    const triggerContract = async (name: string, address: `0x${string}`, abi: any, func: string, args: any[] = []) => {
        setLoading(true);
        try {
            log(`Triggering ${name}.${func}...`);
            const hash = await adminClient.writeContract({
                address,
                abi,
                functionName: func,
                args
            });
            log(`Tx sent: ${hash}`);
            await adminClient.request({ method: 'evm_mine' }); // Auto mine
            log(`Tx mined.`);
            
            // Check for VRF
            await checkAndFulfillVRF();
            setTimeout(onRefresh, 2000);
        } catch (e: any) {
            log(`Error: ${e.message}`);
        }
        setLoading(false);
    };

    const lastFulfilledRequestId = useRef<bigint>(0n);

    // 修正後的 VRF 履行邏輯：動態檢查需要幾個 Words
    const checkAndFulfillVRF = async () => {
        try {
            const nextId = await adminClient.readContract({
                address: VRF_COORDINATOR_MOCK_ADDRESS as `0x${string}`,
                abi: VRF_COORDINATOR_MOCK_ABI,
                functionName: 'nextRequestId'
            }) as bigint;
            
            // 掃描所有尚未履行的 Request
            for (let id = lastFulfilledRequestId.current + 1n; id < nextId; id++) {
                try {
                    // 1. 檢查這個請求需要幾個隨機數
                    const numWordsBigInt = await adminClient.readContract({
                        address: VRF_COORDINATOR_MOCK_ADDRESS as `0x${string}`,
                        abi: VRF_COORDINATOR_MOCK_ABI,
                        functionName: 'requestNumWords',
                        args: [id]
                    }) as bigint;

                    const numWordsNeeded = Number(numWordsBigInt);
                    log(`Fulfilling VRF Request #${id} (Needs ${numWordsNeeded} words)...`);

                    if (numWordsNeeded === 0) {
                        // 可能是已經履行過或無效的請求，跳過
                        lastFulfilledRequestId.current = id;
                        continue;
                    }

                    // 2. 生成對應長度的隨機數
                    const randomWords = Array.from({ length: numWordsNeeded }, () =>
                        BigInt(Math.floor(Math.random() * 1e18))
                    );

                    try {
                        const hash = await adminClient.writeContract({
                            address: VRF_COORDINATOR_MOCK_ADDRESS as `0x${string}`,
                            abi: VRF_COORDINATOR_MOCK_ABI,
                            functionName: 'fulfillRandomWords',
                            args: [id, randomWords]
                        });
                        log(`VRF Request #${id} Success!`);
                        await adminClient.request({ method: 'evm_mine' }); // 使用 evm_mine
                        lastFulfilledRequestId.current = id;
                    } catch (e: any) {
                        log(`VRF #${id} Failed: ${e.shortMessage || "Reverted"}`);
                        // 即使失敗也標記處理過，避免卡死
                        lastFulfilledRequestId.current = id;
                    }
                } catch (e: any) {
                    log(`VRF #${String(id)} Check Failed: ${e.shortMessage}`);
                    lastFulfilledRequestId.current = id;
                }
            }
        } catch (e: any) {
            // Ignore read errors
        }
    };

    const [autoPlay, setAutoPlay] = useState(false);
    const [lastActionTime, setLastActionTime] = useState(0);

    // Read Battle State for Bot
    const { data: isBattleActive } = useReadContract({
        address: CONTRACTS.BattleHook.address as `0x${string}`,
        abi: BATTLE_ABI,
        functionName: 'isGameActive',
        query: { refetchInterval: 5000 }
    });

    // Bot Logic
    useEffect(() => {
        if (!autoPlay) return;
        const now = Date.now();
        if (now - lastActionTime < 10000) return; // Cooldown 10s

        const runBot = async () => {
            try {
                // 1. Check VRF
                await checkAndFulfillVRF();

                // 2. Battle Logic - Auto Start New Round
                if (isBattleActive === false) {
                    log("Bot: Starting new round...");
                    await triggerContract('Battle', CONTRACTS.BattleHook.address as `0x${string}`, BATTLE_ABI, 'startNewRound');
                    setLastActionTime(Date.now());
                }
                
                // Note: Auto-shrink 邏輯暫時保留手動，避免在演示時跑太快
            } catch (e) {
                console.error(e);
            }
        };
        
        const timer = setInterval(runBot, 5000);
        return () => clearInterval(timer);
    }, [autoPlay, isBattleActive, lastActionTime]);

    const btnStyle = {
        padding: '0.5rem 1rem',
        backgroundColor: '#ddd',
        border: '2px solid #333',
        cursor: 'pointer',
        fontFamily: 'var(--font-mono)',
        fontWeight: 'bold' as const
    };

    return (
        <div style={{ padding: '1rem', border: '2px solid #333', marginBottom: '2rem', backgroundColor: '#f0f0f0' }}>
            <h3 style={{ fontFamily: 'var(--font-mono)', marginTop: 0 }}>ADMIN / TIME CONTROLS (AUTO-SIGNER)</h3>
            <div style={{ marginBottom: '1rem' }}>
                <label style={{ fontFamily: 'var(--font-mono)', fontWeight: 'bold', display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                    <input type="checkbox" checked={autoPlay} onChange={e => setAutoPlay(e.target.checked)} />
                    ENABLE LOTTO BOT (Auto-Start Rounds & Fulfill VRF)
                </label>
            </div>
            <div style={{ display: 'flex', gap: '0.5rem', flexWrap: 'wrap', marginBottom: '1rem' }}>
                <button style={btnStyle} disabled={loading} onClick={() => advanceTime(3600)}>+1 Hour</button>
                <button style={btnStyle} disabled={loading} onClick={() => advanceTime(86400)}>+1 Day</button>
                <button style={btnStyle} disabled={loading} onClick={() => advanceTime(604800)}>+1 Week</button>
            </div>
            <div style={{ display: 'flex', gap: '0.5rem', flexWrap: 'wrap' }}>
                <button style={{...btnStyle, backgroundColor: '#ffcc99'}} disabled={loading} onClick={() => triggerContract('Alpha', CONTRACTS.AlphaHook.address as `0x${string}`, ALPHA_HOOK_ABI, 'performDraw')}>
                    Trigger Alpha Draw
                </button>
                <button style={{...btnStyle, backgroundColor: '#ccffcc'}} disabled={loading} onClick={() => triggerContract('Savings', CONTRACTS.GeneralHook.address as `0x${string}`, ALPHA_HOOK_ABI, 'performDraw')}>
                    Trigger Savings Draw
                </button>
                <button style={{...btnStyle, backgroundColor: '#ffcccc'}} disabled={loading} onClick={() => triggerContract('Battle', CONTRACTS.BattleHook.address as `0x${string}`, BATTLE_ABI, 'startNewRound')}>
                    Start New Round
                </button>
                <button style={{...btnStyle, backgroundColor: '#ccccff'}} disabled={loading} onClick={() => triggerContract('Battle', CONTRACTS.BattleHook.address as `0x${string}`, BATTLE_ABI, 'performShrink')}>
                    Trigger Game Action (Start/Shrink)
                </button>
            </div>
        </div>
    );
};


export default function LottoPage() {
  const { address } = useAccount();

  // --- Auto Draw Logic (Reads) ---
  const { data: lastDrawTimestamp } = useReadContract({
    address: CONTRACTS.AlphaHook.address as `0x${string}`,
    abi: ALPHA_HOOK_ABI,
    functionName: 'lastDrawTimestamp',
    query: { refetchInterval: 10000 }
  });

  // --- State ---
  const [selectedCoords, setSelectedCoords] = useState<{x: number, y: number} | null>(null);
  const [showMapModal, setShowMapModal] = useState(false);
  const [savingsAmount, setSavingsAmount] = useState('100');
  const [alphaAmount, setAlphaAmount] = useState('100');
  const [isZap, setIsZap] = useState(false);
  const [zapToken, setZapToken] = useState(POPULAR_TOKENS[1].address); // Default to WETH
  const [customTokenAddress, setCustomTokenAddress] = useState('');
  const [zapAmount, setZapAmount] = useState('0');
  const [adminLog, setAdminLog] = useState<string[]>([]);

  // --- Token Scanning ---
  const tokensToScan = useMemo(() => {
    const list = [...POPULAR_TOKENS];
    if (customTokenAddress && customTokenAddress.startsWith('0x') && customTokenAddress.length === 42) {
        if (!list.find(t => t.address.toLowerCase() === customTokenAddress.toLowerCase())) {
            list.push({ symbol: 'CUSTOM', address: customTokenAddress, decimals: 18, name: 'Custom Token' });
        }
    }
    return list;
  }, [customTokenAddress]);

  const { data: erc20Balances, isLoading: isScanningERC20, refetch: refetchERC20 } = useReadContracts({
    contracts: tokensToScan.filter(t => t.symbol !== 'ETH').map(t => ({
        address: t.address as `0x${string}`,
        abi: erc20Abi,
        functionName: 'balanceOf',
        args: [address as `0x${string}`],
    })),
    query: {
        enabled: !!address && isZap,
        refetchInterval: 10000,
    }
  });

  const { data: ethBalance, isLoading: isScanningETH, refetch: refetchETH } = useBalance({
    address: address as `0x${string}`,
    query: {
        enabled: !!address && isZap,
        refetchInterval: 10000,
    }
  });

  const availableTokens = useMemo(() => {
    if (!address) return [];
    const result = [];
    if (ethBalance && ethBalance.value > BigInt(0)) {
        result.push({
            symbol: 'ETH',
            address: '0x0000000000000000000000000000000000000000',
            decimals: 18,
            name: 'Ether',
            balance: ethBalance.value
        });
    }
    if (erc20Balances) {
        const erc20Tokens = tokensToScan.filter(t => t.symbol !== 'ETH');
        erc20Tokens.forEach((t, i) => {
            const bal = erc20Balances[i].result ? (erc20Balances[i].result as bigint) : BigInt(0);
            if (bal > BigInt(0)) {
                result.push({ ...t, balance: bal });
            }
        });
    }
    return result;
  }, [erc20Balances, ethBalance, tokensToScan, address]);

  const isScanning = isScanningERC20 || isScanningETH;

  // --- Quoter ---
  const { data: quoteResult, isLoading: isQuoting } = useReadContract({
    address: CONTRACTS.QuoterV2.address as `0x${string}`,
    abi: parseAbi([
        'struct QuoteExactInputSingleParams { address tokenIn; address tokenOut; uint256 amountIn; uint24 fee; uint160 sqrtPriceLimitX96; }',
        'function quoteExactInputSingle(QuoteExactInputSingleParams params) external returns (uint256 amountOut, uint160 sqrtPriceX96After, uint32 initializedTicksCrossed, uint256 gasEstimate)'
    ]),
    functionName: 'quoteExactInputSingle',
    args: [{
        tokenIn: (zapToken === '0x0000000000000000000000000000000000000000' ? POPULAR_TOKENS.find(t => t.symbol === 'WETH')?.address : zapToken) as `0x${string}`,
        tokenOut: CONTRACTS.USDC.address as `0x${string}`,
        amountIn: parseUnits(zapAmount || '0', tokensToScan.find(t => t.address === zapToken)?.decimals || 18),
        fee: (zapToken === '0x0000000000000000000000000000000000000000' || zapToken.toLowerCase() === '0x4200000000000000000000000000000000000006') ? 500 : 3000,
        sqrtPriceLimitX96: BigInt(0)
    }],
    query: {
        enabled: !!zapToken && !!zapAmount && isZap && zapAmount !== '0',
    }
  });

  const estimatedUSDC = quoteResult ? (quoteResult as any)[0] : BigInt(0);

  // --- Transactions ---
  const { writeContract, data: hash, isPending } = useWriteContract();
  const { isLoading: isConfirming, isSuccess: isConfirmed } = useWaitForTransactionReceipt({ hash });

  // Allowances
  const { data: allowance, refetch: refetchAllowance } = useReadContract({
    address: CONTRACTS.USDC.address as `0x${string}`,
    abi: erc20Abi,
    functionName: 'allowance',
    args: [address as `0x${string}`, CONTRACTS.MasterVault.address as `0x${string}`],
    query: { enabled: !!address }
  });

  const { data: zapAllowance, refetch: refetchZapAllowance } = useReadContract({
    address: zapToken as `0x${string}`,
    abi: erc20Abi,
    functionName: 'allowance',
    args: [address as `0x${string}`, CONTRACTS.ZapRouter.address as `0x${string}`],
    query: { enabled: !!address && !!zapToken && isZap && zapToken !== '0x0000000000000000000000000000000000000000' }
  });

  // --- Battle State Reads ---
  const { data: currentRoundId, refetch: refetchRoundId } = useReadContract({
    address: CONTRACTS.BattleHook.address as `0x${string}`,
    abi: BATTLE_ABI,
    functionName: 'currentRoundId',
  });

  const { data: battleRadius, refetch: refetchBattleRadius } = useReadContract({
    address: CONTRACTS.BattleHook.address as `0x${string}`,
    abi: BATTLE_ABI,
    functionName: 'getCurrentRadius',
  });

  const { data: battleCenterX, refetch: refetchBattleCenterX } = useReadContract({
    address: CONTRACTS.BattleHook.address as `0x${string}`,
    abi: BATTLE_ABI,
    functionName: 'currentCenterX',
  });

  const { data: battleCenterY, refetch: refetchBattleCenterY } = useReadContract({
    address: CONTRACTS.BattleHook.address as `0x${string}`,
    abi: BATTLE_ABI,
    functionName: 'currentCenterY',
  });

  const { data: isGameActive, refetch: refetchGameStatus } = useReadContract({
    address: CONTRACTS.BattleHook.address as `0x${string}`,
    abi: BATTLE_ABI,
    functionName: 'isGameActive',
  });

  // --- Ponder Data ---
  const { data: ponderData, refetch: refetchPonder, error: ponderError } = usePonderQuery<{ 
    pools: { items: { id: string, totalAssets: string, activeTicketsCount: number }[] },
    user: { tickets: { items: { id: string, mode: number, assets: string, isWinner: boolean, isDead: boolean, mintTime: string, multiplier: string }[] } },
    draws: { items: { id: string, winnerTokenId: string, prize: string, timestamp: string, winnerToken: { owner: { id: string } } }[] },
    rounds: { items: { id: string, status: string, winnerId: string, winner: { owner: { id: string } } }[] }
  }>(
    ['lotto-data', address || ''],
    gql`
      query GetLottoData($user: String!) {
        pools {
          items { id totalAssets activeTicketsCount }
        }
        user(id: $user) {
          tickets(orderBy: "mintTime", orderDirection: "desc", limit: 50) {
            items { id mode assets isWinner isDead mintTime multiplier }
          }
        }
        draws(orderBy: "timestamp", orderDirection: "desc", limit: 5) {
          items { id winnerTokenId prize timestamp winnerToken { owner { id } } }
        }
        rounds(orderBy: "id", orderDirection: "desc", limit: 1) {
          items {
            id
            status
            winnerId
            winner { owner { id } }
          }
        }
      }
    `,
    { user: address ? address.toLowerCase() : '' }
  );

  const refreshAll = () => {
      refetchPonder();
      refetchBattleRadius();
      refetchGameStatus();
      refetchBattleCenterX();
      refetchBattleCenterY();
      refetchRoundId();
      refetchERC20();
      refetchETH();
  };

  useEffect(() => {
      if (isConfirmed) {
          refetchAllowance();
          refetchZapAllowance();
          // Delay Ponder refetch
          setTimeout(refreshAll, 5000);
      }
  }, [isConfirmed]);

  const getPoolStats = (mode: string) => {
    const pool = ponderData?.pools.items.find(p => p.id === mode);
    return {
      tvl: pool ? `$${Number(formatUnits(BigInt(pool.totalAssets), 6)).toLocaleString()}` : '$0',
      players: pool ? pool.activeTicketsCount : 0
    };
  };

  const savingsStats = getPoolStats('3');
  const alphaStats = getPoolStats('1');
  const battleStats = getPoolStats('2');
  
  // Battle Pool specific info
  const latestRound = ponderData?.rounds?.items[0];

  const handleApprove = () => {
    writeContract({
        address: CONTRACTS.USDC.address as `0x${string}`,
        abi: erc20Abi,
        functionName: 'approve',
        args: [CONTRACTS.MasterVault.address as `0x${string}`, maxUint256],
    });
  };

  const handleApproveZap = () => {
    if (!zapToken) return;
    const target = zapToken === '0x0000000000000000000000000000000000000000' 
        ? '0x4200000000000000000000000000000000000006' // WETH
        : zapToken;
        
    writeContract({
        address: target as `0x${string}`,
        abi: erc20Abi,
        functionName: 'approve',
        args: [CONTRACTS.ZapRouter.address as `0x${string}`, maxUint256],
    });
  };

  const handleDeposit = async (mode: number, amount: string, data: `0x${string}` = '0x') => {
    if (!address) return;
    
    if (mode === 2) {
        if (!selectedCoords) {
            setShowMapModal(true);
            return;
        }
        data = encodeAbiParameters(
            [{ type: 'uint256' }, { type: 'uint256' }],
            [BigInt(selectedCoords.x), BigInt(selectedCoords.y)]
        );
    } else {
        data = encodeAbiParameters(
            [{ type: 'uint256' }, { type: 'uint256' }],
            [BigInt(0), BigInt(0)]
        );
    }

    if (isZap) {
        if (!zapToken) {
            alert('Please select a token to zap');
            return;
        }
        const selectedToken = tokensToScan.find(t => t.address === zapToken);
        const decimals = selectedToken ? selectedToken.decimals : 18;
        const amountIn = parseUnits(amount, decimals);
        const minUSDC = estimatedUSDC ? (estimatedUSDC * BigInt(90)) / BigInt(100) : BigInt(0);
        let poolFee = 3000;
        const isETH = zapToken === '0x0000000000000000000000000000000000000000';
        const wethAddress = '0x4200000000000000000000000000000000000006';
        
        if (isETH || zapToken.toLowerCase() === wethAddress.toLowerCase()) poolFee = 500;

        if (isETH) {
            writeContract({
                address: CONTRACTS.ZapRouter.address as `0x${string}`,
                abi: parseAbi([
                    'function zapInETH(uint256 minUSDC, uint8 mode, bytes calldata data, address receiver, uint24 poolFee) external payable returns (uint256 tokenId)'
                ]),
                functionName: 'zapInETH',
                args: [minUSDC, mode, data, address, poolFee],
                value: amountIn
            });
        } else {
            if (!zapAllowance || zapAllowance < amountIn) {
                handleApproveZap();
                return;
            }
            writeContract({
                address: CONTRACTS.ZapRouter.address as `0x${string}`,
                abi: parseAbi([
                    'function zapIn(address tokenIn, uint256 amountIn, uint256 minUSDC, uint8 mode, bytes calldata data, address receiver, uint24 poolFee) external payable returns (uint256 tokenId)'
                ]),
                functionName: 'zapIn',
                args: [zapToken as `0x${string}`, amountIn, minUSDC, mode, data, address, poolFee],
            });
        }
    } else {
        const amountBigInt = parseUnits(amount, 6);
        if (!allowance || allowance < amountBigInt) {
            handleApprove();
            return;
        }
        writeContract({
          address: CONTRACTS.MasterVault.address as `0x${string}`,
          abi: parseAbi([
            'function deposit(uint256 assets, address receiver, uint8 mode, bytes calldata data) external returns (uint256 tokenId)'
          ]),
          functionName: 'deposit',
          args: [amountBigInt, address, mode, data],
        });
    }
    
    if (mode === 2) setShowMapModal(false);
  };

  const handleRedeem = (tokenId: string) => {
      writeContract({
          address: CONTRACTS.MasterVault.address as `0x${string}`,
          abi: parseAbi(['function claimRedeem(uint256 tokenId) external returns (uint256 assets)']),
          functionName: 'claimRedeem',
          args: [BigInt(tokenId)],
      });
  };

  const isApproved = (amount: string) => {
      if (!allowance) return false;
      return allowance >= parseUnits(amount || '0', 6);
  };

  // 在元件內部定義輔助函數或變數
  const roundState = ponderData?.rounds?.items[0]?.status; // Ponder 記錄的狀態
  // 或者使用鏈上讀取的狀態 (更即時)
  const { data: onChainState } = useReadContract({
      address: CONTRACTS.BattleHook.address as `0x${string}`,
      abi: BATTLE_ABI,
      functionName: 'getRoundState',
      args: [currentRoundId || 0n],
      query: { refetchInterval: 2000 }
  });

  // 定義狀態文字對照
  const stateText = {
      0: 'Inactive (回合結束)',
      1: 'Joining (報名中)',
      2: 'Battling (對戰中)'
  }[Number(onChainState)];

  return (
    <Container>
      <AdminControls 
        onLog={(msg) => setAdminLog(prev => [msg, ...prev].slice(0, 5))} 
        onRefresh={refreshAll}
      />
      {adminLog.length > 0 && (
        <div style={{ 
            marginBottom: '1rem', 
            padding: '0.5rem', 
            backgroundColor: '#333', 
            color: '#0f0', 
            fontFamily: 'monospace', 
            fontSize: '0.8rem',
            maxHeight: '100px',
            overflowY: 'auto'
        }}>
            {adminLog.map((l, i) => <div key={i}>{l}</div>)}
        </div>
      )}

      <Header>
        <Title>LOTTO POOLS</Title>
        <div style={{display: 'flex', gap: '1rem', alignItems: 'center'}}>
            {ponderError && (
                <div style={{color: 'red', fontWeight: 'bold', border: '2px solid red', padding: '0.5rem'}}>
                    DATA ERROR: Check Console
                </div>
            )}
        </div>
      </Header>

      {ponderData?.draws?.items && ponderData.draws.items.length > 0 && (
        <HistorySection style={{marginTop: '0', marginBottom: '3rem'}}>
            <h2 style={{fontFamily: 'var(--font-mono)', marginBottom: '1rem'}}>RECENT WINNERS (Alpha/Savings)</h2>
            <div style={{overflowX: 'auto'}}>
                <HistoryTable>
                    <thead>
                        <tr>
                            <Th>Draw Time</Th>
                            <Th>Winner</Th>
                            <Th>Prize (Assets)</Th>
                            <Th>Ticket ID</Th>
                        </tr>
                    </thead>
                    <tbody>
                        {ponderData.draws.items.map(draw => (
                            <Tr key={draw.id}>
                                <Td>{new Date(Number(draw.timestamp) * 1000).toLocaleString()}</Td>
                                <Td>{draw.winnerToken?.owner?.id ? `${draw.winnerToken.owner.id.slice(0, 6)}...${draw.winnerToken.owner.id.slice(-4)}` : 'Unknown'}</Td>
                                <Td>{formatUnits(BigInt(draw.prize), 6)} USDC</Td>
                                <Td>#{draw.winnerTokenId}</Td>
                            </Tr>
                        ))}
                    </tbody>
                </HistoryTable>
            </div>
        </HistorySection>
      )}
      
      <PoolsContainer>
        {/* Savings Pool (Mode 3) */}
        <PoolSection>
          <PoolCard>
            <PoolHeader>
              <PoolName>Savings Pool</PoolName>
              <PoolTag>NO LOSS</PoolTag>
            </PoolHeader>
            <StatsGrid>
              <StatBox>
                <StatLabel>TVL</StatLabel>
                <StatValue>{savingsStats.tvl}</StatValue>
              </StatBox>
              <StatBox>
                <StatLabel>PLAYERS</StatLabel>
                <StatValue>{savingsStats.players}</StatValue>
              </StatBox>
              <StatBox>
                <StatLabel>RISK</StatLabel>
                <StatValue>NONE</StatValue>
              </StatBox>
              <StatBox>
                <StatLabel>NEXT DRAW</StatLabel>
                <StatValue>Daily</StatValue>
              </StatBox>
            </StatsGrid>
            <ActionArea>
              <ZapContainer>
                <CheckboxLabel>
                    <input type="checkbox" checked={isZap} onChange={e => setIsZap(e.target.checked)} />
                    Zap Mode (Swap any token)
                </CheckboxLabel>
                {isZap && (
                    <>
                        {isScanning && <div style={{fontSize: '0.8rem', color: '#666'}}>Scanning wallet...</div>}
                        <TokenSelect 
                            value={zapToken} 
                            onChange={e => {
                                if (e.target.value === 'custom') {
                                    setZapToken('');
                                    setCustomTokenAddress('');
                                } else {
                                    setZapToken(e.target.value);
                                }
                            }}
                        >
                            {availableTokens.map(token => (
                                <option key={token.address} value={token.address}>
                                    {token.symbol} (Bal: {Number(formatUnits(token.balance, token.decimals)).toFixed(4)})
                                </option>
                            ))}
                            <option value="custom">Import Custom Token...</option>
                        </TokenSelect>
                        
                        {(!zapToken || zapToken === '') && (
                            <AmountInput 
                                placeholder="0x... (Token Address)"
                                value={customTokenAddress}
                                onChange={e => {
                                    setCustomTokenAddress(e.target.value);
                                    if (e.target.value.length === 42) setZapToken(e.target.value);
                                }}
                                style={{fontSize: '0.9rem', marginBottom: '0.5rem'}}
                            />
                        )}

                        <div style={{fontSize: '0.8rem', marginBottom: '0.5rem', fontFamily: 'var(--font-mono)'}}>
                            Estimated Output: {isQuoting ? 'Calculating...' : `${formatUnits(estimatedUSDC, 6)} USDC`}
                        </div>
                    </>
                )}
              </ZapContainer>
              <AmountInput 
                type="number" 
                value={isZap ? zapAmount : savingsAmount} 
                onChange={e => {
                    if (isZap) setZapAmount(e.target.value);
                    else setSavingsAmount(e.target.value);
                }} 
                placeholder={isZap ? `Amount (${tokensToScan.find(t => t.address === zapToken)?.symbol || 'Token'})` : "Amount (USDC)"}
              />
              <JoinButton 
                onClick={() => handleDeposit(3, isZap ? zapAmount : savingsAmount)}
                disabled={isPending || isConfirming}
              >
                {isPending ? 'CONFIRMING...' : 
                 isZap ? 
                    (zapToken !== '0x0000000000000000000000000000000000000000' && (!zapAllowance || zapAllowance < parseUnits(zapAmount, tokensToScan.find(t => t.address === zapToken)?.decimals || 18)) ? 'APPROVE ZAP' : 'ZAP DEPOSIT') :
                    (!isApproved(savingsAmount) ? 'APPROVE USDC' : 'DEPOSIT')}
              </JoinButton>
            </ActionArea>
          </PoolCard>
        </PoolSection>

        {/* Alpha Pool (Mode 1) */}
        <PoolSection>
          <PoolCard>
            <PoolHeader>
              <PoolName>Alpha Pool</PoolName>
              <PoolTag>HIGH YIELD</PoolTag>
            </PoolHeader>
            <StatsGrid>
              <StatBox>
                <StatLabel>TVL</StatLabel>
                <StatValue>{alphaStats.tvl}</StatValue>
              </StatBox>
              <StatBox>
                <StatLabel>PLAYERS</StatLabel>
                <StatValue>{alphaStats.players}</StatValue>
              </StatBox>
              <StatBox>
                <StatLabel>RISK</StatLabel>
                <StatValue>MEDIUM</StatValue>
              </StatBox>
              <StatBox>
                <StatLabel>NEXT DRAW</StatLabel>
                <StatValue>Weekly</StatValue>
              </StatBox>
            </StatsGrid>
            <ActionArea>
              <ZapContainer>
                <CheckboxLabel>
                    <input type="checkbox" checked={isZap} onChange={e => setIsZap(e.target.checked)} />
                    Zap Mode (Swap any token)
                </CheckboxLabel>
                {isZap && (
                    <>
                        {isScanning && <div style={{fontSize: '0.8rem', color: '#666'}}>Scanning wallet...</div>}
                        <TokenSelect 
                            value={zapToken} 
                            onChange={e => {
                                if (e.target.value === 'custom') {
                                    setZapToken('');
                                    setCustomTokenAddress('');
                                } else {
                                    setZapToken(e.target.value);
                                }
                            }}
                        >
                            {availableTokens.map(token => (
                                <option key={token.address} value={token.address}>
                                    {token.symbol} (Bal: {Number(formatUnits(token.balance, token.decimals)).toFixed(4)})
                                </option>
                            ))}
                            <option value="custom">Import Custom Token...</option>
                        </TokenSelect>
                        
                        {(!zapToken || zapToken === '') && (
                            <AmountInput 
                                placeholder="0x... (Token Address)"
                                value={customTokenAddress}
                                onChange={e => {
                                    setCustomTokenAddress(e.target.value);
                                    if (e.target.value.length === 42) setZapToken(e.target.value);
                                }}
                                style={{fontSize: '0.9rem', marginBottom: '0.5rem'}}
                            />
                        )}

                        <div style={{fontSize: '0.8rem', marginBottom: '0.5rem', fontFamily: 'var(--font-mono)'}}>
                            Estimated Output: {isQuoting ? 'Calculating...' : `${formatUnits(estimatedUSDC, 6)} USDC`}
                        </div>
                    </>
                )}
              </ZapContainer>
              <AmountInput 
                type="number" 
                value={isZap ? zapAmount : alphaAmount} 
                onChange={e => {
                    if (isZap) setZapAmount(e.target.value);
                    else setAlphaAmount(e.target.value);
                }} 
                placeholder={isZap ? `Amount (${tokensToScan.find(t => t.address === zapToken)?.symbol || 'Token'})` : "Amount (USDC)"}
              />
              <JoinButton 
                onClick={() => handleDeposit(1, isZap ? zapAmount : alphaAmount)}
                disabled={isPending || isConfirming}
              >
                {isPending ? 'CONFIRMING...' : 
                 isZap ? 
                    (zapToken !== '0x0000000000000000000000000000000000000000' && (!zapAllowance || zapAllowance < parseUnits(zapAmount, tokensToScan.find(t => t.address === zapToken)?.decimals || 18)) ? 'APPROVE ZAP' : 'ZAP DEPOSIT') :
                    (!isApproved(alphaAmount) ? 'APPROVE USDC' : 'DEPOSIT')}
              </JoinButton>
            </ActionArea>
          </PoolCard>
        </PoolSection>

        {/* Battle Pool (Mode 2) */}
        <PoolSection>
          <PoolCard>
            <PoolHeader>
              <PoolName>Battle Pool</PoolName>
              <div style={{display: 'flex', flexDirection: 'column', alignItems: 'flex-end'}}>
                  <PoolTag>BATTLE ROYALE</PoolTag>
                  <span style={{fontFamily: 'var(--font-mono)', fontSize: '0.8rem', marginTop: '0.5rem'}}>
                      ROUND #{currentRoundId ? currentRoundId.toString() : '0'}
                  </span>
                  {/* 顯示詳細狀態 */}
                  <span style={{fontSize: '0.9rem', color: '#e91e63', fontWeight: 'bold', marginTop: '0.2rem'}}>
                    STATUS: {stateText || 'Loading...'}
                  </span>
              </div>
            </PoolHeader>
            <StatsGrid>
              <StatBox>
                <StatLabel>TVL</StatLabel>
                <StatValue>{battleStats.tvl}</StatValue>
              </StatBox>
              <StatBox>
                <StatLabel>ALIVE</StatLabel>
                <StatValue>{battleStats.players}</StatValue>
              </StatBox>
              <StatBox>
                <StatLabel>ZONE CENTER</StatLabel>
                <StatValue>({battleCenterX ? battleCenterX.toString() : '500'}, {battleCenterY ? battleCenterY.toString() : '500'})</StatValue>
              </StatBox>
              <StatBox>
                <StatLabel>ZONE RADIUS</StatLabel>
                <StatValue>{battleRadius ? battleRadius.toString() : '500'}</StatValue>
              </StatBox>
              {latestRound?.winnerId && (
                <StatBox style={{gridColumn: 'span 2', marginTop: '1rem', borderTop: '1px dashed #ccc', paddingTop: '0.5rem'}}>
                  <StatLabel>LAST ROUND WINNER</StatLabel>
                  <StatValue style={{fontSize: '1rem', color: 'green'}}>
                    Ticket #{latestRound.winnerId}
                    <br/>
                    <span style={{fontSize: '0.8rem', color: '#000', fontWeight: 'normal'}}>
                      Owner: {latestRound.winner?.owner?.id ? `${latestRound.winner.owner.id.slice(0,6)}...` : 'Unknown'}
                    </span>
                  </StatValue>
                </StatBox>
              )}
            </StatsGrid>
            <ActionArea>
              <JoinButton 
                onClick={() => {
                    if (isZap) setIsZap(false);
                    setShowMapModal(true);
                }}
                disabled={isPending || isConfirming}
              >
                {isPending ? 'CONFIRMING...' : 
                 isConfirming ? 'MINING...' : 
                 !isApproved('100') ? 'APPROVE USDC' : 'ENTER BATTLE (100 USDC)'}
              </JoinButton>
              {isConfirmed && <div style={{marginTop: '1rem', color: 'green', fontWeight: 'bold'}}>Transaction Confirmed!</div>}
            </ActionArea>
          </PoolCard>
        </PoolSection>
      </PoolsContainer>

      {/* History & Redeem Section */}
      {ponderData?.user?.tickets?.items && ponderData.user.tickets.items.length > 0 && (
        <HistorySection>
            <h2 style={{fontFamily: 'var(--font-mono)', marginBottom: '1rem'}}>YOUR TICKETS & HISTORY</h2>
            <div style={{overflowX: 'auto'}}>
                <HistoryTable>
                    <thead>
                        <tr>
                            <Th>ID</Th>
                            <Th>Mode</Th>
                            <Th>Assets</Th>
                            <Th>Weight</Th>
                            <Th>Date</Th>
                            <Th>Status</Th>
                            <Th>Action</Th>
                        </tr>
                    </thead>
                    <tbody>
                        {ponderData.user.tickets.items.map(ticket => {
                            let status: 'active' | 'winner' | 'redeemed' | 'dead' = 'active';
                            if (ticket.isDead) {
                                status = ticket.isWinner ? 'redeemed' : 'dead';
                            } else if (ticket.isWinner) {
                                status = 'winner';
                            }

                            return (
                                <Tr key={ticket.id}>
                                    <Td>#{ticket.id}</Td>
                                    <Td>{ticket.mode === 1 ? 'Alpha' : ticket.mode === 2 ? 'Battle' : 'Savings'}</Td>
                                    <Td>{formatUnits(BigInt(ticket.assets), 6)} USDC</Td>
                                    <Td>{ticket.multiplier ? `${Number(ticket.multiplier) / 100}x` : '1x'}</Td>
                                    <Td>{new Date(Number(ticket.mintTime) * 1000).toLocaleString()}</Td>
                                    <Td>
                                        <StatusBadge $status={status}>
                                            {status === 'dead' ? 'LOST / BURNED' : status}
                                        </StatusBadge>
                                    </Td>
                                    <Td>
                                        {status === 'winner' && (
                                            <RedeemButton 
                                                onClick={() => handleRedeem(ticket.id)}
                                                disabled={isPending}
                                            >
                                                {isPending ? '...' : 'REDEEM'}
                                            </RedeemButton>
                                        )}
                                        {status === 'active' && (
                                            <RedeemButton 
                                                onClick={() => handleRedeem(ticket.id)}
                                                disabled={isPending}
                                                style={{backgroundColor: '#fff', fontSize: '0.8rem'}}
                                            >
                                                WITHDRAW
                                            </RedeemButton>
                                        )}
                                    </Td>
                                </Tr>
                            );
                        })}
                    </tbody>
                </HistoryTable>
            </div>
        </HistorySection>
      )}

      {showMapModal && (
        <ModalOverlay onClick={() => setShowMapModal(false)}>
          <ModalContent onClick={e => e.stopPropagation()}>
            <div style={{width: '100%', display: 'flex', justifyContent: 'space-between', alignItems: 'center'}}>
                <h2 style={{fontFamily: 'var(--font-mono)'}}>SELECT DROP ZONE</h2>
                <CloseButton onClick={() => setShowMapModal(false)}>×</CloseButton>
            </div>
            <BattleMap 
                onSelect={(x, y) => setSelectedCoords({x, y})} 
                radius={battleRadius ? Number(battleRadius) : 500}
                centerX={battleCenterX ? Number(battleCenterX) : 500}
                centerY={battleCenterY ? Number(battleCenterY) : 500}
            />
            <p style={{fontFamily: 'var(--font-mono)', fontSize: '0.8rem'}}>
                Selected Coordinates: {selectedCoords ? `[${selectedCoords.x}, ${selectedCoords.y}]` : 'None'}
            </p>
            <JoinButton 
                onClick={() => handleDeposit(2, '100')}
                disabled={!selectedCoords || isPending || isConfirming}
            >
                {isPending ? 'CONFIRMING...' : 
                 isConfirming ? 'MINING...' : 
                 !isApproved('100') ? 'APPROVE USDC' : 'CONFIRM DROP'}
            </JoinButton>
          </ModalContent>
        </ModalOverlay>
      )}
    </Container>
  );
}