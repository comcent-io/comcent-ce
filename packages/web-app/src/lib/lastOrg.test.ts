import { describe, expect, it } from 'vitest';
import { orgToOpen } from './lastOrg';

const acme = { subdomain: 'acme' };
const northwind = { subdomain: 'northwind' };

describe('orgToOpen', () => {
  it('reopens the last used org', () => {
    expect(orgToOpen({ orgs: [acme, northwind], invites: [] }, 'northwind')).toBe('northwind');
  });

  it('shows the list when the last used org is no longer theirs', () => {
    expect(orgToOpen({ orgs: [acme, northwind], invites: [] }, 'gone')).toBeNull();
  });

  it('opens the only org when nothing was used before', () => {
    expect(orgToOpen({ orgs: [acme], invites: [] }, null)).toBe('acme');
  });

  it('shows the list when an invitation is waiting beside the only org', () => {
    expect(orgToOpen({ orgs: [acme], invites: [{}] }, null)).toBeNull();
  });

  it('shows the list with several orgs and none used before, or with none', () => {
    expect(orgToOpen({ orgs: [acme, northwind], invites: [] }, null)).toBeNull();
    expect(orgToOpen({ orgs: [], invites: [] }, 'acme')).toBeNull();
  });
});
