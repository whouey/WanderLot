"use client";

import { useCurrentAccount, useSignAndExecuteTransaction } from "@mysten/dapp-kit";
import { usePool, useMyTickets, useUsdcBalance } from "@/hooks/usePool";
import {
  buildCollectRewardTx,
  buildWithdrawBeforeLotteryTx,
  buildBurnTicketTx,
} from "@/lib/sui";
import { USDC_SCALAR } from "@/lib/constants";
import type { UserTicket } from "@/types";

function fmt(raw: bigint): string {
  return (Number(raw) / USDC_SCALAR).toFixed(2);
}

export function MyTickets() {
  const account = useCurrentAccount();
  const { data: pool } = usePool();
  const { data: tickets, refetch: refetchTickets } = useMyTickets();
  const { refetch: refetchUsdc } = useUsdcBalance();
  const { mutate: sign, isPending } = useSignAndExecuteTransaction();

  if (!account) return null;
  if (!tickets?.length) {
    return (
      <div className="rounded-xl border border-dashed border-slate-300 bg-slate-50 p-6 text-center">
        <p className="text-slate-400 text-sm">You have no PoolTickets yet.</p>
      </div>
    );
  }

  function collectReward(ticket: UserTicket) {
    const tx = buildCollectRewardTx(ticket.id);
    sign({ transaction: tx }, { onSuccess: () => { refetchTickets(); refetchUsdc(); } });
  }

  function withdraw(ticket: UserTicket) {
    const tx = buildWithdrawBeforeLotteryTx(ticket.id);
    sign({ transaction: tx }, { onSuccess: () => { refetchTickets(); refetchUsdc(); } });
  }

  function burnTicket(ticket: UserTicket) {
    const tx = buildBurnTicketTx(ticket.id);
    sign({ transaction: tx }, { onSuccess: () => refetchTickets() });
  }

  const currentRound = pool?.round ?? 0;
  const isOpen = pool?.state === "OPEN";

  return (
    <div className="rounded-xl border border-slate-200 bg-white shadow-sm overflow-hidden">
      <div className="px-6 py-4 border-b border-slate-100">
        <h2 className="font-semibold text-slate-800 text-lg">My Pool Tickets</h2>
        <p className="text-xs text-slate-400 mt-0.5">{tickets.length} ticket{tickets.length !== 1 ? "s" : ""}</p>
      </div>
      <div className="divide-y divide-slate-100">
        {tickets.map((ticket) => {
          const isCurrentRound = ticket.round === currentRound;
          const isSettled = ticket.round < currentRound;
          const canWithdraw = isCurrentRound && isOpen && !isPending;
          const canCollect = isSettled && !ticket.rewardCollected && !isPending;
          const canBurn = isSettled && ticket.rewardCollected && !isPending;

          let statusLabel: React.ReactNode;
          if (isCurrentRound && isOpen) {
            statusLabel = <Badge color="blue">Active</Badge>;
          } else if (isCurrentRound && !isOpen) {
            statusLabel = <Badge color="amber">In Lottery</Badge>;
          } else if (!ticket.rewardCollected) {
            statusLabel = <Badge color="emerald">Reward Ready</Badge>;
          } else {
            statusLabel = <Badge color="slate">Done</Badge>;
          }

          return (
            <div key={ticket.id} className="px-6 py-4 flex items-center gap-4">
              <div className="flex-1 min-w-0">
                <p className="text-sm font-medium text-slate-700 truncate">
                  {fmt(ticket.deposited)} USDC &mdash; Round #{ticket.round}
                </p>
                <p className="text-xs text-slate-400 font-mono truncate mt-0.5">
                  {ticket.id.slice(0, 10)}…{ticket.id.slice(-6)}
                </p>
              </div>
              <div className="flex items-center gap-2 shrink-0">
                {statusLabel}
                {canWithdraw && (
                  <ActionButton onClick={() => withdraw(ticket)} variant="ghost">
                    Withdraw
                  </ActionButton>
                )}
                {canCollect && (
                  <ActionButton onClick={() => collectReward(ticket)} variant="primary">
                    Collect
                  </ActionButton>
                )}
                {canBurn && (
                  <ActionButton onClick={() => burnTicket(ticket)} variant="ghost">
                    Burn
                  </ActionButton>
                )}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}

function Badge({ color, children }: { color: "blue" | "amber" | "emerald" | "slate"; children: React.ReactNode }) {
  const cls: Record<string, string> = {
    blue:    "bg-blue-100 text-blue-700",
    amber:   "bg-amber-100 text-amber-700",
    emerald: "bg-emerald-100 text-emerald-700",
    slate:   "bg-slate-100 text-slate-500",
  };
  return (
    <span className={`px-2 py-0.5 rounded-full text-xs font-semibold ${cls[color]}`}>
      {children}
    </span>
  );
}

function ActionButton({
  onClick,
  variant,
  children,
}: {
  onClick: () => void;
  variant: "primary" | "ghost";
  children: React.ReactNode;
}) {
  const base = "text-xs font-medium px-3 py-1.5 rounded-lg transition";
  const cls =
    variant === "primary"
      ? `${base} bg-brand text-white hover:bg-brand-dark`
      : `${base} border border-slate-300 text-slate-600 hover:bg-slate-50`;
  return <button onClick={onClick} className={cls}>{children}</button>;
}
