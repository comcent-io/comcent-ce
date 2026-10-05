import { describe, expect, it } from 'vitest';
import { formatDate, formatDateTime, formatTableDate, formatTableDateTime, toDate } from './format';

describe('toDate', () => {
  it('reads a timestamp without a zone as UTC', () => {
    expect(toDate('2026-09-29T04:21:00')?.toISOString()).toBe('2026-09-29T04:21:00.000Z');
    expect(toDate('2026-09-29T04:21:00Z')?.toISOString()).toBe('2026-09-29T04:21:00.000Z');
    expect(toDate('2026-09-29T09:51:00+05:30')?.toISOString()).toBe('2026-09-29T04:21:00.000Z');
  });

  it('reads a date on its own as that local calendar day', () => {
    const date = toDate('2026-09-28')!;
    expect([date.getFullYear(), date.getMonth(), date.getDate(), date.getHours()]).toEqual([
      2026, 8, 28, 0,
    ]);
  });

  it('gives null for nothing or nonsense', () => {
    for (const value of [null, undefined, '', 'not a date']) expect(toDate(value)).toBeNull();
  });
});

describe('dates for display', () => {
  it('uses the fallback when there is no date', () => {
    expect(formatDateTime(null, 'Not sent')).toBe('Not sent');
    expect(formatDate(undefined)).toBe('');
    expect(formatTableDateTime('')).toBe('');
  });

  it('writes the day, month and year', () => {
    expect(formatDate('2026-09-28')).toMatch(/28/);
    expect(formatDate('2026-09-28')).toMatch(/2026/);
    expect(formatDateTime('2026-09-29T04:21:00Z')).toMatch(/2026/);
  });

  it('writes the compact table stamp', () => {
    const local = new Date(2026, 8, 29, 9, 51);
    expect(formatTableDateTime(local)).toBe('2026/09/29 09:51 am');
    expect(formatTableDate(local)).toBe('2026/09/29');
  });
});
