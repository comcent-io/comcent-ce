// The organization the user last worked in, kept per browser. Signing in
// (the /app entry point) reopens it; the organization list only marks it.
// Storage can be unavailable (private windows, blocked site data), so every
// access is guarded: without it, sign-in just shows the list.

const KEY = 'selectedSubdomain';

export function getLastOrg(): string | null {
  try {
    return localStorage.getItem(KEY);
  } catch {
    return null;
  }
}

export function setLastOrg(subdomain: string) {
  try {
    localStorage.setItem(KEY, subdomain);
  } catch {
    // Not remembered; nothing else depends on it.
  }
}

type OrgChoice = {
  orgs: { subdomain: string }[];
  invites: unknown[];
};

/**
 * Where signing in should land: the last used org if the user still belongs
 * to it; their only org, when there's no invitation waiting to be seen; or
 * null for the organization list.
 */
export function orgToOpen({ orgs, invites }: OrgChoice, last: string | null): string | null {
  if (last && orgs.some((org) => org.subdomain === last)) return last;
  if (orgs.length === 1 && invites.length === 0) return orgs[0].subdomain;
  return null;
}
