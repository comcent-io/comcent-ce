import { convertWalletBalanceToDollars, convertDollarsToWalletBalance } from './money.js';

describe('money', () => {
  describe('convertWalletBalanceToDollars', () => {
    it('should convert properly ', () => {
      expect(convertWalletBalanceToDollars(BigInt(1000000))).toBe(1);
      expect(convertWalletBalanceToDollars(BigInt(10000000))).toBe(10);
      expect(convertWalletBalanceToDollars(BigInt(1231))).toBe(0.001231);
      expect(convertWalletBalanceToDollars(BigInt(1_231123))).toBe(1.231123);
      expect(convertWalletBalanceToDollars(BigInt(7_948_349_299_234893))).toBe(
        7_948_349_299.234893,
      );
    });
  });

  describe('convertDollarsToWalletBalance', () => {
    it('should convert properly ', () => {
      expect(convertDollarsToWalletBalance(1)).toBe(BigInt(1000000));
      expect(convertDollarsToWalletBalance(10)).toBe(BigInt(10000000));
      expect(convertDollarsToWalletBalance(1.2342342341)).toBe(BigInt(1234234));
    });
  });
});
