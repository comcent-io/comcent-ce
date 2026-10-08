import { describe, expect, it } from 'vitest';
import { labelKey, selectionChanged } from './labelFilter';

describe('labelKey', () => {
  it('uses the id when there is one', () => {
    expect(labelKey({ id: 7, name: 'Billing' })).toBe('7');
  });

  it('falls back to the name', () => {
    expect(labelKey({ name: 'Refund' })).toBe('Refund');
  });
});

describe('selectionChanged', () => {
  it('is false when nothing is ticked and nothing is applied', () => {
    expect(selectionChanged([], [])).toBe(false);
  });

  it('is false when the ticked labels are the applied ones, in any order', () => {
    expect(selectionChanged(['Refund', 'Billing'], ['Billing', 'Refund'])).toBe(false);
  });

  it('is true when a label is ticked with nothing applied', () => {
    expect(selectionChanged(['Billing'], [])).toBe(true);
  });

  it('is true when every applied label is unticked', () => {
    expect(selectionChanged([], ['Billing', 'Refund'])).toBe(true);
  });

  it('is true when one applied label is swapped for another', () => {
    expect(selectionChanged(['Billing', 'Shipping'], ['Billing', 'Refund'])).toBe(true);
  });

  it('is true when one of the applied labels is unticked', () => {
    expect(selectionChanged(['Billing'], ['Billing', 'Refund'])).toBe(true);
  });
});
