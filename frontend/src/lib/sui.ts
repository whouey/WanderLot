import { SuiClient, getFullnodeUrl } from "@mysten/sui/client";
import { Transaction } from "@mysten/sui/transactions";
import {
  PACKAGE_ID,
  POOL_ID,
  TREASURY_ID,
  SYSTEM_ID,
  USDC_CAP_ID,
  MODULES,
  USDC_SCALAR,
} from "./constants";

// ── Client ────────────────────────────────────────────────────────────────────

const network = (process.env.NEXT_PUBLIC_SUI_NETWORK ?? "testnet") as
  | "mainnet"
  | "testnet"
  | "devnet"
  | "localnet";

export const suiClient = new SuiClient({ url: getFullnodeUrl(network) });

// ── Transaction builders ──────────────────────────────────────────────────────
// Each function returns a Transaction (PTB) ready to be signed and executed
// via wallet.signAndExecuteTransaction() from @mysten/dapp-kit.

/**
 * Mint fake USDC to the caller's address.
 * @param amount human-readable USDC amount (e.g. 100 → 100_000_000 raw)
 * @param recipient wallet address
 */
export function buildFaucetTx(amount: number, recipient: string): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${PACKAGE_ID}::${MODULES.usdc}::faucet`,
    arguments: [
      tx.object(USDC_CAP_ID),
      tx.pure.u64(BigInt(Math.round(amount * USDC_SCALAR))),
      tx.pure.address(recipient),
    ],
  });
  return tx;
}

/**
 * Deposit USDC into the pool and receive a PoolTicket.
 * @param usdcCoinId object ID of a Coin<USDC> owned by the caller
 * @param amount raw USDC units to deposit (split from usdcCoinId if needed)
 * @param sender wallet address of the depositor (to receive the PoolTicket)
 */
export function buildDepositTx(usdcCoinId: string, amount: bigint, sender: string): Transaction {
  const tx = new Transaction();
  const [splitCoin] = tx.splitCoins(tx.object(usdcCoinId), [tx.pure.u64(amount)]);
  const ticket = tx.moveCall({
    target: `${PACKAGE_ID}::${MODULES.pool}::deposit`,
    arguments: [tx.object(POOL_ID), splitCoin],
  });
  tx.transferObjects([ticket], tx.pure.address(sender));
  return tx;
}

/**
 * Withdraw USDC deposit before tickets are bought (STATE_OPEN only).
 * @param ticketId object ID of the PoolTicket to burn
 */
export function buildWithdrawBeforeLotteryTx(ticketId: string): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${PACKAGE_ID}::${MODULES.pool}::withdraw_before_lottery`,
    arguments: [tx.object(POOL_ID), tx.object(ticketId)],
  });
  return tx;
}

/**
 * Convert all pooled USDC into Invoice lottery tickets.
 * Permissionless — anyone can call.
 */
export function buildBuyTicketsTx(): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${PACKAGE_ID}::${MODULES.pool}::buy_tickets`,
    arguments: [
      tx.object(POOL_ID),
      tx.object(SYSTEM_ID),
      tx.object(TREASURY_ID),
      tx.object("0x6"), // Clock object ID (always 0x6 on Sui)
    ],
  });
  return tx;
}

/**
 * Settle the current round after the admin has run lottery().
 * Permissionless — anyone can call.
 */
export function buildSettleRoundTx(): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${PACKAGE_ID}::${MODULES.pool}::settle_round`,
    arguments: [
      tx.object(POOL_ID),
      tx.object(SYSTEM_ID),
      tx.object(TREASURY_ID),
      tx.object("0x6"), // Clock
    ],
  });
  return tx;
}

/**
 * Collect proportional reward from a settled round.
 * @param ticketId object ID of the PoolTicket
 */
export function buildCollectRewardTx(ticketId: string): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${PACKAGE_ID}::${MODULES.pool}::collect_reward`,
    arguments: [tx.object(POOL_ID), tx.object(ticketId)],
  });
  return tx;
}

/**
 * Burn a used PoolTicket after reward has been collected.
 * @param ticketId object ID of the PoolTicket
 */
export function buildBurnTicketTx(ticketId: string): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${PACKAGE_ID}::${MODULES.pool}::burn_ticket`,
    arguments: [tx.object(ticketId)],
  });
  return tx;
}

// ── Query helpers ─────────────────────────────────────────────────────────────

/** Fetch the current Pool object fields. */
export async function fetchPool() {
  const obj = await suiClient.getObject({
    id: POOL_ID,
    options: { showContent: true },
  });
  return obj.data?.content;
}

/** Fetch all PoolTickets owned by an address. */
export async function fetchPoolTickets(owner: string) {
  const objects = await suiClient.getOwnedObjects({
    owner,
    filter: {
      StructType: `${PACKAGE_ID}::${MODULES.pool}::PoolTicket`,
    },
    options: { showContent: true },
  });
  return objects.data;
}

/** Fetch all Coin<USDC> owned by an address. */
export async function fetchUsdcCoins(owner: string) {
  return suiClient.getCoins({
    owner,
    coinType: `${PACKAGE_ID}::${MODULES.usdc}::USDC`,
  });
}
