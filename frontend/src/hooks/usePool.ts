import { useQuery } from "@tanstack/react-query";
import { useSuiClient, useCurrentAccount } from "@mysten/dapp-kit";
import { POOL_ID, PACKAGE_ID, MODULES, STATE_OPEN, STATE_LOCKED } from "@/lib/constants";
import type { PoolState, UserTicket } from "@/types";

/** Fetch and parse the shared Pool object. */
export function usePool() {
  const client = useSuiClient();
  return useQuery({
    queryKey: ["pool", POOL_ID],
    queryFn: async () => {
      const obj = await client.getObject({ id: POOL_ID, options: { showContent: true } });
      if (obj.data?.content?.dataType !== "moveObject") return null;
      const fields = obj.data.content.fields as Record<string, unknown>;
      return {
        round:          Number(fields.round),
        state:          Number(fields.state) === STATE_OPEN ? "OPEN" as PoolState : "LOCKED" as PoolState,
        usdcBalance:    BigInt(fields.usdc_balance as string),
        rewardBalance:  BigInt(fields.reward_balance as string),
        ticketCount:    Number((fields.invoice_numbers as string[]).length),
        roundTotal:     BigInt(fields.round_total as string),
      };
    },
    refetchInterval: 5_000,
  });
}

/** Fetch all PoolTickets owned by the connected wallet. */
export function useMyTickets() {
  const account = useCurrentAccount();
  const client  = useSuiClient();
  return useQuery({
    queryKey: ["tickets", account?.address],
    enabled: !!account?.address,
    queryFn: async () => {
      const res = await client.getOwnedObjects({
        owner: account!.address,
        filter: { StructType: `${PACKAGE_ID}::${MODULES.pool}::PoolTicket` },
        options: { showContent: true },
      });
      return res.data.map((item): UserTicket => {
        const f = (item.data?.content as { fields: Record<string, unknown> })?.fields ?? {};
        return {
          id:              item.data!.objectId,
          deposited:       BigInt(f.deposited as string),
          round:           Number(f.round),
          rewardCollected: Boolean(f.reward_collected),
        };
      });
    },
    refetchInterval: 5_000,
  });
}

/** Fetch total USDC balance for the connected wallet. */
export function useUsdcBalance() {
  const account = useCurrentAccount();
  const client  = useSuiClient();
  return useQuery({
    queryKey: ["usdc", account?.address],
    enabled: !!account?.address,
    queryFn: async () => {
      const coins = await client.getCoins({
        owner: account!.address,
        coinType: `${PACKAGE_ID}::${MODULES.usdc}::USDC`,
      });
      return coins.data.reduce((sum, c) => sum + BigInt(c.balance), 0n);
    },
    refetchInterval: 5_000,
  });
}
