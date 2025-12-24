'use client';

import styled from 'styled-components';
import { useState, useEffect } from 'react';
import { useAccount, useWriteContract, useBalance, useWaitForTransactionReceipt } from 'wagmi';
import { parseAbi, formatUnits, parseUnits } from 'viem';
import { CONTRACTS } from '../../utils/contracts';

const PageLayout = styled.div`
  display: flex;
  flex-direction: column;
  padding: 2rem;
  gap: 2rem;
  min-height: 100vh;
  background-color: ${({ theme }) => theme.colors.background};

  @media (min-width: ${({ theme }) => theme.breakpoints.desktop}) {
    flex-direction: row;
    align-items: flex-start;
    justify-content: center;
  }
`;

const ChartSection = styled.div`
  flex: 2;
  background-color: ${({ theme }) => theme.colors.white};
  border: 3px solid ${({ theme }) => theme.colors.black};
  padding: 1.5rem;
  box-shadow: ${({ theme }) => theme.shadows.card};
  min-height: 400px;
  display: flex;
  flex-direction: column;
`;

const ChartHeader = styled.div`
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 1rem;
  border-bottom: 2px solid ${({ theme }) => theme.colors.black};
  padding-bottom: 1rem;
`;

const TokenInfo = styled.div`
  h2 {
    font-size: 2rem;
    margin: 0;
  }
  span {
    font-family: ${({ theme }) => theme.fonts.mono};
    color: #666;
  }
`;

const PriceInfo = styled.div`
  text-align: right;
  h3 {
    font-size: 1.8rem;
    margin: 0;
    font-family: ${({ theme }) => theme.fonts.mono};
  }
  span {
    color: #00cc00;
    font-weight: bold;
  }
`;

const MockChart = styled.div`
  flex: 1;
  background: repeating-linear-gradient(
    45deg,
    #f0f0f0,
    #f0f0f0 10px,
    #ffffff 10px,
    #ffffff 20px
  );
  border: 1px dashed ${({ theme }) => theme.colors.black};
  display: flex;
  align-items: center;
  justify-content: center;
  position: relative;
  overflow: hidden;

  &::after {
    content: "CHART VISUALIZATION";
    font-family: ${({ theme }) => theme.fonts.mono};
    color: #999;
    font-size: 1.5rem;
  }
`;

const SwapSection = styled.div`
  flex: 1;
  max-width: 480px;
  width: 100%;
`;

const SwapCard = styled.div`
  background-color: ${({ theme }) => theme.colors.white};
  border: 3px solid ${({ theme }) => theme.colors.black};
  padding: 2rem;
  box-shadow: 8px 8px 0px 0px ${({ theme }) => theme.colors.primary};
`;

const Title = styled.h1`
  font-size: 2rem;
  margin-bottom: 1.5rem;
  text-align: center;
  color: ${({ theme }) => theme.colors.black};
`;

const InputGroup = styled.div`
  margin-bottom: 1.5rem;
`;

const Label = styled.label`
  display: block;
  font-family: ${({ theme }) => theme.fonts.mono};
  margin-bottom: 0.5rem;
  font-weight: bold;
  display: flex;
  justify-content: space-between;
`;

const Balance = styled.span`
  font-size: 0.8rem;
  color: #666;
`;

const InputWrapper = styled.div`
  position: relative;
`;

const Input = styled.input`
  width: 100%;
  padding: 1rem;
  font-size: 1.2rem;
  font-family: ${({ theme }) => theme.fonts.mono};
  border: 2px solid ${({ theme }) => theme.colors.black};
  background-color: ${({ theme }) => theme.colors.background};
  
  &:focus {
    outline: none;
    border-color: ${({ theme }) => theme.colors.primary};
  }
`;

const TokenBadge = styled.div`
  position: absolute;
  right: 1rem;
  top: 50%;
  transform: translateY(-50%);
  font-weight: bold;
  background: ${({ theme }) => theme.colors.black};
  color: white;
  padding: 0.2rem 0.5rem;
  border-radius: 4px;
`;

