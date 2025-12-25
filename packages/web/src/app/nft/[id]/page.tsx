'use client';

import styled from 'styled-components';
import { useParams, useRouter } from 'next/navigation';
import { usePonderQuery } from '../../../hooks/usePonder';
import { gql } from '../../../utils/ponder';
import { formatUnits } from 'viem';

const Container = styled.div`
  padding: 2rem;
  min-height: 100vh;
  background-color: ${({ theme }) => theme.colors.background};
`;

const BackButton = styled.button`
  background: none;
  border: none;
  font-size: 1.2rem;
  cursor: pointer;
  margin-bottom: 2rem;
  font-family: ${({ theme }) => theme.fonts.mono};
  
  &:hover {
    text-decoration: underline;
  }
`;

const DetailCard = styled.div`
  background-color: ${({ theme }) => theme.colors.white};
  border: 3px solid ${({ theme }) => theme.colors.black};
  padding: 2rem;
  box-shadow: ${({ theme }) => theme.shadows.card};
  max-width: 800px;
  margin: 0 auto;
  display: flex;
  gap: 3rem;

  @media (max-width: ${({ theme }) => theme.breakpoints.tablet}) {
    flex-direction: column;
  }
`;

const ImageSection = styled.div`
  flex: 1;
  aspect-ratio: 1;
  background-color: #f0f0f0;
  border: 2px solid ${({ theme }) => theme.colors.black};
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 5rem;
  font-family: ${({ theme }) => theme.fonts.mono};
`;

const InfoSection = styled.div`
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: 1.5rem;
`;

const Title = styled.h1`
  font-size: 2.5rem;
  margin: 0;
  color: ${({ theme }) => theme.colors.primary};
`;

const StatRow = styled.div`
  display: flex;
  justify-content: space-between;
  border-bottom: 1px solid #eee;
  padding-bottom: 0.5rem;
`;

const Label = styled.span`
  font-weight: bold;
  color: #666;
`;

const Value = styled.span`
  font-family: ${({ theme }) => theme.fonts.mono};
`;

export default function NFTDetailPage() {
  const params = useParams();
  const router = useRouter();
  const id = params.id as string;

  const { data, isLoading } = usePonderQuery(['nft-detail', id], gql`
    query GetNFTDetail($id: String!) {
      ticket(id: $id) {
        id
        mode
        assets
        mintTime
        isWinner
        prize
        multiplier
        owner {
          id
        }
      }
    }
  `, { id }, { refetchInterval: 2000 });

  if (isLoading) return <Container>Loading...</Container>;
  if (!data?.ticket) return <Container>NFT not found</Container>;

  const ticket = data.ticket;

  return (
    <Container>
      <BackButton onClick={() => router.back()}>← Back to Market</BackButton>
      
      <DetailCard>
        <ImageSection>
          #{ticket.id}
        </ImageSection>
        
        <InfoSection>
          <Title>Ticket #{ticket.id}</Title>
          
          <StatRow>
            <Label>Owner</Label>
            <Value>{ticket.owner.id.slice(0, 6)}...{ticket.owner.id.slice(-4)}</Value>
          </StatRow>
          
          <StatRow>
            <Label>Pool Mode</Label>
            <Value>{ticket.mode === 1 ? 'Savings' : ticket.mode === 2 ? 'Alpha' : 'Battle'}</Value>
          </StatRow>
          
          <StatRow>
            <Label>Deposited Assets</Label>
            <Value>{formatUnits(BigInt(ticket.assets), 6)} USDC</Value>
          </StatRow>

          <StatRow>
            <Label>Mint Time</Label>
            <Value>{new Date(Number(ticket.mintTime) * 1000).toLocaleDateString()}</Value>
          </StatRow>

          <StatRow>
            <Label>Multiplier</Label>
            <Value>{ticket.multiplier / 100}x</Value>
          </StatRow>

          {ticket.isWinner && (
            <StatRow>
              <Label>Total Winnings</Label>
              <Value>{formatUnits(BigInt(ticket.prize), 6)} USDC</Value>
            </StatRow>
          )}
        </InfoSection>
      </DetailCard>
    </Container>
  );
}
