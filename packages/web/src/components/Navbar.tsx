'use client';

import styled from 'styled-components';
import { ConnectButton } from '@rainbow-me/rainbowkit';
import Link from 'next/link';

const Nav = styled.nav`
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 1rem 2rem;
  background-color: ${({ theme }) => theme.colors.white};
  border-bottom: 2px solid ${({ theme }) => theme.colors.black};
  position: sticky;
  top: 0;
  z-index: 100;
`;

const Logo = styled(Link)`
  font-family: ${({ theme }) => theme.fonts.title};
  font-size: 1.5rem;
  color: ${({ theme }) => theme.colors.primary};
  text-shadow: 2px 2px 0px ${({ theme }) => theme.colors.black};
`;

const NavLinks = styled.div`
  display: flex;
  gap: 2rem;
  align-items: center;

  @media (max-width: ${({ theme }) => theme.breakpoints.tablet}) {
    display: none;
  }
`;

const NavLink = styled(Link)`
  font-family: ${({ theme }) => theme.fonts.mono};
  font-weight: bold;
  text-transform: uppercase;
  
  &:hover {
    color: ${({ theme }) => theme.colors.primary};
    text-decoration: underline;
  }
`;

export const Navbar = () => {
  return (
    <Nav>
      <Logo href="/">PROOF OF LUCK</Logo>
      <NavLinks>
        <NavLink href="/lotto">Lotto</NavLink>
        <NavLink href="/nft">NFT</NavLink>
        <NavLink href="/pol">PoL</NavLink>
        <NavLink href="/governance">Governance</NavLink>
      </NavLinks>
      <ConnectButton showBalance={false} />
    </Nav>
  );
};
