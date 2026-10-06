// How a party on a call is shown: a member's SIP address
// ("maya@acme.comcent.io") by its username, a phone number as it is.

export function partyName(party: string | null | undefined, fallback = 'Unknown'): string {
  if (!party) return fallback;
  return party.includes('@') ? party.split('@')[0] : party;
}

/**
 * The other side of a call in the dialer, from SIP.js's `remoteIdentity`: the
 * display name the call came with if there is one, otherwise the number or
 * username from its address ("+14155550199@acme.comcent.io" is shown as
 * "+14155550199"). `detail` is that number or username when a display name is
 * shown above it.
 */
export function remoteParty(identity: { displayName?: string; uri: { aor: string } }): {
  name: string;
  detail: string;
} {
  let address = identity.uri.aor;
  try {
    address = decodeURIComponent(address);
  } catch {
    // Not percent-encoded after all; show it as it is.
  }
  const party = partyName(address);
  if (identity.displayName && identity.displayName !== party) {
    return { name: identity.displayName, detail: party };
  }
  return { name: party, detail: '' };
}

/** Whether the party is a phone number (the customer side), not a member. */
export function isPhoneParty(party: string | null | undefined): boolean {
  return !!party && /^\+?\d+$/.test(party);
}

/** Up to two letters for an avatar: "MA" for maya, "16" for +16505550188. */
export function partyInitials(party: string | null | undefined): string {
  const name = partyName(party, '?');
  return (name.startsWith('+') ? name.slice(1) : name).slice(0, 2).toUpperCase();
}
