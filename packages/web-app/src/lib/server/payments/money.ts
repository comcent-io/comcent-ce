const MONEY_UNIT = 1_000_000;

export function convertWalletBalanceToDollars(walletBalance: bigint): number {
  return Number(Number(walletBalance) / MONEY_UNIT);
}

export function convertDollarsToWalletBalance(dollars: number): bigint {
  return BigInt(Math.round(dollars * MONEY_UNIT));
}
