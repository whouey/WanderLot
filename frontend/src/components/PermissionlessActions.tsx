"use client";

import { useSignAndExecuteTransaction } from "@mysten/dapp-kit";
import { usePool } from "@/hooks/usePool";
import { buildBuyTicketsTx, buildSettleRoundTx } from "@/lib/sui";

export function PermissionlessActions() {
  const { data: pool, refetch } = usePool();
  const { mutate: sign, isPending } = useSignAndExecuteTransaction();

  const isOpen   = pool?.state === "OPEN";
  const isLocked = pool?.state === "LOCKED";
  const hasUsdc  = (pool?.usdcBalance ?? 0n) > 0n;

  function buyTickets() {
    const tx = buildBuyTicketsTx();
    sign({ transaction: tx }, { onSuccess: () => refetch() });
  }

  function settleRound() {
    const tx = buildSettleRoundTx();
    sign({ transaction: tx }, { onSuccess: () => refetch() });
  }

  return (
    <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
      {/* Buy Tickets */}
      <div className={`rounded-xl border p-5 ${isOpen && hasUsdc ? "border-slate-200 bg-white shadow-sm" : "border-dashed border-slate-300 bg-slate-50"}`}>
        <div className="flex items-start justify-between gap-3">
          <div>
            <h3 className="font-semibold text-slate-700">Buy Tickets</h3>
            <p className="text-xs text-slate-400 mt-1 leading-relaxed">
              Convert pooled USDC into lottery invoices. Anyone can call this.
            </p>
            {isLocked && (
              <p className="mt-2 text-xs text-amber-600 bg-amber-50 rounded px-2 py-1">
                Tickets already bought — pool is LOCKED.
              </p>
            )}
            {isOpen && !hasUsdc && (
              <p className="mt-2 text-xs text-slate-400 bg-slate-100 rounded px-2 py-1">
                No USDC in pool yet.
              </p>
            )}
          </div>
          <button
            onClick={buyTickets}
            disabled={!isOpen || !hasUsdc || isPending}
            className="shrink-0 rounded-lg bg-brand px-3 py-2 text-xs font-medium text-white hover:bg-brand-dark disabled:opacity-40 transition"
          >
            {isPending ? "…" : "Run"}
          </button>
        </div>
        {isOpen && hasUsdc && (
          <div className="mt-3 text-xs text-slate-500">
            Pool: <span className="font-medium text-slate-700">{(Number(pool!.usdcBalance) / 1e6).toFixed(2)} USDC</span>
          </div>
        )}
      </div>

      {/* Settle Round */}
      <div className={`rounded-xl border p-5 ${isLocked ? "border-slate-200 bg-white shadow-sm" : "border-dashed border-slate-300 bg-slate-50"}`}>
        <div className="flex items-start justify-between gap-3">
          <div>
            <h3 className="font-semibold text-slate-700">Settle Round</h3>
            <p className="text-xs text-slate-400 mt-1 leading-relaxed">
              After admin runs the lottery draw, settle winnings and open the next round.
            </p>
            {isOpen && (
              <p className="mt-2 text-xs text-slate-400 bg-slate-100 rounded px-2 py-1">
                Waiting for pool to lock first.
              </p>
            )}
          </div>
          <button
            onClick={settleRound}
            disabled={!isLocked || isPending}
            className="shrink-0 rounded-lg bg-brand px-3 py-2 text-xs font-medium text-white hover:bg-brand-dark disabled:opacity-40 transition"
          >
            {isPending ? "…" : "Run"}
          </button>
        </div>
        {isLocked && (
          <div className="mt-3 text-xs text-slate-500">
            <span className="font-medium text-amber-600">{pool?.ticketCount ?? 0}</span> tickets in lottery
          </div>
        )}
      </div>
    </div>
  );
}