const PercentButtons = styled.div`
  display: flex;
  gap: 0.5rem;
  margin-top: 0.5rem;
`;

const PercentBtn = styled.button`
  flex: 1;
  padding: 0.2rem;
  font-size: 0.8rem;
  background: transparent;
  border: 1px solid ${({ theme }) => theme.colors.black};
  cursor: pointer;
  
  &:hover {
    background: ${({ theme }) => theme.colors.background};
  }
`;

const SwapIcon = styled.div`
  display: flex;
  justify-content: center;
  margin: -1rem 0;
  position: relative;
  z-index: 1;
  
  button {
    background: ${({ theme }) => theme.colors.secondary};
    border: 2px solid ${({ theme }) => theme.colors.black};
    width: 40px;
    height: 40px;
    border-radius: 50%;
    display: flex;
    align-items: center;
    justify-content: center;
    cursor: pointer;
    font-size: 1.2rem;
    
    &:hover {
      transform: rotate(180deg);
      transition: transform 0.3s;
    }
  }
`;

const ActionButton = styled.button`
  width: 100%;
  padding: 1rem;
  font-size: 1.2rem;
  font-weight: bold;
  background-color: ${({ theme }) => theme.colors.primary};
  color: ${({ theme }) => theme.colors.white};
  border: 2px solid ${({ theme }) => theme.colors.black};
  box-shadow: 4px 4px 0px 0px ${({ theme }) => theme.colors.black};
  cursor: pointer;
  margin-top: 1rem;
  
  &:hover {
    transform: translate(2px, 2px);
    box-shadow: 2px 2px 0px 0px ${({ theme }) => theme.colors.black};
  }
  
  &:active {
    transform: translate(4px, 4px);
    box-shadow: none;
  }

  &:disabled {
    background-color: #ccc;
    cursor: not-allowed;
    box-shadow: none;
    transform: none;
  }
`;

const SWAP_ROUTER_ADDRESS = '0x2626664c2603336E57B271c5C0b26F421741e481'; // Base Mainnet SwapRouter

const SWAP_ROUTER_ABI = parseAbi([
  'function exactInputSingle((address tokenIn, address tokenOut, uint24 fee, address recipient, uint256 amountIn, uint256 amountOutMinimum, uint160 sqrtPriceLimitX96) params) external payable returns (uint256 amountOut)'
]);

const ERC20_ABI = parseAbi([
  'function approve(address spender, uint256 amount) external returns (bool)'
]);

