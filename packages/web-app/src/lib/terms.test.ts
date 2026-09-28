import { describe, expect, it } from 'vitest';
import { termsToAccept, type SessionTerms } from './terms';

const terms = (acceptanceRequired: boolean): SessionTerms => ({
  termsUrl: 'https://terms.example.com/terms-of-use',
  privacyUrl: 'https://terms.example.com/privacy-policy',
  version: '2026-09-28',
  acceptanceRequired,
  previouslyAccepted: false,
});

describe('termsToAccept', () => {
  it('a deployment with no terms asks for nothing', () => {
    expect(termsToAccept(null)).toBeNull();
    expect(termsToAccept(undefined)).toBeNull();
  });

  it('terms the user has already accepted ask for nothing', () => {
    expect(termsToAccept(terms(false))).toBeNull();
  });

  it('terms the user has yet to accept are returned for the terms page', () => {
    expect(termsToAccept(terms(true))).toEqual(terms(true));
  });
});
