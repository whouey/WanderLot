"use client";

import { useState } from "react";
import {
  useCurrentAccount,
  useSignAndExecuteTransaction,
} from "@mysten/dapp-kit";
import { usePool, useUsdcBalance } from "@/hooks/usePool";
import { buildDepositTx, buildFaucetTx } from "@/lib/sui";
import { USDC_SCALAR, TICKET_COST_USDC } from "@/lib/constants";

function fmt(raw: bigint): string {
  return (Number(raw) / USDC_SCALAR).toFixed(2);
}

export function DepositPanel() {
  const account = useCurrentAccount();
  const { data: pool } = usePool();
  const { data: usdcBalance, refetch: refetchUsdc } = useUsdcBalance();
  const { mutate: sign, isPending } = useSignAndExecuteTransaction();
  const [amount, setAmount] = useState("");
  const [txStatus, setTxStatus] = useState<"idle" | "ok" | "err">("idle");
  const [faucetPending, setFaucetPending] = useState(false);

  const isOpen = pool?.state === "OPEN";
  const numAmount = parseFloat(amount) || 0;
  const rawAmount = BigInt(Math.round(numAmount * USDC_SCALAR));
  const ticketsEstimate = Math.floor(numAmount / TICKET_COST_USDC);

  function handleDeposit() {
    if (!account || !usdcBalance || rawAmount === 0n) return;
    // Find the first USDC coin — the TX builder will split it
    // We need the actual coin object ID; use the hook's underlying client
    // For simplicity we re-query coins in sui.ts via fetchUsdcCoins
    import("@/lib/sui").then(({ fetchUsdcCoins }) =>
      fetchUsdcCoins(account.address).then(({ data: coins }) => {
        if (!coins.length) return;
        const coinId = coins[0].coinObjectId;
        const tx = buildDepositTx(coinId, rawAmount, account.address);
        sign(
          { transaction: tx },
          {
            onSuccess: () => { setTxStatus("ok"); setAmount(""); refetchUsdc(); },
            onError:   () => setTxStatus("err"),
          }
        );
      })
    );
  }

  function handleFaucet() {
    if (!account) return;
    setFaucetPending(true);
    import("@/lib/sui").then(({ buildFaucetTx: _buildFaucetTx }) => {
      const tx = buildFaucetTx(100, account.address);
      sign(
        { transaction: tx },
        {
          onSuccess: () => { refetchUsdc(); setFaucetPending(false); },
          onError:   () => setFaucetPending(false),
        }
      );
    });
  }

  if (!account) {
    return (
      <div className="rounded-xl border border-dashed border-slate-300 bg-slate-50 p-6 flex items-center justify-center min-h-[180px]">
        <p className="text-slate-400 text-sm">Connect your wallet to deposit.</p>
      </div>
    );
  }

  return (
    <div className="rounded-xl border border-slate-200 bg-white p-6 shadow-sm space-y-5">
      <div className="flex items-center justify-between">
        <h2 className="font-semibold text-slate-800 text-lg">Deposit USDC</h2>
        <button
          onClick={handleFaucet}
          disabled={faucetPending}
          className="text-xs text-brand border border-brand rounded-lg px-3 py-1 hover:bg-brand hover:text-white transition disabled:opacity-40"
        >
          {faucetPending ? "Minting…" : "Faucet +100"}
        </button>
      </div>

      <div className="text-xs text-slate-500">
        Balance: <span className="font-medium text-slate-700">{usdcBalance !== undefined ? `${fmt(usdcBalance)} USDC` : "—"}</span>
      </div>

      <div>
        <label className="block text-sm font-medium text-slate-600 mb-1">
          Amount (USDC)
        </label>
        <div className="flex gap-2">
          <input
            type="number"
            min="1"
            step="1"
            placeholder="0"
            value={amount}
            onChange={(e) => { setAmount(e.target.value); setTxStatus("idle"); }}
            disabled={!isOpen || isPending}
            className="flex-1 rounded-lg border border-slate-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-brand disabled:bg-slate-50"
          />
          <button
            onClick={handleDeposit}
            disabled={!isOpen || isPending || rawAmount === 0n || rawAmount > (usdcBalance ?? 0n)}
            className="rounded-lg bg-brand px-4 py-2 text-sm font-medium text-white hover:bg-brand-dark disabled:opacity-40 transition"
          >
            {isPending ? "Confirming…" : "Deposit"}
          </button>
        </div>
        {numAmount > 0 && (
          <p className="mt-1.5 text-xs text-slate-400">
            ≈ <span className="font-medium">{ticketsEstimate}</span> lottery ticket{ticketsEstimate !== 1 ? "s" : ""}
          </p>
        )}
      </div>

      {!isOpen && (
        <p className="text-xs text-amber-600 bg-amber-50 rounded-lg px-3 py-2">
          Pool is LOCKED — tickets are being bought. Wait for the round to settle.
        </p>
      )}

      {txStatus === "ok" && (
        <p className="text-xs text-emerald-600 bg-emerald-50 rounded-lg px-3 py-2">
          Deposit confirmed. Your PoolTicket is in your wallet.
        </p>
      )}
      {txStatus === "err" && (
        <p className="text-xs text-red-600 bg-red-50 rounded-lg px-3 py-2">
          Transaction failed. Check your balance and try again.
        </p>
      )}
    </div>
  );
}
