/// WanderLot shared lottery pool.
///
/// Instead of buying individual lottery tickets, users deposit USDC into this
/// shared pool. The pool buys Invoice tickets collectively. If any pool ticket
/// wins, the USDC prize is distributed proportionally to all depositors.
///
/// This reduces variance while preserving the same expected value as solo play.
///
/// ── Round lifecycle ────────────────────────────────────────────────────────
///
///   STATE_OPEN   → anyone deposits USDC, receives a PoolTicket
///       ↓ buy_tickets() called (permissionless)
///   STATE_LOCKED → pool owns invoices, waiting for admin to run lottery()
///       ↓ settle_round() called (permissionless, after lottery runs)
///   STATE_OPEN   → new round begins; previous depositors can collect_reward()
///
/// ── Setup (one-time after publish) ────────────────────────────────────────
///
///   The deployer must call setup(pool, treasury_cap_tax) once to store the
///   TAX_COIN TreasuryCap inside the Pool, enabling permissionless ticket
///   purchases without the deployer signing every transaction.
///
module wanderlot::pool;

use sui::balance::{Self, Balance};
use sui::coin::{Self, Coin, TreasuryCap};
use sui::clock::Clock;
use sui::table::{Self, Table};
use sui::dynamic_object_field as dof;
use wanderlot::usdc::USDC;
use wanderlot::tax_coin::{Self, TAX_COIN};
use wanderlot::treasury::Treasury;
use wanderlot::invoice::{Self, Invoice, System as InvoiceSystem};

// ── Constants ─────────────────────────────────────────────────────────────────

/// Pool lifecycle states
const STATE_OPEN:   u8 = 0; // accepting deposits; tickets can be bought
const STATE_LOCKED: u8 = 1; // tickets bought; awaiting lottery + settlement

/// Cost per lottery ticket in raw TAX_COIN units.
/// 10 TAX_COIN × 10^6 (6 decimals) = 10_000_000 raw units per ticket.
/// With 1 USDC → 10 TAX_COIN, each ticket costs 1 USDC equivalent.
const TICKET_PRICE_TAX: u64 = 10_000_000;

/// Dynamic-field key for the stored TreasuryCap<TAX_COIN>
const TAX_CAP_KEY: vector<u8> = b"tax_cap";

// ── Errors ────────────────────────────────────────────────────────────────────
const EDepositsLocked:      u64 = 0; // buy_tickets already called this round
const ENoDeposits:          u64 = 1; // pool has no USDC to buy tickets with
const EAlreadyClaimed:      u64 = 2; // ticket reward already collected
const ERoundNotSettled:     u64 = 3; // settle_round not yet called for this round
const ETreasuryCapSet:      u64 = 4; // setup() already called
const ETreasuryCapMissing:  u64 = 5; // setup() not yet called
const EWrongRound:          u64 = 6; // ticket belongs to a different round
const ELotteryNotRun:       u64 = 7; // lottery() has not been drawn yet

// ── Structs ───────────────────────────────────────────────────────────────────

/// Shared object — one global pool.
public struct Pool has key {
    id: UID,

    // ── Round tracking ────────────────────────────────────────────────────
    /// Current round number (increments after each settlement)
    round: u64,
    /// Pool state: STATE_OPEN or STATE_LOCKED
    state: u8,

    // ── Balances ──────────────────────────────────────────────────────────
    /// USDC deposited this round (drained when buy_tickets is called)
    usdc_balance: Balance<USDC>,
    /// USDC prize winnings awaiting proportional distribution
    reward_balance: Balance<USDC>,

    // ── Invoice tracking ──────────────────────────────────────────────────
    /// Invoice numbers owned by the pool in the current round
    invoice_numbers: vector<u64>,
    /// Snapshot of total deposited at the time buy_tickets() was called
    round_total: u64,

    // ── Historical data for reward calculation ────────────────────────────
    /// round → prize amount won (0 if pool lost that round)
    round_rewards: Table<u64, u64>,
    /// round → total USDC deposited when tickets were bought
    round_totals:  Table<u64, u64>,
}

/// Owned by the depositor — proof of their stake in a given round.
public struct PoolTicket has key, store {
    id: UID,
    /// USDC deposited (raw units, 6 decimals)
    deposited: u64,
    /// Round this ticket was issued for
    round: u64,
    /// Prevents double-claiming rewards
    reward_collected: bool,
}

// ── Init ──────────────────────────────────────────────────────────────────────

fun init(ctx: &mut TxContext) {
    let pool = Pool {
        id: object::new(ctx),
        round: 0,
        state: STATE_OPEN,
        usdc_balance: balance::zero(),
        reward_balance: balance::zero(),
        invoice_numbers: vector::empty(),
        round_total: 0,
        round_rewards: table::new(ctx),
        round_totals:  table::new(ctx),
    };
    transfer::share_object(pool);
}

// ── One-time setup ────────────────────────────────────────────────────────────

