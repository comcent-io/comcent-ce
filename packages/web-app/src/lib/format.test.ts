import { describe, expect, it } from 'vitest';
import {
  formatDate,
  formatDateTime,
  formatDuration,
  formatEnum,
  formatTableDate,
  formatTableDateTime,
  formatTime,
  toDate,
} from './format';

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

  it('writes the time of day', () => {
    expect(formatTime(new Date(2026, 8, 29, 9, 51))).toBe('9:51 am');
    expect(formatTime(new Date(2026, 8, 29, 21, 5))).toBe('9:05 pm');
    expect(formatTime(null, '-')).toBe('-');
  });

  it('writes a stored enum value as a label', () => {
    expect(formatEnum('ADMIN')).toBe('Admin');
    expect(formatEnum('IN_PROGRESS')).toBe('In progress');
    expect(formatEnum(null)).toBe('');
  });

  it('writes how long something lasted', () => {
    expect(formatDuration('2026-10-05T09:52:19Z', '2026-10-05T09:53:15Z')).toBe('0:56');
    expect(formatDuration('2026-10-05T09:00:00Z', '2026-10-05T09:12:05Z')).toBe('12:05');
    expect(formatDuration('2026-10-05T09:00:00Z', '2026-10-05T10:02:09Z')).toBe('1:02:09');
    expect(formatDuration('2026-10-05T09:00:00Z', null, '-')).toBe('-');
  });
});
