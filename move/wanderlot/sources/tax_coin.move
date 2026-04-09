/// TAX_COIN is the intermediate lottery-ticket currency.
/// Users exchange USDC → TAX_COIN (1:10), which funds the Treasury prize pool.
/// TAX_COIN is then spent to mint Invoice lottery tickets.
///
/// Extensions over the reference:
///   - buy_quota_return: same as buy_quota but returns the coin instead of
///     transferring it, so pool.move can receive it internally.
module wanderlot::tax_coin;

use sui::coin::{Self, Coin, TreasuryCap};
use sui::url;
use wanderlot::treasury::{Self, Treasury};
use wanderlot::usdc::USDC;

public struct TAX_COIN has drop {}

fun init(witness: TAX_COIN, ctx: &mut TxContext) {
    let (treasury_cap, metadata) = coin::create_currency<TAX_COIN>(
        witness,
        6,
        b"TAX",
        b"TAX_COIN",
        b"WanderLot lottery ticket currency",
        option::some(url::new_unsafe_from_bytes(
            b"https://cdn-icons-png.flaticon.com/512/8744/8744976.png"
        )),
        ctx,
    );
    transfer::public_freeze_object(metadata);
    // TreasuryCap stays private with deployer (not shared)
    transfer::public_transfer(treasury_cap, ctx.sender());
}

// ── Public (user-facing) ──────────────────────────────────────────────────────

/// Exchange USDC for TAX_COIN at a 1:10 ratio.
/// USDC is deposited into the Treasury prize pool.
/// TAX_COIN is transferred to ctx.sender().
#[allow(lint(self_transfer))]
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