/// Store the TAX_COIN TreasuryCap inside the Pool so buy_tickets() is
/// permissionless. Must be called once by the deployer after publish.
public fun setup(
    pool: &mut Pool,
    treasury_cap: TreasuryCap<TAX_COIN>,
    _ctx: &mut TxContext,
) {
    assert!(!dof::exists_(&pool.id, TAX_CAP_KEY), ETreasuryCapSet);
    dof::add(&mut pool.id, TAX_CAP_KEY, treasury_cap);
}

// ── Phase 1: Deposit ──────────────────────────────────────────────────────────

/// Deposit USDC into the pool and receive a PoolTicket proving your stake.
/// Only valid while the pool is STATE_OPEN (before buy_tickets is called).
public fun deposit(
    pool: &mut Pool,
    usdc: Coin<USDC>,
    ctx: &mut TxContext,
): PoolTicket {
    assert!(pool.state == STATE_OPEN, EDepositsLocked);
    let amount = coin::value(&usdc);
    assert!(amount > 0, ENoDeposits);
    balance::join(&mut pool.usdc_balance, coin::into_balance(usdc));
    PoolTicket {
        id: object::new(ctx),
        deposited: amount,
        round: pool.round,
        reward_collected: false,
    }
}

/// Cancel a deposit and recover USDC before tickets are bought.
/// Burns the PoolTicket.
public fun withdraw_before_lottery(
    pool: &mut Pool,
    ticket: PoolTicket,
    ctx: &mut TxContext,
) {
    assert!(pool.state == STATE_OPEN, EDepositsLocked);
    assert!(ticket.round == pool.round, EWrongRound);
    let amount = ticket.deposited;
    let payout = coin::from_balance(
        balance::split(&mut pool.usdc_balance, amount), ctx
    );
    transfer::public_transfer(payout, ctx.sender());
    let PoolTicket { id, deposited: _, round: _, reward_collected: _ } = ticket;
    object::delete(id);
}

// ── Phase 2: Buy tickets ──────────────────────────────────────────────────────

/// Convert all pooled USDC into Invoice lottery tickets and lock the round.
/// Permissionless — any address (bot, keeper, or user) can call this.
///
/// Flow:
///   1. Snapshot pool.round_total
///   2. Drain pool.usdc_balance → USDC coin
///   3. USDC → TAX_COIN (1:10 via pool's stored TreasuryCap; USDC → Treasury)
///   4. Split TAX_COIN into TICKET_PRICE_TAX chunks → one Invoice per chunk
///   5. Store each Invoice as a child object of the pool (dynamic_object_field)
///   6. Burn leftover TAX_COIN (< one ticket's worth)
///   7. Transition to STATE_LOCKED
public fun buy_tickets(
    pool: &mut Pool,
    system: &mut InvoiceSystem,
    treasury: &mut Treasury,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(pool.state == STATE_OPEN, EDepositsLocked);
    assert!(dof::exists_(&pool.id, TAX_CAP_KEY), ETreasuryCapMissing);
    let total_usdc = balance::value(&pool.usdc_balance);
    assert!(total_usdc > 0, ENoDeposits);

    // Snapshot total for proportional reward calculation later
    pool.round_total = total_usdc;

    // Drain all USDC from pool
    let usdc_coin = coin::from_balance(
        balance::split(&mut pool.usdc_balance, total_usdc), ctx
    );

    // Step 1: USDC → TAX_COIN
    // We separate this into a helper to avoid simultaneous borrow on pool.id
    let mut tax_balance = mint_tax(pool, usdc_coin, treasury, ctx);

    // Step 2: TAX_COIN → Invoices (one per TICKET_PRICE_TAX units)
    while (balance::value(&tax_balance) >= TICKET_PRICE_TAX) {
        let ticket_tax = coin::from_balance(
            balance::split(&mut tax_balance, TICKET_PRICE_TAX), ctx
        );
        let invoice = invoice::create_invoice(
            ticket_tax, system, b"WanderLot".to_string(), clock, ctx
        );
        let num = invoice::invoice_number(&invoice);
        vector::push_back(&mut pool.invoice_numbers, num);
        dof::add(&mut pool.id, num, invoice);
    };

    // Step 3: Burn leftover TAX_COIN (less than one ticket's worth)
    if (balance::value(&tax_balance) > 0) {
        burn_tax(pool, coin::from_balance(tax_balance, ctx));
    } else {
        balance::destroy_zero(tax_balance);
    };

    pool.state = STATE_LOCKED;
}

// ── Phase 3: Settle round ─────────────────────────────────────────────────────

