"use client";

import { ConnectButton, useCurrentAccount } from "@mysten/dapp-kit";
import { PoolStats } from "@/components/PoolStats";
import { DepositPanel } from "@/components/DepositPanel";
import { MyTickets } from "@/components/MyTickets";
import { PermissionlessActions } from "@/components/PermissionlessActions";

export default function Home() {
  const account = useCurrentAccount();

  return (
    <main className="min-h-screen bg-slate-50">
      {/* ── Header ── */}
      <header className="sticky top-0 z-10 border-b border-slate-200 bg-white/80 backdrop-blur-sm">
        <div className="max-w-5xl mx-auto px-6 py-4 flex items-center justify-between">
          <div>
            <span className="text-xl font-bold text-brand tracking-tight">WanderLot</span>
            <span className="ml-2 text-xs text-slate-400">Pool your luck. Share the reward.</span>
          </div>
          <ConnectButton />
        </div>
      </header>

      <div className="max-w-5xl mx-auto px-6 py-8 space-y-8">
        {/* ── Pool stats bar ── */}
        <PoolStats />

        {/* ── Main actions ── */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <DepositPanel />

          {/* Info card */}
          <div className="rounded-xl border border-slate-200 bg-white p-6 shadow-sm space-y-4">
            <h2 className="font-semibold text-slate-800 text-lg">How it works</h2>
            <ol className="space-y-3 text-sm text-slate-600 list-decimal list-inside">
              <li>
                <span className="font-medium">Deposit USDC</span> — you receive a PoolTicket
                proving your stake for this round.
              </li>
              <li>
                <span className="font-medium">Pool buys tickets</span> — the USDC is converted
                10:1 into TAX_COIN, then into Invoice lottery tickets.
              </li>
              <li>
                <span className="font-medium">Lottery runs</span> — admin draws a random winner
                from all invoices ever created.
              </li>
              <li>
                <span className="font-medium">Settle &amp; collect</span> — if the pool holds the
                winning ticket, the prize is shared proportionally to all depositors.
              </li>
            </ol>
            <div className="rounded-lg bg-slate-50 px-4 py-3 text-xs text-slate-500 leading-relaxed">
              Same expected value as solo play — lower variance because the pool
              spreads risk across all depositors.
            </div>
          </div>
        </div>

        {/* ── Permissionless operator panel ── */}
        <section>
          <h2 className="text-sm font-semibold text-slate-500 uppercase tracking-wide mb-3">
            Permissionless Actions
          </h2>
          <PermissionlessActions />
        </section>

        {/* ── User portfolio ── */}
        {account && (
          <section>
            <h2 className="text-sm font-semibold text-slate-500 uppercase tracking-wide mb-3">
              My Portfolio
            </h2>
            <MyTickets />
          </section>
        )}
      </div>

      {/* ── Footer ── */}
      <footer className="mt-16 border-t border-slate-200 py-6 text-center text-xs text-slate-400">
        WanderLot &mdash; built on Sui &middot; contracts on{" "}
        <span className="font-mono">testnet-v1.42.0</span>
      </footer>
    </main>
  );
}
