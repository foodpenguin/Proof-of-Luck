'use client';

import styled from 'styled-components';
import { useState, useEffect } from 'react';
import { useAccount, useWriteContract, useWaitForTransactionReceipt } from 'wagmi';
import { parseAbi, formatUnits, parseUnits } from 'viem';
import { CONTRACTS } from '../../utils/contracts';
import { usePonderQuery } from '../../hooks/usePonder';
import { gql } from '../../utils/ponder';

const Container = styled.div`
  padding: 2rem;
  min-height: 100vh;
  background-color: ${({ theme }) => theme.colors.background};
`;

const Title = styled.h1`
  font-size: 3rem;
  color: ${({ theme }) => theme.colors.secondary};
  text-shadow: 3px 3px 0px ${({ theme }) => theme.colors.black};
  -webkit-text-stroke: 1px black;
  margin-bottom: 2rem;
`;

const SectionTitle = styled.h2`
  font-size: 2rem;
  margin: 2rem 0 1rem;
  color: ${({ theme }) => theme.colors.primary};
`;

const MarketGrid = styled.div`
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(250px, 1fr));
  gap: 2rem;
`;

const NFTCard = styled.div`
  background-color: ${({ theme }) => theme.colors.white};
  border: 2px solid ${({ theme }) => theme.colors.black};
  padding: 1rem;
  box-shadow: ${({ theme }) => theme.shadows.card};
  cursor: pointer;
  transition: transform 0.2s;

  &:hover {
    transform: translateY(-5px);
  }
`;

const NFTImage = styled.div`
  width: 100%;
  height: 250px;
  background-color: #f0f0f0;
  margin-bottom: 1rem;
  border: 2px solid ${({ theme }) => theme.colors.black};
  display: flex;
  align-items: center;
  justify-content: center;
  font-family: ${({ theme }) => theme.fonts.mono};
  font-size: 3rem;
`;

const NFTInfo = styled.div`
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 0.5rem;
`;

const NFTName = styled.h3`
  font-size: 1.2rem;
  margin: 0;
`;

const NFTPrice = styled.div`
  font-family: ${({ theme }) => theme.fonts.mono};
  font-weight: bold;
  color: ${({ theme }) => theme.colors.primary};
`;

const ActionButton = styled.button`
  width: 100%;
  padding: 0.8rem;
  margin-top: 1rem;
  background-color: ${({ theme }) => theme.colors.primary};
  color: ${({ theme }) => theme.colors.white};
  border: 2px solid ${({ theme }) => theme.colors.black};
  font-weight: bold;
  cursor: pointer;
  
  &:hover {
    background-color: ${({ theme }) => theme.colors.secondary};
    color: ${({ theme }) => theme.colors.black};
  }

  &:disabled {
    background-color: #ccc;
    cursor: not-allowed;
  }
`;

const Input = styled.input`
  width: 100%;
  padding: 0.5rem;
  margin-top: 0.5rem;
  border: 2px solid ${({ theme }) => theme.colors.black};
  font-family: ${({ theme }) => theme.fonts.mono};
`;

const MARKETPLACE_ABI = parseAbi([
  'function buy(uint256 tokenId) external',
  'function list(uint256 tokenId, uint256 price) external',
  'function cancelListing(uint256 tokenId) external'
]);

const ERC721_ABI = parseAbi([
  'function approve(address to, uint256 tokenId) external',
  'function getApproved(uint256 tokenId) external view returns (address)',
  'function isApprovedForAll(address owner, address operator) external view returns (bool)'
]);

import { useRouter } from 'next/navigation';

const ERC20_ABI = parseAbi([
  'function approve(address spender, uint256 amount) external returns (bool)'
]);

