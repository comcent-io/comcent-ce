// How the app shows dates and times. Pages use these rather than
// their own toLocaleString / moment calls, so the same thing reads the same
// everywhere.

import moment from 'moment-timezone';

export type DateInput = string | number | Date | null | undefined;

const DATE_ONLY = /^\d{4}-\d{2}-\d{2}$/;
const HAS_ZONE = /(Z|[+-]\d{2}:?\d{2})$/i;

/**
 * A timestamp from the API as a Date. Some columns are Postgres timestamps
 * without a zone and come back without one; they are UTC. A date on its own
 * ("2026-09-28") is a calendar day, so it is read as local midnight, not UTC
 * midnight (which is the day before west of UTC).
 */
export function toDate(value: DateInput): Date | null {
  if (value === null || value === undefined || value === '') return null;
  if (value instanceof Date) return isNaN(value.getTime()) ? null : value;
  if (typeof value === 'number') return new Date(value);

  const text = value.trim();
  let date: Date;
  if (DATE_ONLY.test(text)) {
    const [year, month, day] = text.split('-').map(Number);
    date = new Date(year, month - 1, day);
  } else {
    date = new Date(HAS_ZONE.test(text) ? text : `${text}Z`);
  }
  return isNaN(date.getTime()) ? null : date;
}

/** "29 Sept 2026, 9:51 am", in the viewer's timezone; `fallback` when empty. */
export function formatDateTime(value: DateInput, fallback = ''): string {
  const date = toDate(value);
  if (!date) return fallback;
  return date.toLocaleString(undefined, {
    day: 'numeric',
    month: 'short',
    year: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  });
}

/** "29 Sept 2026", in the viewer's timezone; `fallback` when empty. */
export function formatDate(value: DateInput, fallback = ''): string {
  const date = toDate(value);
  if (!date) return fallback;
  return date.toLocaleDateString(undefined, { day: 'numeric', month: 'short', year: 'numeric' });
}

/**
 * The compact stamp tables use, "2026/09/29 09:51 am": fixed width, and
 * sorts the way it reads.
 */
export function formatTableDateTime(value: DateInput, fallback = ''): string {
  const date = toDate(value);
  return date ? moment(date).format('YYYY/MM/DD hh:mm a') : fallback;
}

/** The compact table date, "2026/09/29". */
export function formatTableDate(value: DateInput, fallback = ''): string {
  const date = toDate(value);
  return date ? moment(date).format('YYYY/MM/DD') : fallback;
}
