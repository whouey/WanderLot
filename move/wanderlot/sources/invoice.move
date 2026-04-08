/// Core lottery engine.
/// An Invoice is a lottery ticket — each one gets a unique sequential number.
/// The admin draws a random winner; the holder of the matching Invoice claims
/// the entire Treasury prize.
///
/// Extensions over the reference:
///   - create_invoice        : returns Invoice instead of transferring (individual pool use)
///   - register_invoice      : consumes TAX_COIN, returns (number, timestamp), NO object created
///                             — used by pool so it never needs to hold Invoice objects
///   - claim_lottery_to_pool : returns Coin<USDC> instead of transferring (object-holding flow)
///   - claim_by_number       : claim by stored (number, timestamp) — used by pool
///   - burn_invoice          : destroys a non-winning invoice
///   - Getter functions for private fields (frontend / pool queries)
module wanderlot::invoice;

use sui::clock::{Self, Clock};
use sui::random::{Self, Random};
use std::string::String;
use sui::coin::{Self, Coin};
use sui::balance::{Self, Balance};
use wanderlot::tax_coin::TAX_COIN;
use wanderlot::usdc::USDC;
use wanderlot::treasury::{Self, Treasury};

// ── Errors ────────────────────────────────────────────────────────────────────
const EExpired: u64 = 0;      // invoice created after the lottery ran
const EWrongWinner: u64 = 1;  // invoice number does not match the winner

// ── Structs ───────────────────────────────────────────────────────────────────

/// Capability that gates the lottery() function. Held by the deployer.
public struct Admin has key, store {
    id: UID,
}

/// A single lottery ticket. invoice_number is the ticket number.
public struct Invoice has key, store {
    id: UID,
    protocol: String,    // label (e.g. "WanderLot")
    amount: u64,         // TAX_COIN deposited to create this invoice
    timestamp: u64,      // ms timestamp at creation
    invoice_number: u64, // sequential ticket number (1, 2, 3, …)
}

/// Global lottery state — shared object.
public struct System has key, store {
    id: UID,
    count: u64,                // total invoices ever created
    tax_value: u64,            // reference cost per ticket (informational)
    balance: Balance<TAX_COIN>,// accumulated TAX_COIN from all ticket purchases
    timestamp: u64,            // timestamp of the last lottery draw
    winner: u64,               // winning invoice_number from last draw
    counter: u64,              // resets to 0 after each draw
}

// ── Init ──────────────────────────────────────────────────────────────────────

fun init(ctx: &mut TxContext) {
    let system = System {
        id: object::new(ctx),
        count: 0,
        tax_value: 100,
        balance: balance::zero(),
        timestamp: 0,
        winner: 0,
        counter: 0,
    };
    let admin = Admin { id: object::new(ctx) };
    transfer::share_object(system);
    transfer::public_transfer(admin, ctx.sender());
}

// ── Lottery draw ──────────────────────────────────────────────────────────────

/// Draw a random winner from all invoices ever created.
/// Only the Admin capability holder can call this.
#[allow(lint(public_random))]
public fun lottery(
    _admin: &Admin,
    system: &mut System,
    random: &Random,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let mut generator = random::new_generator(random, ctx);
    system.winner = generator.generate_u64_in_range(1, system.count);
    system.timestamp = clock::timestamp_ms(clock);
    system.counter = 0;
}

// ── Invoice creation — individual user flow ───────────────────────────────────

/// Standard path: create an invoice and transfer it to the caller.
#[allow(lint(self_transfer))]
public fun init_invoice(
    tax: Coin<TAX_COIN>,
    system: &mut System,
    protocol: String,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let invoice = create_invoice_internal(tax, system, protocol, clock, ctx);
    transfer::public_transfer(invoice, ctx.sender());
}

/// Returns the Invoice object (used if caller needs to hold it themselves).
public fun create_invoice(
    tax: Coin<TAX_COIN>,
    system: &mut System,
    protocol: String,
    clock: &Clock,
    ctx: &mut TxContext,
): Invoice {
    create_invoice_internal(tax, system, protocol, clock, ctx)
}

