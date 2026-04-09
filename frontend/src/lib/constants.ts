// ── On-chain addresses (populated from .env.local after deploy) ───────────────

export const PACKAGE_ID   = process.env.NEXT_PUBLIC_PACKAGE_ID   ?? "";
export const POOL_ID      = process.env.NEXT_PUBLIC_POOL_ID      ?? "";
export const TREASURY_ID  = process.env.NEXT_PUBLIC_TREASURY_ID  ?? "";
export const SYSTEM_ID    = process.env.NEXT_PUBLIC_INVOICE_SYSTEM_ID ?? "";
export const USDC_CAP_ID  = process.env.NEXT_PUBLIC_USDC_TREASURY_CAP_ID ?? "";

// ── Coin decimals ─────────────────────────────────────────────────────────────

export const USDC_DECIMALS    = 6;
export const TAX_COIN_DECIMALS = 6;

/// Multiply a human-readable USDC amount by this to get raw units.
/// e.g. 1 USDC → 1_000_000 raw units
export const USDC_SCALAR = 10 ** USDC_DECIMALS;

// ── Pool mechanics ────────────────────────────────────────────────────────────

/// Raw TAX_COIN units required per lottery ticket (mirrors pool.move constant)
export const TICKET_PRICE_TAX = 10_000_000n; // 10 TAX_COIN

/// USDC cost per ticket (1 USDC = 10 TAX_COIN = 1 ticket)
export const TICKET_COST_USDC = 1; // human-readable USDC

// ── Pool states ───────────────────────────────────────────────────────────────

export const STATE_OPEN   = 0;
export const STATE_LOCKED = 1;

// ── Module names ──────────────────────────────────────────────────────────────

export const MODULES = {
  usdc:     "usdc",
  tax_coin: "tax_coin",
  treasury: "treasury",
  invoice:  "invoice",
  pool:     "pool",
} as const;
