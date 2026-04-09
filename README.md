# WanderLot

> **Pool your luck. Share the reward.**

WanderLot is a shared lottery pool built on **Sui Move**. Instead of buying individual lottery tickets with high variance, users deposit USDC into a collective pool. The pool purchases Invoice lottery tickets on everyone's behalf. When any pool ticket wins, the prize is distributed proportionally — same expected value, dramatically lower variance.

---

## How It Works

### The Problem with Solo Play

In the base invoice lottery, each ticket gives a `1/N` chance of winning the entire prize.

- Win chance: **1 / 10,000 = 0.01%**
- If you win: take everything
- If you lose: USDC is gone

This is high-variance. Most players lose. The expected value is positive, but the experience feels like gambling.

### The WanderLot Solution

Users deposit into a shared pool. The pool buys 100+ tickets collectively. When any pool ticket wins, the reward is split by each depositor's share.

```
Alice  deposits  500 USDC  → 50% share
Bob    deposits  300 USDC  → 30% share
Carol  deposits  200 USDC  → 20% share
─────────────────────────────────────
Pool total: 1,000 USDC → 100 tickets

Lottery runs → Pool ticket #4077 wins → Prize: 8,000 USDC

Alice  receives  4,000 USDC  (50%)
Bob    receives  2,400 USDC  (30%)
Carol  receives  1,600 USDC  (20%)
```

- **Same expected value** as solo play
- **100× lower variance** (100 tickets vs 1)
- **Proportional, trustless distribution** — on-chain math, no intermediary

---

## Architecture

```
WanderLot/
├── move/
│   └── wanderlot/
│       ├── Move.toml
│       └── sources/
│           ├── usdc.move       # Fake USDC (test faucet)
│           ├── tax_coin.move   # Intermediate lottery currency (1 USDC → 10 TAX)
│           ├── treasury.move   # Prize vault (USDC flows in via TAX purchase)
│           ├── invoice.move    # Core lottery: ticket minting, random draw, claim
│           └── pool.move       # WanderLot pool: deposit, buy tickets, distribute
└── frontend/
    ├── package.json
    ├── next.config.ts
    ├── tailwind.config.ts
    └── src/
        ├── app/
        │   ├── layout.tsx      # Providers: SuiClient, WalletProvider, ReactQuery
        │   ├── page.tsx        # Home page shell
        │   └── globals.css
        ├── components/         # UI components (to be implemented)
        ├── hooks/
        │   └── usePool.ts      # usePool, useMyTickets, useUsdcBalance
        ├── lib/
        │   ├── constants.ts    # Package IDs, decimals, module names
        │   ├── sui.ts          # Transaction builders + query helpers
        │   └── utils.ts        # formatUsdc, parseUsdc, cn
        └── types/
            └── index.ts        # Shared TypeScript types
```

---

## Smart Contract Modules

### `usdc.move`
Fake USDC for testnet/devnet. TreasuryCap is shared — anyone can call `faucet()`.

### `tax_coin.move`
Intermediate currency. Users exchange USDC → TAX_COIN at **1:10 ratio**. USDC goes straight into the Treasury prize vault. TAX_COIN is then spent to mint Invoice tickets.

**Extension:** `buy_quota_return()` — same as `buy_quota` but returns the coin instead of transferring, so `pool.move` can hold it internally.

### `treasury.move`
Shared prize vault. USDC flows in via `input()`. Only `invoice::claim_lottery` can drain it via the `public(package)` `output()` function — no external bypass possible.

### `invoice.move`
Core lottery engine (adapted from `sui_workshop_3` reference).

| Function | Description |
|---|---|
| `init_invoice(tax, system, protocol, clock)` | Original: mint ticket, transfer to caller |
| `create_invoice(tax, system, protocol, clock)` | **New:** mint ticket, return it (pool use) |
| `claim_lottery(system, invoice, treasury, clock)` | Original: verify winner, pay caller |
| `claim_lottery_to_pool(...)` | **New:** verify winner, return coin (pool use) |
| `burn_invoice(invoice)` | **New:** destroy non-winning tickets after round |
| Getters | `invoice_number`, `invoice_timestamp`, `system_winner`, etc. |

