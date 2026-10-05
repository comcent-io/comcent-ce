// How a party on a call is shown: a member's SIP address
// ("maya@acme.comcent.io") by its username, a phone number as it is.

export function partyName(party: string | null | undefined, fallback = 'Unknown'): string {
  if (!party) return fallback;
  return party.includes('@') ? party.split('@')[0] : party;
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
