/// Fake USDC for testing on devnet/testnet.
/// TreasuryCap is shared so anyone can call faucet().
module wanderlot::usdc;

use sui::coin_registry;
use sui::coin::{Self, TreasuryCap};

public struct USDC has drop {}

fun init(witness: USDC, ctx: &mut TxContext) {
    let (builder, treasury_cap) = coin_registry::new_currency_with_otw(
        witness,
        6,
        b"usdc".to_string(),
        b"USDC".to_string(),
        b"Fake USDC for WanderLot testing".to_string(),
        b"https://upload.wikimedia.org/wikipedia/commons/thumb/4/4a/Circle_USDC_Logo.svg/960px-Circle_USDC_Logo.svg.png".to_string(),
        ctx,
    );
    let metadata_cap = builder.finalize(ctx);
    transfer::public_transfer(metadata_cap, ctx.sender());
    // Share treasury cap so anyone can mint test USDC
    transfer::public_share_object(treasury_cap);
}

/// Mint `amount` test USDC to `recipient`.
/// amount is in raw units — 1_000_000 = 1.0 USDC (6 decimals).
public fun faucet(
    treasury_cap: &mut TreasuryCap<USDC>,
    amount: u64,
    recipient: address,
    ctx: &mut TxContext,
) {
    let coin = coin::mint(treasury_cap, amount, ctx);
    transfer::public_transfer(coin, recipient);
}
