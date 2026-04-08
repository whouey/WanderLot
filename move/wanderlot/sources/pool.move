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
///   STATE_LOCKED → pool holds ticket records, waiting for admin lottery()
///       ↓ settle_round() called (permissionless, after lottery runs)
///   STATE_OPEN   → new round; previous depositors can collect_reward()
///
/// ── Invoice ownership design ───────────────────────────────────────────────
///
///   The pool uses invoice::register_invoice() which consumes TAX_COIN and
///   records the ticket in the System WITHOUT creating a Sui Invoice object.
///   The pool tracks (invoice_number → timestamp) in a plain Table<u64, u64>.
///   On settle_round(), invoice::claim_by_number() is used to prove ownership.
///   This avoids dynamic_object_field child-object restrictions in Sui v1.42.
///
/// ── Setup (one-time after publish) ────────────────────────────────────────
///
///   Call setup(pool, treasury_cap_tax) once after publishing to store the
///   TreasuryCap<TAX_COIN> inside the Pool. This enables permissionless
///   ticket purchases — no deployer signature required.
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
use wanderlot::invoice::{Self, System as InvoiceSystem};

// ── Constants ─────────────────────────────────────────────────────────────────

const STATE_OPEN:   u8 = 0; // accepting deposits; tickets can be bought
const STATE_LOCKED: u8 = 1; // tickets bought; awaiting lottery + settlement

/// Cost per lottery ticket in raw TAX_COIN units.
/// 10 TAX_COIN × 10^6 (6 decimals) = 10_000_000 raw units per ticket.
/// With 1 USDC → 10 TAX_COIN, each ticket costs 1 USDC equivalent.
const TICKET_PRICE_TAX: u64 = 10_000_000;

/// Dynamic-field key for the stored TreasuryCap<TAX_COIN>
const TAX_CAP_KEY: vector<u8> = b"tax_cap";

// ── Errors ────────────────────────────────────────────────────────────────────
const EDepositsLocked:     u64 = 0;
const ENoDeposits:         u64 = 1;
const EAlreadyClaimed:     u64 = 2;
const ERoundNotSettled:    u64 = 3;
const ETreasuryCapSet:     u64 = 4;
const ETreasuryCapMissing: u64 = 5;
const EWrongRound:         u64 = 6;
const ELotteryNotRun:      u64 = 7;

// ── Structs ───────────────────────────────────────────────────────────────────

/// Shared object — one global pool.
public struct Pool has key {
    id: UID,

    // ── Round tracking ────────────────────────────────────────────────────
    round: u64,
    state: u8,

    // ── Balances ──────────────────────────────────────────────────────────
    /// USDC deposited this round (drained when buy_tickets is called)
    usdc_balance: Balance<USDC>,
    /// USDC prize winnings awaiting proportional distribution
    reward_balance: Balance<USDC>,

    // ── Ticket tracking (no Sui objects — just numbers + timestamps) ──────
    /// invoice_number → timestamp for each ticket registered this round
    invoice_records: Table<u64, u64>,
    /// Ordered list of invoice numbers for winner search
    invoice_numbers: vector<u64>,
    /// Snapshot of total deposited at buy_tickets time
    round_total: u64,

    // ── Historical data for reward calculation ────────────────────────────
    round_rewards: Table<u64, u64>, // round → prize amount (0 if lost)
    round_totals:  Table<u64, u64>, // round → total deposited
}

/// Owned by the depositor — proof of their stake in a given round.
public struct PoolTicket has key, store {
    id: UID,
    deposited:        u64,
    round:            u64,
    reward_collected: bool,
}

// ── Init ──────────────────────────────────────────────────────────────────────

fun init(ctx: &mut TxContext) {
    let pool = Pool {
        id: object::new(ctx),
        round: 0,
        state: STATE_OPEN,
        usdc_balance:    balance::zero(),
        reward_balance:  balance::zero(),
        invoice_records: table::new(ctx),
        invoice_numbers: vector::empty(),
        round_total: 0,
        round_rewards: table::new(ctx),
        round_totals:  table::new(ctx),
    };
    transfer::share_object(pool);
}

// ── One-time setup ────────────────────────────────────────────────────────────

/// Store TAX_COIN TreasuryCap inside the Pool so buy_tickets() is permissionless.
/// Call once after publish.
public fun setup(
    pool: &mut Pool,
    treasury_cap: TreasuryCap<TAX_COIN>,
    _ctx: &mut TxContext,
) {
    assert!(!dof::exists_(&pool.id, TAX_CAP_KEY), ETreasuryCapSet);
    dof::add(&mut pool.id, TAX_CAP_KEY, treasury_cap);
}

// ── Phase 1: Deposit ──────────────────────────────────────────────────────────

