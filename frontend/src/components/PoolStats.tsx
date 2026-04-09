"use client";

import { usePool } from "@/hooks/usePool";
import { USDC_SCALAR } from "@/lib/constants";

function fmt(raw: bigint): string {
  return (Number(raw) / USDC_SCALAR).toLocaleString("en-US", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
}

export function PoolStats() {
  const { data: pool, isLoading } = usePool();

  const stateCls =
    pool?.state === "OPEN"
      ? "bg-emerald-100 text-emerald-700"
      : "bg-amber-100 text-amber-700";

  return (
    <section className="grid grid-cols-2 md:grid-cols-4 gap-4">
      <Card
        label="Round"
        value={isLoading ? "—" : `#${pool?.round ?? 0}`}
      />
      <Card
        label="State"
        value={
          isLoading ? "—" : (
            <span className={`px-2 py-0.5 rounded-full text-xs font-semibold ${stateCls}`}>
              {pool?.state ?? "—"}
            </span>
          )
        }
      />
      <Card
        label="Pool Deposits"
        value={isLoading ? "—" : `${fmt(pool?.usdcBalance ?? 0n)} USDC`}
      />
      <Card
        label="Prize Balance"
        value={isLoading ? "—" : `${fmt(pool?.rewardBalance ?? 0n)} USDC`}
      />
    </section>
  );
}

function Card({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div className="rounded-xl border border-slate-200 bg-white p-5 shadow-sm">
      <p className="text-xs uppercase tracking-wide text-slate-400">{label}</p>
      <p className="mt-2 text-xl font-semibold text-slate-800">{value}</p>
    </div>
  );
}
