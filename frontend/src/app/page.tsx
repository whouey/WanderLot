"use client";

import { ConnectButton } from "@mysten/dapp-kit";

/**
 * Home page — placeholder shell.
 * Replace the sections below with the actual UI components:
 *   - <PoolStats />     : live round state, ticket count, prize pool size
 *   - <DepositPanel />  : deposit USDC, see your PoolTicket
 *   - <Portfolio />     : list user's PoolTickets, collect rewards
 *   - <History />       : past rounds, win/loss, APY
 */
export default function Home() {
  return (
    <main className="min-h-screen p-8">
      {/* ── Header ── */}
      <header className="flex items-center justify-between mb-12">
        <div>
          <h1 className="text-3xl font-bold text-brand">WanderLot</h1>
          <p className="text-slate-500 text-sm mt-1">
            Pool your luck. Share the reward.
          </p>
        </div>
        <ConnectButton />
      </header>

      {/* ── Pool stats (TODO) ── */}
      <section className="grid grid-cols-1 md:grid-cols-3 gap-6 mb-12">
        <StatCard label="Current Round"   value="—" />
        <StatCard label="Pool Size"       value="— USDC" />
        <StatCard label="Tickets Held"    value="—" />
      </section>

      {/* ── Actions (TODO: replace with real components) ── */}
      <section className="grid grid-cols-1 md:grid-cols-2 gap-6">
        <PlaceholderCard title="Deposit USDC"     description="Add USDC to the shared pool and receive a PoolTicket." />
        <PlaceholderCard title="Collect Reward"   description="Claim your proportional share after the pool wins." />
        <PlaceholderCard title="Buy Tickets"      description="Convert pooled USDC into lottery invoices (permissionless)." />
        <PlaceholderCard title="Settle Round"     description="Distribute winnings and open the next round (permissionless)." />
      </section>
    </main>
  );
}

function StatCard({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-xl border border-slate-200 bg-white p-6 shadow-sm">
      <p className="text-xs uppercase tracking-wide text-slate-400">{label}</p>
      <p className="mt-2 text-2xl font-semibold text-slate-800">{value}</p>
    </div>
  );
}

function PlaceholderCard({ title, description }: { title: string; description: string }) {
  return (
    <div className="rounded-xl border border-dashed border-slate-300 bg-slate-50 p-6">
      <h2 className="font-semibold text-slate-700">{title}</h2>
      <p className="mt-1 text-sm text-slate-400">{description}</p>
      <button
        disabled
        className="mt-4 rounded-lg bg-brand px-4 py-2 text-sm font-medium text-white opacity-40 cursor-not-allowed"
      >
        Coming soon
      </button>
    </div>
  );
}