fun create_invoice_internal(
    tax: Coin<TAX_COIN>,
    system: &mut System,
    protocol: String,
    clock: &Clock,
    ctx: &mut TxContext,
): Invoice {
    let amount    = coin::value(&tax);
    let timestamp = clock::timestamp_ms(clock);
    system.count  = system.count + 1;
    balance::join(&mut system.balance, coin::into_balance(tax));
    Invoice {
        id: object::new(ctx),
        protocol,
        amount,
        timestamp,
        invoice_number: system.count,
    }
}

// ── Invoice registration — pool flow (no Sui object created) ─────────────────

/// Pool path: consume TAX_COIN, register a ticket number in the System,
/// and return (invoice_number, timestamp) WITHOUT creating a Sui object.
///
/// This lets the pool record lottery tickets in a plain Table instead of
/// storing Invoice objects as dynamic fields — avoiding Sui v1.42 restrictions
/// on freshly-minted objects inside shared-object transactions.
public(package) fun register_invoice(
    tax: Coin<TAX_COIN>,
    system: &mut System,
    clock: &Clock,
): (u64, u64) {
    let timestamp = clock::timestamp_ms(clock);
    system.count  = system.count + 1;
    balance::join(&mut system.balance, coin::into_balance(tax));
    (system.count, timestamp)
}

// ── Lottery claim — individual path ──────────────────────────────────────────

/// Standard path: verify winner, drain Treasury, transfer prize to caller.
#[allow(lint(self_transfer))]
public fun claim_lottery(
    system: &mut System,
    invoice: Invoice,
    treasury: &mut Treasury,
    _clock: &Clock,
    ctx: &mut TxContext,
) {
    let prize = claim_with_invoice(system, invoice, treasury, ctx);
    transfer::public_transfer(prize, ctx.sender());
}

/// Returns the prize Coin instead of transferring (if caller wants to handle it).
public fun claim_lottery_to_pool(
    system: &mut System,
    invoice: Invoice,
    treasury: &mut Treasury,
    _clock: &Clock,
    ctx: &mut TxContext,
): Coin<USDC> {
    claim_with_invoice(system, invoice, treasury, ctx)
}

fun claim_with_invoice(
    system: &System,
    invoice: Invoice,
    treasury: &mut Treasury,
    ctx: &mut TxContext,
): Coin<USDC> {
    assert!(invoice.timestamp <= system.timestamp, EExpired);
    assert!(invoice.invoice_number == system.winner, EWrongWinner);
    let prize = treasury::output(treasury, ctx);
    burn_invoice_internal(invoice);
    prize
}

// ── Lottery claim — pool path (no Invoice object needed) ─────────────────────

/// Pool path: claim prize using a stored (invoice_number, invoice_timestamp).
/// Verifies the same conditions as claim_lottery without requiring the object.
/// Only callable within this package so the pool contract is the sole caller.
public(package) fun claim_by_number(
    system: &System,
    invoice_number: u64,
    invoice_timestamp: u64,
    treasury: &mut Treasury,
    ctx: &mut TxContext,
): Coin<USDC> {
    assert!(invoice_timestamp <= system.timestamp, EExpired);
    assert!(invoice_number == system.winner, EWrongWinner);
    treasury::output(treasury, ctx)
}

// ── Invoice cleanup ───────────────────────────────────────────────────────────

/// Destroy an Invoice object (e.g. after round ends without winning).
public fun burn_invoice(invoice: Invoice) {
    burn_invoice_internal(invoice);
}

fun burn_invoice_internal(invoice: Invoice) {
    let Invoice { id, protocol: _, amount: _, timestamp: _, invoice_number: _ } = invoice;
    object::delete(id);
}

// ── Getters ───────────────────────────────────────────────────────────────────

public fun invoice_number(invoice: &Invoice): u64   { invoice.invoice_number }
public fun invoice_timestamp(invoice: &Invoice): u64 { invoice.timestamp }
public fun invoice_amount(invoice: &Invoice): u64   { invoice.amount }
public fun invoice_protocol(invoice: &Invoice): String { invoice.protocol }

public fun system_winner(system: &System): u64    { system.winner }
public fun system_count(system: &System): u64     { system.count }
public fun system_timestamp(system: &System): u64 { system.timestamp }
