'use client';

import styled from 'styled-components';
import { useState, useEffect } from 'react';
import { useAccount, useWriteContract, useReadContract, useWaitForTransactionReceipt } from 'wagmi';
import { parseAbi, formatUnits, parseUnits } from 'viem';
import { CONTRACTS } from '../../utils/contracts';
import { usePonderQuery } from '../../hooks/usePonder';
import { gql } from '../../utils/ponder';

const Container = styled.div`
  padding: 2rem;
  min-height: 100vh;
  background-color: ${({ theme }) => theme.colors.background};
`;

const Header = styled.div`
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 2rem;
  flex-wrap: wrap;
  gap: 1rem;
`;

const Title = styled.h1`
  font-size: 3rem;
  color: ${({ theme }) => theme.colors.black};
  text-transform: uppercase;
  margin: 0;
`;

const StatsGrid = styled.div`
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
  gap: 1.5rem;
  margin-bottom: 3rem;
`;

const StatCard = styled.div`
  background-color: ${({ theme }) => theme.colors.white};
  border: 3px solid ${({ theme }) => theme.colors.black};
  padding: 1.5rem;
  box-shadow: ${({ theme }) => theme.shadows.card};
`;

const StatLabel = styled.div`
  font-family: ${({ theme }) => theme.fonts.mono};
  font-size: 0.9rem;
  color: #666;
  text-transform: uppercase;
  margin-bottom: 0.5rem;
`;

const StatValue = styled.div`
  font-size: 2rem;
  font-weight: bold;
  color: ${({ theme }) => theme.colors.primary};
`;

const SectionTitle = styled.h2`
  font-size: 2rem;
  margin-bottom: 1.5rem;
  border-bottom: 4px solid ${({ theme }) => theme.colors.black};
  display: inline-block;
`;

const ContentGrid = styled.div`
  display: grid;
  grid-template-columns: 1fr;
  gap: 2rem;
  
  @media (min-width: ${({ theme }) => theme.breakpoints.desktop}) {
    grid-template-columns: 1fr 2fr;
  }
`;

const StakingCard = styled.div`
  background-color: ${({ theme }) => theme.colors.secondary};
  border: 3px solid ${({ theme }) => theme.colors.black};
  padding: 2rem;
  height: fit-content;
`;

const StakingInput = styled.input`
  width: 100%;
  padding: 1rem;
  margin: 1rem 0;
  border: 2px solid ${({ theme }) => theme.colors.black};
  font-family: ${({ theme }) => theme.fonts.mono};
  font-size: 1.2rem;
`;

const ActionButton = styled.button`
  width: 100%;
  padding: 1rem;
  background-color: ${({ theme }) => theme.colors.black};
  color: ${({ theme }) => theme.colors.white};
  font-weight: bold;
  border: none;
  cursor: pointer;
  margin-bottom: 1rem;
  
  &:hover {
    opacity: 0.9;
  }
  
  &:disabled {
    background-color: #ccc;
    cursor: not-allowed;
  }
`;

const ProposalCard = styled.div`
  background-color: ${({ theme }) => theme.colors.white};
  border: 2px solid ${({ theme }) => theme.colors.black};
  padding: 1.5rem;
  margin-bottom: 1rem;
  
  &:hover {
    box-shadow: ${({ theme }) => theme.shadows.card};
  }
`;

const ProposalHeader = styled.div`
  display: flex;
  justify-content: space-between;
  margin-bottom: 1rem;
`;

const StatusBadge = styled.span<{ status: string }>`
  background-color: ${({ status }) => 
    status === 'Active' ? '#4caf50' : 
    status === 'Executed' ? '#2196f3' : '#9e9e9e'};
  color: white;
  padding: 0.25rem 0.5rem;
  border-radius: 4px;
  font-size: 0.8rem;
  font-weight: bold;
`;

const VoteButtons = styled.div`
  display: flex;
  gap: 1rem;
  margin-top: 1rem;
`;

const VoteBtn = styled.button<{ type: 'for' | 'against' }>`
  flex: 1;
  padding: 0.5rem;
  background-color: ${({ type }) => type === 'for' ? '#4caf50' : '#f44336'};
  color: white;
  border: 2px solid black;
  cursor: pointer;
  font-weight: bold;
  
  &:hover {
    opacity: 0.9;
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
  gap: 1rem;
  box-shadow: 10px 10px 0px 0px ${({ theme }) => theme.colors.secondary};
`;

const TextArea = styled.textarea`
  width: 100%;
  padding: 1rem;
  border: 2px solid ${({ theme }) => theme.colors.black};
  font-family: ${({ theme }) => theme.fonts.mono};
  min-height: 100px;
`;

