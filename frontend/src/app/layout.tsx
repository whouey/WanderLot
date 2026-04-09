"use client";

import { Inter } from "next/font/google";
import "./globals.css";

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { SuiClientProvider, WalletProvider } from "@mysten/dapp-kit";
import { getFullnodeUrl } from "@mysten/sui/client";
import "@mysten/dapp-kit/dist/index.css";

const inter = Inter({ subsets: ["latin"] });

const queryClient = new QueryClient();

const networks = {
  testnet: { url: getFullnodeUrl("testnet") },
  devnet:  { url: getFullnodeUrl("devnet") },
  mainnet: { url: getFullnodeUrl("mainnet") },
};

const defaultNetwork = (process.env.NEXT_PUBLIC_SUI_NETWORK ?? "testnet") as keyof typeof networks;

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body className={inter.className}>
        <QueryClientProvider client={queryClient}>
          <SuiClientProvider networks={networks} defaultNetwork={defaultNetwork}>
            <WalletProvider autoConnect>
              {children}
            </WalletProvider>
          </SuiClientProvider>
        </QueryClientProvider>
      </body>
    </html>
  );
}
