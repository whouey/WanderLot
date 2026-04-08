/// The Treasury holds all USDC prize money.
/// USDC flows IN when users buy TAX_COIN (via tax_coin::buy_quota).
/// USDC flows OUT only via invoice::claim_lottery — enforced by public(package).
module wanderlot::treasury;

use sui::balance::{Self, Balance};
use sui::coin::{Self, Coin};
use wanderlot::usdc::USDC;

/// Shared object — one global prize vault.
public struct Treasury has key {
    id: UID,
    pool: Balance<USDC>,
}

fun init(ctx: &mut TxContext) {
    let treasury = Treasury {
        id: object::new(ctx),
        pool: balance::zero(),
    };
    transfer::share_object(treasury);
}

// ── Public ────────────────────────────────────────────────────────────────────

/// Deposit USDC into the prize pool.
/// Called by tax_coin::buy_quota every time a user buys TAX_COIN.
public fun input(treasury: &mut Treasury, coin: Coin<USDC>, _ctx: &mut TxContext) {
    balance::join(&mut treasury.pool, coin::into_balance(coin));
}

/// Read the current prize pool balance.
public fun balance(treasury: &Treasury): u64 {
    balance::value(&treasury.pool)
}

// ── Package-internal ──────────────────────────────────────────────────────────

/// Drain the entire prize pool and return it as a Coin.
/// Restricted to this package — only invoice::claim_lottery can call this,
/// preventing any external contract from siphoning the treasury.
public(package) fun output(treasury: &mut Treasury, ctx: &mut TxContext): Coin<USDC> {
    let amount = balance::value(&treasury.pool);
    coin::from_balance(balance::split(&mut treasury.pool, amount), ctx)
}