/// After the admin has called invoice::lottery(), call this to:
///   1. Check if any pool invoice won
///   2. If so, claim the Treasury prize into pool.reward_balance
///   3. Burn all remaining (non-winning) invoices so they can't be replayed
///   4. Record round outcome and advance to the next round
///
/// Permissionless — any address can call this.
public fun settle_round(
    pool: &mut Pool,
    system: &mut InvoiceSystem,
    treasury: &mut Treasury,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(pool.state == STATE_LOCKED, ERoundNotSettled);
    // Ensure lottery has been run at least once
    assert!(invoice::system_timestamp(system) > 0, ELotteryNotRun);

    let winner      = invoice::system_winner(system);
    let lottery_ts  = invoice::system_timestamp(system);
    let mut reward  = 0u64;

    // Process every invoice the pool holds: claim the winner, burn the rest
    while (!vector::is_empty(&pool.invoice_numbers)) {
        let num = vector::pop_back(&mut pool.invoice_numbers);
        if (dof::exists_<u64>(&pool.id, num)) {
            let inv: Invoice = dof::remove(&mut pool.id, num);
            if (num == winner && invoice::invoice_timestamp(&inv) <= lottery_ts) {
                // This invoice is the winner — claim the prize
                let prize = invoice::claim_lottery_to_pool(
                    system, inv, treasury, clock, ctx
                );
                reward = coin::value(&prize);
                balance::join(
                    &mut pool.reward_balance,
                    coin::into_balance(prize),
                );
            } else {
                // Non-winner or stale — burn it to prevent future misuse
                invoice::burn_invoice(inv);
            };
        };
    };

    // Record round outcome for PoolTicket holders to query later
    table::add(&mut pool.round_rewards, pool.round, reward);
    table::add(&mut pool.round_totals,  pool.round, pool.round_total);

    // Reset and open the next round
    pool.round_total = 0;
    pool.round       = pool.round + 1;
    pool.state       = STATE_OPEN;
}

// ── Phase 4: Collect reward ───────────────────────────────────────────────────

/// Collect proportional reward share after the pool's round has been settled.
///
/// reward = (ticket.deposited / round_total) × round_prize
///
/// The ticket's reward_collected flag is set to true; call burn_ticket()
/// afterward if you want to clean up the owned object.
public fun collect_reward(
    pool: &mut Pool,
    ticket: &mut PoolTicket,
    ctx: &mut TxContext,
) {
    assert!(!ticket.reward_collected, EAlreadyClaimed);
    // Round must be settled (pool.round has advanced past ticket.round)
    assert!(
        table::contains(&pool.round_rewards, ticket.round),
        ERoundNotSettled,
    );

    let round_reward = *table::borrow(&pool.round_rewards, ticket.round);
    let round_total  = *table::borrow(&pool.round_totals,  ticket.round);

    if (round_reward > 0 && round_total > 0) {
        // Integer-safe proportional calculation
        let payout_amount = (
            (ticket.deposited as u128) * (round_reward as u128) / (round_total as u128)
        ) as u64;
        if (payout_amount > 0) {
            let payout = coin::from_balance(
                balance::split(&mut pool.reward_balance, payout_amount), ctx
            );
            transfer::public_transfer(payout, ctx.sender());
        };
    };

    ticket.reward_collected = true;
}

/// Destroy a fully-used PoolTicket (reward already collected).
public fun burn_ticket(ticket: PoolTicket) {
    let PoolTicket { id, deposited: _, round: _, reward_collected: _ } = ticket;
    object::delete(id);
}

// ── View functions ────────────────────────────────────────────────────────────

public fun pool_round(pool: &Pool): u64          { pool.round }
public fun pool_state(pool: &Pool): u8           { pool.state }
public fun pool_usdc_balance(pool: &Pool): u64   { balance::value(&pool.usdc_balance) }
public fun pool_reward_balance(pool: &Pool): u64 { balance::value(&pool.reward_balance) }
public fun pool_ticket_count(pool: &Pool): u64   { vector::length(&pool.invoice_numbers) }
public fun pool_round_total(pool: &Pool): u64    { pool.round_total }

public fun ticket_deposited(t: &PoolTicket): u64       { t.deposited }
public fun ticket_round(t: &PoolTicket): u64           { t.round }
public fun ticket_reward_collected(t: &PoolTicket): bool { t.reward_collected }

/// Returns (reward, total_deposited) for a settled round. Aborts if not settled.
public fun round_outcome(pool: &Pool, round: u64): (u64, u64) {
    (
        *table::borrow(&pool.round_rewards, round),
        *table::borrow(&pool.round_totals,  round),
    )
}

// ── Private helpers ───────────────────────────────────────────────────────────

/// Isolated helper: borrows pool.id to mint TAX_COIN, then releases the borrow.
/// Keeps the borrow scope from pool.id narrow so the caller can re-borrow it
/// for dof::add in the ticket-creation loop.
fun mint_tax(
    pool: &mut Pool,
    usdc: Coin<USDC>,
    treasury: &mut Treasury,
    ctx: &mut TxContext,
): Balance<TAX_COIN> {
    let cap = dof::borrow_mut<vector<u8>, TreasuryCap<TAX_COIN>>(
        &mut pool.id, TAX_CAP_KEY
    );
    let tax = tax_coin::buy_quota_return(usdc, cap, treasury, ctx);
    coin::into_balance(tax)
}

/// Isolated helper: borrows pool.id to burn leftover TAX_COIN.
fun burn_tax(pool: &mut Pool, tax: Coin<TAX_COIN>) {
    let cap = dof::borrow_mut<vector<u8>, TreasuryCap<TAX_COIN>>(
        &mut pool.id, TAX_CAP_KEY
    );
    coin::burn(cap, tax);
}