export default function PolPage() {
  const { address } = useAccount();
  const [amountIn, setAmountIn] = useState('');
  const [isBuying, setIsBuying] = useState(true); // true = Buy POL (USDC -> POL), false = Sell POL (POL -> USDC)
  const [step, setStep] = useState<'idle' | 'approving' | 'swapping'>('idle');
  const [approveTxHash, setApproveTxHash] = useState<`0x${string}` | undefined>(undefined);

  const tokenIn = isBuying ? CONTRACTS.USDC : CONTRACTS.POLToken;
  const tokenOut = isBuying ? CONTRACTS.POLToken : CONTRACTS.USDC;
  const decimalsIn = isBuying ? 6 : 18; // USDC 6, POL 18 (assumed)

  const { data: balanceIn } = useBalance({
    address,
    token: tokenIn.address as `0x${string}`,
  });

  const { data: balanceOut } = useBalance({
    address,
    token: tokenOut.address as `0x${string}`,
  });

  const { writeContract, isPending, data: txHash } = useWriteContract();

  // Wait for Approval
  const { isLoading: isApproving, isSuccess: isApproved } = useWaitForTransactionReceipt({
    hash: approveTxHash,
  });

  // Wait for Swap
  const { isLoading: isSwapping, isSuccess: isSwapped } = useWaitForTransactionReceipt({
    hash: txHash,
  });

  useEffect(() => {
    if (isApproved && step === 'approving') {
      setStep('swapping');
      handleSwapExecution();
    }
  }, [isApproved, step]);

  useEffect(() => {
    if (isSwapped) {
      setStep('idle');
      setAmountIn('');
    }
  }, [isSwapped]);

  const handleSwapStart = () => {
    if (!amountIn || !address) return;
    const amount = parseUnits(amountIn, decimalsIn);
    setStep('approving');

    // Approve
    writeContract({
      address: tokenIn.address as `0x${string}`,
      abi: ERC20_ABI,
      functionName: 'approve',
      args: [SWAP_ROUTER_ADDRESS, amount]
    }, {
      onSuccess: (hash) => setApproveTxHash(hash),
      onError: () => setStep('idle')
    });
  };

  const handleSwapExecution = () => {
    if (!amountIn || !address) return;
    const amount = parseUnits(amountIn, decimalsIn);

    // Swap
    writeContract({
      address: SWAP_ROUTER_ADDRESS,
      abi: SWAP_ROUTER_ABI,
      functionName: 'exactInputSingle',
      args: [{
        tokenIn: tokenIn.address as `0x${string}`,
        tokenOut: tokenOut.address as `0x${string}`,
        fee: 3000, // 0.3%
        recipient: address,
        amountIn: amount,
        amountOutMinimum: 0n, // Slippage 100% for demo
        sqrtPriceLimitX96: 0n
      }]
    }, {
      onError: () => setStep('idle')
    });
  };

  const getButtonText = () => {
    if (step === 'approving' || isApproving) return 'APPROVING...';
    if (step === 'swapping' || isSwapping) return 'SWAPPING...';
    return 'SWAP TOKENS';
  };

  return (
    <PageLayout>
      <ChartSection>
        <ChartHeader>
          <TokenInfo>
            <h2>POL / USDC</h2>
            <span>Proof of Luck Token</span>
          </TokenInfo>
          <PriceInfo>
            <h3>1 POL = 1 USDC</h3>
            <span>(Pegged)</span>
          </PriceInfo>
        </ChartHeader>
        <MockChart />
      </ChartSection>

      <SwapSection>
        <SwapCard>
          <Title>SWAP</Title>
          
          <InputGroup>
            <Label>
              <span>From</span>
              <Balance>Balance: {balanceIn ? formatUnits(balanceIn.value, decimalsIn) : '0.0'} {isBuying ? 'USDC' : 'POL'}</Balance>
            </Label>
            <InputWrapper>
              <Input 
                placeholder="0.0" 
                value={amountIn}
                onChange={(e) => setAmountIn(e.target.value)}
              />
              <TokenBadge>{isBuying ? 'USDC' : 'POL'}</TokenBadge>
            </InputWrapper>
            <PercentButtons>
              <PercentBtn onClick={() => balanceIn && setAmountIn(formatUnits(balanceIn.value / 4n, decimalsIn))}>25%</PercentBtn>
              <PercentBtn onClick={() => balanceIn && setAmountIn(formatUnits(balanceIn.value / 2n, decimalsIn))}>50%</PercentBtn>
              <PercentBtn onClick={() => balanceIn && setAmountIn(formatUnits(balanceIn.value, decimalsIn))}>MAX</PercentBtn>
            </PercentButtons>
          </InputGroup>

          <SwapIcon>
            <button onClick={() => setIsBuying(!isBuying)}>↓</button>
          </SwapIcon>

          <InputGroup>
            <Label>
              <span>To</span>
              <Balance>Balance: {balanceOut ? formatUnits(balanceOut.value, isBuying ? 18 : 6) : '0.0'} {isBuying ? 'POL' : 'USDC'}</Balance>
            </Label>
            <InputWrapper>
              <Input placeholder="0.0" readOnly value={amountIn} />
              <TokenBadge>{isBuying ? 'POL' : 'USDC'}</TokenBadge>
            </InputWrapper>
          </InputGroup>

          <ActionButton onClick={handleSwapStart} disabled={isPending || isApproving || isSwapping || !amountIn}>
            {getButtonText()}
          </ActionButton>
        </SwapCard>
      </SwapSection>
    </PageLayout>
  );
}
