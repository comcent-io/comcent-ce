import { describe, expect, it } from 'vitest';
import { remoteParty } from './party';

const identity = (aor: string, displayName = '') => ({ displayName, uri: { aor } });

describe('remoteParty', () => {
  it('shows a dialed number without the SIP domain', () => {
    expect(remoteParty(identity('+14155550199@acme.comcent.io'))).toEqual({
      name: '+14155550199',
      detail: '',
    });
  });

  it('shows a member by username', () => {
    expect(remoteParty(identity('maya@acme.comcent.io')).name).toBe('maya');
  });

  it('shows the plus sign of an encoded number', () => {
    expect(remoteParty(identity('%2B14155550199@acme.comcent.io')).name).toBe('+14155550199');
  });

  it('puts the number under a display name', () => {
    expect(remoteParty(identity('+14155550199@acme.comcent.io', 'Jordan Lee'))).toEqual({
      name: 'Jordan Lee',
      detail: '+14155550199',
    });
  });

  it('does not repeat a display name that is just the number', () => {
    expect(remoteParty(identity('+14155550199@198.51.100.7', '+14155550199'))).toEqual({
      name: '+14155550199',
      detail: '',
    });
  });
});