export default function NFTPage() {
  const router = useRouter();
  const { address } = useAccount();
  const [listingPrice, setListingPrice] = useState<string>('');
  const [selectedTokenId, setSelectedTokenId] = useState<string | null>(null);
  const [processingId, setProcessingId] = useState<string | null>(null);
  const [approveTxHash, setApproveTxHash] = useState<`0x${string}` | undefined>(undefined);
  const [actionType, setActionType] = useState<'buy' | 'list' | null>(null);

  const { data: marketData, isLoading: isMarketLoading } = usePonderQuery(['nft-listings'], gql`
    query GetListings {
      listings(where: { isActive: true }) {
        items {
          id
          tokenId
          price
          seller {
            id
          }
        }
      }
    }
  `, {}, { refetchInterval: 2000 });

  const { data: userData, isLoading: isUserLoading } = usePonderQuery(['user-tickets', address || ''], gql`
    query GetUserTickets($ownerId: String!) {
      tickets(where: { ownerId: $ownerId, isDead: false }) {
        items {
          id
          mode
          assets
        }
      }
    }
  `, { ownerId: address ? address.toLowerCase() : '' }, { enabled: !!address, refetchInterval: 2000 });

  const { writeContract, isPending, data: txHash } = useWriteContract();

  const { isLoading: isApproving, isSuccess: isApproved } = useWaitForTransactionReceipt({
    hash: approveTxHash,
  });

  const { isLoading: isConfirming, isSuccess: isConfirmed } = useWaitForTransactionReceipt({
    hash: txHash,
  });

  useEffect(() => {
    if (isApproved && processingId && actionType) {
      if (actionType === 'buy') {
        executeBuy(processingId);
      } else if (actionType === 'list') {
        executeList(processingId);
      }
    }
  }, [isApproved, processingId, actionType]);

  useEffect(() => {
    if (isConfirmed) {
      setProcessingId(null);
      setActionType(null);
      setSelectedTokenId(null);
      setListingPrice('');
    }
  }, [isConfirmed]);

  const handleBuy = (tokenId: string, price: bigint) => {
    setProcessingId(tokenId);
    setActionType('buy');
    
    // Approve USDC
    writeContract({
      address: CONTRACTS.USDC.address as `0x${string}`,
      abi: ERC20_ABI,
      functionName: 'approve',
      args: [CONTRACTS.TicketMarketplace.address as `0x${string}`, price]
    }, {
      onSuccess: (hash) => setApproveTxHash(hash),
      onError: () => setProcessingId(null)
    });
  };

  const executeBuy = (tokenId: string) => {
    writeContract({
      address: CONTRACTS.TicketMarketplace.address as `0x${string}`,
      abi: MARKETPLACE_ABI,
      functionName: 'buy',
      args: [BigInt(tokenId)]
    }, {
      onError: () => setProcessingId(null)
    });
  };

  const handleList = (tokenId: string) => {
    if (!listingPrice) return;
    setProcessingId(tokenId);
    setActionType('list');

    // Approve NFT
    writeContract({
      address: CONTRACTS.MasterVault.address as `0x${string}`,
      abi: ERC721_ABI,
      functionName: 'approve',
      args: [CONTRACTS.TicketMarketplace.address as `0x${string}`, BigInt(tokenId)]
    }, {
      onSuccess: (hash) => setApproveTxHash(hash),
      onError: () => setProcessingId(null)
    });
  };

  const executeList = (tokenId: string) => {
    const price = parseUnits(listingPrice, 6);
    writeContract({
      address: CONTRACTS.TicketMarketplace.address as `0x${string}`,
      abi: MARKETPLACE_ABI,
      functionName: 'list',
      args: [BigInt(tokenId), price]
    }, {
      onError: () => setProcessingId(null)
    });
  };

  return (
    <Container>
      <Title>NFT Marketplace</Title>

      <SectionTitle>Active Listings</SectionTitle>
      {isMarketLoading ? (
        <div>Loading market...</div>
      ) : (
        <MarketGrid>
          {marketData?.listings.items.map((listing: any) => (
            <NFTCard key={listing.id} onClick={() => router.push(`/nft/${listing.tokenId}`)}>
              <NFTImage>#{listing.tokenId}</NFTImage>
              <NFTInfo>
                <NFTName>Ticket #{listing.tokenId}</NFTName>
                <NFTPrice>{formatUnits(BigInt(listing.price), 6)} USDC</NFTPrice>
              </NFTInfo>
              <ActionButton 
                onClick={(e) => {
                  e.stopPropagation();
                  handleBuy(listing.tokenId, BigInt(listing.price));
                }}
                disabled={!!processingId || listing.seller.id.toLowerCase() === address?.toLowerCase()}
              >
                {processingId === listing.tokenId ? 'Processing...' : 
                 listing.seller.id.toLowerCase() === address?.toLowerCase() ? 'You Own This' : 'Buy Now'}
              </ActionButton>
            </NFTCard>
          ))}
          {marketData?.listings.items.length === 0 && <div>No active listings</div>}
        </MarketGrid>
      )}

      {address && (
        <>
          <SectionTitle>Your Tickets</SectionTitle>
          {isUserLoading ? (
            <div>Loading your tickets...</div>
          ) : (
            <MarketGrid>
              {userData?.tickets.items.map((ticket: any) => (
                <NFTCard key={ticket.id}>
                  <NFTImage>#{ticket.id}</NFTImage>
                  <NFTInfo>
                    <NFTName>Ticket #{ticket.id}</NFTName>
                    <NFTPrice>Mode: {ticket.mode}</NFTPrice>
                  </NFTInfo>
                  {selectedTokenId === ticket.id ? (
                    <>
                      <Input 
                        type="number" 
                        placeholder="Price in USDC" 
                        value={listingPrice}
                        onChange={(e) => setListingPrice(e.target.value)}
                      />
                      <div style={{ display: 'flex', gap: '0.5rem' }}>
                        <ActionButton onClick={() => handleList(ticket.id)} disabled={!!processingId}>
                          {processingId === ticket.id ? 'Processing...' : 'Confirm List'}
                        </ActionButton>
                        <ActionButton onClick={() => setSelectedTokenId(null)} style={{ backgroundColor: '#ccc' }} disabled={!!processingId}>
                          Cancel
                        </ActionButton>
                      </div>
                    </>
                  ) : (
                    <ActionButton onClick={() => setSelectedTokenId(ticket.id)} disabled={!!processingId}>
                      List for Sale
                    </ActionButton>
                  )}
                </NFTCard>
              ))}
              {userData?.tickets.items.length === 0 && <div>You have no tickets to list. Play some games first!</div>}
            </MarketGrid>
          )}
        </>
      )}
    </Container>
  );
}
