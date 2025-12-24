'use client';

import styled from 'styled-components';
import { ConnectButton } from '@rainbow-me/rainbowkit';

const Container = styled.main`
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  min-height: 100vh;
  padding: 2rem;
  background-color: ${({ theme }) => theme.colors.background};
`;

const Title = styled.h1`
  font-size: 4rem;
  color: ${({ theme }) => theme.colors.primary};
  margin-bottom: 2rem;
  text-shadow: 4px 4px 0px ${({ theme }) => theme.colors.black};
  text-align: center;
`;

const Subtitle = styled.p`
  font-size: 1.5rem;
  color: ${({ theme }) => theme.colors.text};
  margin-bottom: 3rem;
  font-family: ${({ theme }) => theme.fonts.mono};
  text-align: center;
`;

export default function Home() {
  return (
    <Container>
      <Title>PROOF OF LUCK</Title>
      <Subtitle>DECENTRALIZED LOTTERY PROTOCOL</Subtitle>
      <ConnectButton />
    </Container>
  );
}
