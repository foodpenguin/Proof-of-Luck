import type { Metadata } from 'next';
import { Providers } from './providers';
import StyledComponentsRegistry from '../lib/registry';
import { Navbar } from '../components/Navbar';

export const metadata: Metadata = {
  title: 'Proof of Luck',
  description: 'A decentralized lottery and gaming platform',
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body>
        <StyledComponentsRegistry>
          <Providers>
            <Navbar />
            {children}
          </Providers>
        </StyledComponentsRegistry>
      </body>
    </html>
  );
}