const STAKING_ABI = parseAbi([
  'function stake(uint256 amount, address receiver) external returns (uint256)',
  'function withdraw(uint256 amount) external',
  'function balanceOf(address account) external view returns (uint256)',
  'function getVotes(address account) external view returns (uint256)'
]);

const GOVERNOR_ABI = parseAbi([
  'function castVote(uint256 proposalId, uint8 support) external returns (uint256)',
  'function propose(address[] targets, uint256[] values, bytes[] calldatas, string description) external returns (uint256)'
]);

const ERC20_ABI = parseAbi([
  'function approve(address spender, uint256 amount) external returns (bool)',
  'function balanceOf(address account) external view returns (uint256)'
]);

export default function GovernancePage() {
  const { address } = useAccount();
  const [stakeAmount, setStakeAmount] = useState('');
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [proposalDesc, setProposalDesc] = useState('');
  const [step, setStep] = useState<'idle' | 'approving' | 'staking'>('idle');
  const [approveTxHash, setApproveTxHash] = useState<`0x${string}` | undefined>(undefined);
  
  const { data: proposalsData, isLoading: isProposalsLoading } = usePonderQuery(['governance-proposals'], gql`
    query GetProposals {
      proposals(orderBy: "startBlock", orderDirection: "desc") {
        items {
          id
          description
          status
          forVotes
          againstVotes
          endBlock
        }
      }
    }
  `);

  const { data: stakedBalance } = useReadContract({
    address: CONTRACTS.POLStaking.address as `0x${string}`,
    abi: STAKING_ABI,
    functionName: 'balanceOf',
    args: [address || '0x0000000000000000000000000000000000000000']
  });

  const { data: votingPower } = useReadContract({
    address: CONTRACTS.POLStaking.address as `0x${string}`,
    abi: STAKING_ABI,
    functionName: 'getVotes',
    args: [address || '0x0000000000000000000000000000000000000000']
  });

  const { data: polBalance } = useReadContract({
    address: CONTRACTS.POLToken.address as `0x${string}`,
    abi: ERC20_ABI,
    functionName: 'balanceOf',
    args: [address || '0x0000000000000000000000000000000000000000']
  });

  const { writeContract, isPending, data: txHash } = useWriteContract();

  const { isLoading: isApproving, isSuccess: isApproved } = useWaitForTransactionReceipt({
    hash: approveTxHash,
  });

  const { isLoading: isStaking, isSuccess: isStaked } = useWaitForTransactionReceipt({
    hash: txHash,
  });

  useEffect(() => {
    if (isApproved && step === 'approving') {
      setStep('staking');
      executeStake();
    }
  }, [isApproved, step]);

  useEffect(() => {
    if (isStaked) {
      setStep('idle');
      setStakeAmount('');
    }
  }, [isStaked]);

  const handleStake = () => {
    if (!stakeAmount) return;
    const amount = parseUnits(stakeAmount, 18);
    setStep('approving');

    writeContract({
      address: CONTRACTS.POLToken.address as `0x${string}`,
      abi: ERC20_ABI,
      functionName: 'approve',
      args: [CONTRACTS.POLStaking.address as `0x${string}`, amount]
    }, {
      onSuccess: (hash) => setApproveTxHash(hash),
      onError: () => setStep('idle')
    });
  };

  const executeStake = () => {
    if (!stakeAmount || !address) return;
    const amount = parseUnits(stakeAmount, 18);

    writeContract({
      address: CONTRACTS.POLStaking.address as `0x${string}`,
      abi: STAKING_ABI,
      functionName: 'stake',
      args: [amount, address]
    }, {
      onError: () => setStep('idle')
    });
  };

  const handleVote = (proposalId: string, support: number) => {
    writeContract({
      address: CONTRACTS.POLGovernor.address as `0x${string}`,
      abi: GOVERNOR_ABI,
      functionName: 'castVote',
      args: [BigInt(proposalId), support] // 0=Against, 1=For, 2=Abstain
    });
  };

  const handleCreateProposal = () => {
    if (!proposalDesc) return;
    
    // Create a dummy proposal (self-transfer 0 ETH) just for discussion
    writeContract({
      address: CONTRACTS.POLGovernor.address as `0x${string}`,
      abi: GOVERNOR_ABI,
      functionName: 'propose',
      args: [
        [address as `0x${string}`], // Target
        [0n], // Value
        ['0x'], // Calldata
        proposalDesc // Description
      ]
    }, {
      onSuccess: () => {
        setIsModalOpen(false);
        setProposalDesc('');
      }
    });
  };

  const handleDelegate = () => {
    if (!address) return;
    writeContract({
      address: CONTRACTS.POLToken.address as `0x${string}`,
      abi: parseAbi(['function delegate(address delegatee) external']),
      functionName: 'delegate',
      args: [address],
    });
  };

  return (
    <Container>
      <Header>
        <Title>Governance</Title>
        <div style={{ display: 'flex', gap: '1rem' }}>
          <ActionButton style={{ width: 'auto', marginBottom: 0 }} onClick={handleDelegate}>
            Delegate to Self
          </ActionButton>
          <ActionButton style={{ width: 'auto', marginBottom: 0 }} onClick={() => setIsModalOpen(true)}>
            + Create Proposal
          </ActionButton>
        </div>
      </Header>

      <StatsGrid>
        <StatCard>
          <StatLabel>Your POL Balance</StatLabel>
          <StatValue>{polBalance ? formatUnits(polBalance as bigint, 18) : '0'} POL</StatValue>
        </StatCard>
        <StatCard>
          <StatLabel>Your Staked (sPOL)</StatLabel>
          <StatValue>{stakedBalance ? formatUnits(stakedBalance as bigint, 18) : '0'} sPOL</StatValue>
        </StatCard>
        <StatCard>
          <StatLabel>Voting Power</StatLabel>
          <StatValue>{votingPower ? formatUnits(votingPower as bigint, 18) : '0'} vPOL</StatValue>
        </StatCard>
      </StatsGrid>

      <ContentGrid>
        <div>
          <SectionTitle>Staking</SectionTitle>
          <StakingCard>
            <h3>Stake POL to Vote</h3>
            <p>Lock your POL tokens to receive voting power and rewards.</p>
            
            <StakingInput 
              placeholder="Amount to stake" 
              value={stakeAmount}
              onChange={(e) => setStakeAmount(e.target.value)}
            />
            
            <ActionButton onClick={handleStake} disabled={isPending || isApproving || isStaking}>
              {step === 'approving' ? 'Approving...' : step === 'staking' ? 'Staking...' : 'STAKE POL'}
            </ActionButton>
            
            <div style={{ textAlign: 'center', fontSize: '0.9rem' }}>
              <a href="#" style={{ color: 'black' }}>Unstake Tokens</a>
            </div>
          </StakingCard>
        </div>

        <div>
          <SectionTitle>Proposals</SectionTitle>
          {isProposalsLoading ? (
            <div>Loading proposals...</div>
          ) : (
            <div>
              {proposalsData?.proposals.items.map((proposal: any) => (
                <ProposalCard key={proposal.id}>
                  <ProposalHeader>
                    <h3>Proposal #{proposal.id}</h3>
                    <StatusBadge status={proposal.status}>{proposal.status}</StatusBadge>
                  </ProposalHeader>
                  <p>{proposal.description}</p>
                  
                  <div style={{ margin: '1rem 0' }}>
                    <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '0.5rem' }}>
                      <span>For: {formatUnits(BigInt(proposal.forVotes), 18)}</span>
                      <span>Against: {formatUnits(BigInt(proposal.againstVotes), 18)}</span>
                    </div>
                    <div style={{ height: '10px', background: '#eee', borderRadius: '5px', overflow: 'hidden' }}>
                      <div style={{ 
                        width: `${Number(proposal.forVotes) / (Number(proposal.forVotes) + Number(proposal.againstVotes) || 1) * 100}%`, 
                        height: '100%', 
                        background: '#4caf50' 
                      }} />
                    </div>
                  </div>

                  <VoteButtons>
                    <VoteBtn type="for" onClick={() => handleVote(proposal.id, 1)}>VOTE FOR</VoteBtn>
                    <VoteBtn type="against" onClick={() => handleVote(proposal.id, 0)}>VOTE AGAINST</VoteBtn>
                  </VoteButtons>
                </ProposalCard>
              ))}
              {proposalsData?.proposals.items.length === 0 && <div>No proposals found</div>}
            </div>
          )}
        </div>
      </ContentGrid>

      {isModalOpen && (
        <ModalOverlay onClick={() => setIsModalOpen(false)}>
          <ModalContent onClick={(e) => e.stopPropagation()}>
            <h2>Create Proposal</h2>
            <p>Describe your proposal below. This will create a simple on-chain proposal.</p>
            <TextArea 
              placeholder="Proposal Description..." 
              value={proposalDesc}
              onChange={(e) => setProposalDesc(e.target.value)}
            />
            <div style={{ display: 'flex', gap: '1rem' }}>
              <ActionButton onClick={handleCreateProposal} disabled={isPending}>
                Submit Proposal
              </ActionButton>
              <ActionButton onClick={() => setIsModalOpen(false)} style={{ backgroundColor: '#ccc' }}>
                Cancel
              </ActionButton>
            </div>
          </ModalContent>
        </ModalOverlay>
      )}
    </Container>
  );
}
