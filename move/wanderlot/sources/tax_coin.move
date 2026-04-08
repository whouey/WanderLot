/// TAX_COIN is the intermediate lottery-ticket currency.
/// Users exchange USDC → TAX_COIN (1:10), which funds the Treasury prize pool.
/// TAX_COIN is then spent to mint Invoice lottery tickets.
///
/// Extensions over the reference:
///   - buy_quota_return: same as buy_quota but returns the coin instead of
///     transferring it, so pool.move can receive it internally.
module wanderlot::tax_coin;

use sui::coin_registry;
use sui::coin::{Self, Coin, TreasuryCap};
use wanderlot::treasury::{Self, Treasury};
use wanderlot::usdc::USDC;

public struct TAX_COIN has drop {}

fun init(witness: TAX_COIN, ctx: &mut TxContext) {
    let (builder, treasury_cap) = coin_registry::new_currency_with_otw(
        witness,
        6,
        b"TAX".to_string(),
        b"TAX_COIN".to_string(),
        b"WanderLot lottery ticket currency".to_string(),
        b"https://cdn-icons-png.flaticon.com/512/8744/8744976.png".to_string(),
        ctx,
    );
    let metadata_cap = builder.finalize(ctx);
    transfer::public_transfer(metadata_cap, ctx.sender());
    // TreasuryCap stays private with deployer (not shared)
    // so only authorised callers can mint TAX_COIN
    transfer::public_transfer(treasury_cap, ctx.sender());
}

// ── Public (user-facing) ──────────────────────────────────────────────────────

/// Exchange USDC for TAX_COIN at a 1:10 ratio.
/// USDC is deposited into the Treasury prize pool.
/// TAX_COIN is transferred to ctx.sender().
public fun buy_quota(
    in_coin: Coin<USDC>,
    treasury_cap: &mut TreasuryCap<TAX_COIN>,
    treasury: &mut Treasury,
    ctx: &mut TxContext,
) {
    let out = buy_quota_internal(in_coin, treasury_cap, treasury, ctx);
    transfer::public_transfer(out, ctx.sender());
}

// ── Package-internal (pool.move uses this) ────────────────────────────────────

/// Same as buy_quota but RETURNS the TAX_COIN instead of transferring.
/// Called by pool::buy_tickets so the pool can hold the coin internally.
public(package) fun buy_quota_return(
    in_coin: Coin<USDC>,
    treasury_cap: &mut TreasuryCap<TAX_COIN>,
    treasury: &mut Treasury,
    ctx: &mut TxContext,
): Coin<TAX_COIN> {
    buy_quota_internal(in_coin, treasury_cap, treasury, ctx)
}

// ── Private ───────────────────────────────────────────────────────────────────

fun buy_quota_internal(
    in_coin: Coin<USDC>,
    treasury_cap: &mut TreasuryCap<TAX_COIN>,
    treasury: &mut Treasury,
    ctx: &mut TxContext,
): Coin<TAX_COIN> {
    let in_value = coin::value(&in_coin);
    let out_amount = in_value * 10; // 1 USDC → 10 TAX_COIN
    let out_coin = coin::mint<TAX_COIN>(treasury_cap, out_amount, ctx);
    treasury::input(treasury, in_coin, ctx);
    out_coin
}
