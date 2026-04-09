/// Fake USDC for testing on devnet/testnet.
/// TreasuryCap is shared so anyone can call faucet().
module wanderlot::usdc;

use sui::coin::{Self, TreasuryCap};
use sui::url;

public struct USDC has drop {}

fun init(witness: USDC, ctx: &mut TxContext) {
    let (treasury_cap, metadata) = coin::create_currency<USDC>(
        witness,
        6,
        b"USDC",
        b"USDC",
        b"Fake USDC for WanderLot testing",
        option::some(url::new_unsafe_from_bytes(
            b"https://upload.wikimedia.org/wikipedia/commons/thumb/4/4a/Circle_USDC_Logo.svg/960px-Circle_USDC_Logo.svg.png"
        )),
        ctx,
    );
    transfer::public_freeze_object(metadata);
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