### `pool.move`
The WanderLot core. One global shared `Pool` object, user-owned `PoolTicket` objects.

#### Round Lifecycle

```
STATE_OPEN
  │  deposit(pool, usdc) → PoolTicket
  │  withdraw_before_lottery(pool, ticket)   ← exit before commitment
  │
  ↓  buy_tickets(pool, system, treasury, clock)   [permissionless]
  │    ├─ Snapshot round_total
  │    ├─ USDC → TAX_COIN (all pooled USDC)
  │    ├─ TAX_COIN → Invoices (10 TAX per ticket)
  │    └─ Invoices stored as child objects (dynamic_object_field)
  │
STATE_LOCKED
  │  [admin runs invoice::lottery()]
  │
  ↓  settle_round(pool, system, treasury, clock)  [permissionless]
  │    ├─ Find winning invoice in pool
  │    ├─ Claim prize → pool.reward_balance
  │    ├─ Burn all non-winning invoices
  │    └─ Record outcome; advance round; → STATE_OPEN
  │
STATE_OPEN (next round)
  │  collect_reward(pool, &mut ticket)     ← claim proportional share
  │  burn_ticket(ticket)                   ← optional cleanup
```

#### Key Design Decisions

| Decision | Rationale |
|---|---|
| TreasuryCap stored inside Pool via `dynamic_object_field` | Enables permissionless `buy_tickets()` without deployer signing every tx |
| `mint_tax` / `burn_tax` isolated as private helpers | Avoids simultaneous mutable borrows on `pool.id` in the borrow checker |
| Non-winning invoices burned in `settle_round` | Prevents stale tickets from matching future lottery draws |
| `public(package)` on `treasury::output` | Only `invoice.move` can drain the prize; no external attack surface |
| `reward_collected` flag on PoolTicket | Prevents double-claiming; ticket can be burned after collection |

---

## Setup & Deployment

### Prerequisites

- [Sui CLI](https://docs.sui.io/guides/developer/getting-started/sui-install)
- Node.js ≥ 18
- A funded Sui testnet wallet (`sui client faucet`)

### 1. Deploy Move contracts

```bash
cd move/wanderlot
sui client publish --gas-budget 100000000
```

After publishing, note the following from the output:
- `Package ID`
- `Pool` shared object ID
- `Treasury` shared object ID
- `System` (invoice) shared object ID
- `TreasuryCap<USDC>` shared object ID
- `TreasuryCap<TAX_COIN>` owned object ID (in your wallet)
- `Admin` owned object ID (in your wallet)

### 2. One-time pool setup

```bash
# Store the TAX_COIN TreasuryCap inside the Pool
sui client call \
  --package <PACKAGE_ID> \
  --module pool \
  --function setup \
  --args <POOL_ID> <TAX_COIN_TREASURY_CAP_ID> \
  --gas-budget 10000000
```

### 3. Configure frontend

```bash
cd frontend
cp .env.example .env.local
# Edit .env.local with the IDs from step 1
npm install
npm run dev
```

---

## User Interaction Reference

| Action | Who | When |
|---|---|---|
| `usdc::faucet()` | User | Anytime — get test USDC |
| `pool::deposit()` | User | STATE_OPEN only |
| `pool::withdraw_before_lottery()` | User | STATE_OPEN, before buy_tickets |
| `pool::buy_tickets()` | Anyone | STATE_OPEN, pool has USDC |
| `invoice::lottery()` | Admin | After STATE_LOCKED |
| `pool::settle_round()` | Anyone | After lottery() runs |
| `pool::collect_reward()` | User | After round is settled |
| `pool::burn_ticket()` | User | After reward collected |

---

## Reference

This project extends [sui_workshop_3](https://github.com/Bermu-DAO/sui_workshop_3) by Bermu-DAO, adding:
- Return-based variants of `init_invoice` and `claim_lottery` for pool integration
- `burn_invoice` for post-round cleanup
- The entire `pool.move` module

---

## License

MIT