/// Deposit USDC into the pool. Returns a PoolTicket proving your stake.
/// Only valid while pool is STATE_OPEN.
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
#[allow(lint(self_transfer))]
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

/// Convert all pooled USDC into lottery ticket records.
/// Uses register_invoice() — no Invoice Sui objects are created.
/// Permissionless — any address can call this.
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

    pool.round_total = total_usdc;

    let usdc_coin = coin::from_balance(
        balance::split(&mut pool.usdc_balance, total_usdc), ctx
    );

    // USDC → TAX_COIN (pool's stored TreasuryCap; USDC goes to Treasury)
    let mut tax_balance = mint_tax(pool, usdc_coin, treasury, ctx);

    // TAX_COIN → ticket records (no Sui objects created in this loop)
    while (balance::value(&tax_balance) >= TICKET_PRICE_TAX) {
        let ticket_tax = coin::from_balance(
            balance::split(&mut tax_balance, TICKET_PRICE_TAX), ctx
        );
        let (num, ts) = invoice::register_invoice(ticket_tax, system, clock);
        table::add(&mut pool.invoice_records, num, ts);
        vector::push_back(&mut pool.invoice_numbers, num);
    };

    // Burn leftover TAX_COIN (less than one ticket's worth)
    if (balance::value(&tax_balance) > 0) {
        burn_tax(pool, coin::from_balance(tax_balance, ctx));
    } else {
        balance::destroy_zero(tax_balance);
    };

    pool.state = STATE_LOCKED;
}

// ── Phase 3: Settle round ─────────────────────────────────────────────────────

/// After admin calls invoice::lottery(), call this to check if pool won,
/// claim prize, record outcome, and open the next round.
/// Permissionless — any address can call this.
public fun settle_round(
    pool: &mut Pool,
    system: &mut InvoiceSystem,
    treasury: &mut Treasury,
    _clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(pool.state == STATE_LOCKED, ERoundNotSettled);
    assert!(invoice::system_timestamp(system) > 0, ELotteryNotRun);

    let winner     = invoice::system_winner(system);
    let lottery_ts = invoice::system_timestamp(system);
    let mut reward = 0u64;

    // Check if pool holds the winning ticket
    if (table::contains(&pool.invoice_records, winner)) {
        let inv_ts = *table::borrow(&pool.invoice_records, winner);
        // Validate the ticket was created before the lottery ran
        if (inv_ts <= lottery_ts) {
            let prize = invoice::claim_by_number(
                system, winner, inv_ts, treasury, ctx
            );
            reward = coin::value(&prize);
            balance::join(&mut pool.reward_balance, coin::into_balance(prize));
        };
    };

    // Clean up invoice records for this round
    while (!vector::is_empty(&pool.invoice_numbers)) {
        let num = vector::pop_back(&mut pool.invoice_numbers);
        if (table::contains(&pool.invoice_records, num)) {
            table::remove(&mut pool.invoice_records, num);
        };
    };

    // Record round outcome and advance
    table::add(&mut pool.round_rewards, pool.round, reward);
    table::add(&mut pool.round_totals,  pool.round, pool.round_total);

    pool.round_total = 0;
    pool.round       = pool.round + 1;
    pool.state       = STATE_OPEN;
}

// ── Phase 4: Collect reward ───────────────────────────────────────────────────

/// Collect proportional reward share after the round is settled.
/// reward = (deposited / round_total) × round_prize
#[allow(lint(self_transfer))]
public fun collect_reward(
    pool: &mut Pool,
    ticket: &mut PoolTicket,
    ctx: &mut TxContext,
) {
    assert!(!ticket.reward_collected, EAlreadyClaimed);
    assert!(
        table::contains(&pool.round_rewards, ticket.round),
        ERoundNotSettled,
    );

    let round_reward = *table::borrow(&pool.round_rewards, ticket.round);
    let round_total  = *table::borrow(&pool.round_totals,  ticket.round);

    if (round_reward > 0 && round_total > 0) {
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

/// Destroy a fully-used PoolTicket.
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

public fun ticket_deposited(t: &PoolTicket): u64        { t.deposited }
public fun ticket_round(t: &PoolTicket): u64            { t.round }
public fun ticket_reward_collected(t: &PoolTicket): bool { t.reward_collected }

public fun round_outcome(pool: &Pool, round: u64): (u64, u64) {
    (
        *table::borrow(&pool.round_rewards, round),
        *table::borrow(&pool.round_totals,  round),
    )
}

// ── Private helpers ───────────────────────────────────────────────────────────

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

fun burn_tax(pool: &mut Pool, tax: Coin<TAX_COIN>) {
    let cap = dof::borrow_mut<vector<u8>, TreasuryCap<TAX_COIN>>(
        &mut pool.id, TAX_CAP_KEY
    );
    coin::burn(cap, tax);
}
