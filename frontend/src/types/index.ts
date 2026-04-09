// ── On-chain object shapes (as returned by suiClient.getObject) ───────────────

export interface PoolFields {
  round:           string;
  state:           number;
  round_total:     string;
  invoice_numbers: string[];
}

export interface PoolTicketFields {
  deposited:         string;
  round:             string;
  reward_collected:  boolean;
}

export interface InvoiceSystemFields {
  count:     string;
  tax_value: string;
  timestamp: string;
  winner:    string;
  counter:   string;
}

export interface TreasuryFields {
  pool: { value: string }; // Balance<USDC>
}

// ── UI state types ────────────────────────────────────────────────────────────

export type PoolState = "OPEN" | "LOCKED";

export interface RoundOutcome {
  round:        number;
  reward:       bigint; // raw USDC units
  totalDeposit: bigint; // raw USDC units
  won:          boolean;
}

export interface UserTicket {
  id:               string;
  deposited:        bigint;
  round:            number;
  rewardCollected:  boolean;
  /** Estimated reward based on round outcome (undefined if round not settled) */
  estimatedReward?: bigint;
}
