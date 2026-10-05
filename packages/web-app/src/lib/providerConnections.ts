import { deleteJson, getJson, postJson, putJson } from '$lib/http';

/**
 * Client for the provider-connections API.
 *
 * Note the asymmetry, which is a property of the app rather than this file:
 * responses come back camelCased (ComcentWeb.ControllerJson) while request
 * bodies are snake_cased on arrival (ComcentWeb.JsonDecoder). So interfaces
 * describing responses use camelCase and request bodies use snake_case.
 *
 * Credentials are never returned by the server. A connection carries only
 * `credentials_hint` — the last four characters of the key SID — which is
 * enough to tell two keys apart when rotating and useless to anyone else.
 */
export interface ProviderConnection {
  id: string;
  provider: string;
  authMethod: string;
  label: string;
  externalAccountSid: string;
  /**
   * 'unmanaged' = the customer asked us to stop managing the account. We hold
   * no credentials, but their numbers are still routed through the trunk we
   * built, so this is a live connection we simply cannot administer.
   */
  status: 'active' | 'invalid_credentials' | 'revoked' | 'unmanaged';
  lastVerifiedAt: string | null;
  metadata: Record<string, unknown>;
  credentialsHint: string | null;
}

/**
 * A number as it exists in the provider account right now.
 *
 * Fetched live rather than from a cached inventory, so the list is always what
 * Twilio actually has. `importable` and `reason` are decided server-side so the
 * two views cannot disagree about why a number can't be taken.
 */
export interface AvailableNumber {
  providerSid: string;
  e164: string;
  friendlyName: string | null;
  capabilities: { voice?: boolean; sms?: boolean; mms?: boolean; fax?: boolean };
  trunkSid: string | null;
  importable: boolean;
  reason: string | null;
}

export interface ImportResult {
  providerSid: string;
  ok: boolean;
  e164?: string;
  error?: string;
}

const base = (subdomain: string) => `/api/v2/${subdomain}/provider-connections`;

export function listConnections(subdomain: string) {
  return getJson<{ providerConnections: ProviderConnection[] }>(base(subdomain));
}

export function createConnection(
  subdomain: string,
  // Request bodies stay snake_case. The server snake_cases incoming keys
  // (ComcentWeb.JsonDecoder) so either would work, but matching what the
  // controller actually reads keeps the two sides legible together.
  body: {
    external_account_sid: string;
    api_key_sid: string;
    api_key_secret: string;
    label?: string;
  },
) {
  return postJson<ProviderConnection>(base(subdomain), body);
}

export function rotateCredentials(
  subdomain: string,
  id: string,
  body: { api_key_sid: string; api_key_secret: string },
) {
  return putJson<ProviderConnection>(`${base(subdomain)}/${id}/credentials`, body);
}

export function verifyConnection(subdomain: string, id: string) {
  return postJson<ProviderConnection>(`${base(subdomain)}/${id}/verify`, {});
}

export function listAvailableNumbers(subdomain: string, id: string) {
  return getJson<{ numbers: AvailableNumber[] }>(`${base(subdomain)}/${id}/available-numbers`);
}

/**
 * `confirmTrunkMove` is required when a number already sits on another trunk.
 * Twilio moves it silently, so the customer has to say yes explicitly.
 */
export function importNumbers(
  subdomain: string,
  id: string,
  providerSids: string[],
  confirmTrunkMove = false,
) {
  return postJson<{ results: ImportResult[] }>(`${base(subdomain)}/${id}/import-numbers`, {
    provider_sids: providerSids,
    confirm_trunk_move: confirmTrunkMove,
  });
}

/**
 * Imports one number at a time, reporting each result as it lands.
 *
 * Each number costs roughly three seconds of Twilio round-trips, so importing
 * a batch in a single request leaves the page silent for half a minute and
 * looking hung. Sequencing the calls client-side is what lets the UI say which
 * number it is on and show failures as they happen rather than all at the end.
 *
 * Sequential, never parallel: the first import creates the shared SIP trunk,
 * and provisioning re-reads the connection each time to pick it up. Firing
 * these concurrently would race that read and build a trunk per number.
 */
export async function importNumbersSequentially(
  subdomain: string,
  id: string,
  providerSids: string[],
  confirmTrunkMove: boolean,
  onResult: (result: ImportResult, done: number) => void,
): Promise<ImportResult[]> {
  const results: ImportResult[] = [];

  for (const sid of providerSids) {
    const response = await importNumbers(subdomain, id, [sid], confirmTrunkMove);

    // A transport-level failure is reported against this number and the batch
    // carries on: one bad number must not abandon the rest.
    const result: ImportResult = response.ok
      ? // The endpoint answers with a list even for a single number.
        (response.data.results?.[0] ?? {
          providerSid: sid,
          ok: false,
          error: 'No result returned',
        })
      : { providerSid: sid, ok: false, error: response.error };

    results.push(result);
    onResult(result, results.length);
  }

  return results;
}

export interface DisconnectPreview {
  connectionId: string;
  label: string;
  numberCount: number;
  numbers: string[];
  /** Numbers attached to a live queue, campaign or flow — disconnecting interrupts these. */
  inUse: string[];
  /** Held by a campaign FK: release refuses until these are detached. */
  blocked: string[];
  restorable: number;
}

export interface DisconnectSummary {
  mode: 'release' | 'keep';
  numbers: number;
  restored: number;
  failed: { e164: string; ok: boolean; error?: string }[];
}

export interface NumberState {
  e164: string;
  state: 'ok' | 'drifted' | 'missing' | 'error';
  fields?: { field: string; expected: string; actual: string }[];
  error?: string;
}

export function disconnectPreview(subdomain: string, id: string) {
  return getJson<DisconnectPreview>(`${base(subdomain)}/${id}/disconnect-preview`);
}

export function refreshNumbers(subdomain: string, id: string) {
  return postJson<{ numbers: NumberState[] }>(`${base(subdomain)}/${id}/refresh-numbers`, {});
}

/**
 * `mode` is required and deliberately has no default.
 *
 * `release` restores each number's original provider configuration and removes
 * Comcent's records. `keep` leaves the provider untouched and deactivates ours.
 * These are different intentions, so the caller must say which.
 */
export function disconnect(subdomain: string, id: string, mode: 'release' | 'keep') {
  return deleteJson<DisconnectSummary>(`${base(subdomain)}/${id}?mode=${mode}`);
}

/** Human-readable status, so the badge and any prose stay in step. */
export function statusLabel(status: ProviderConnection['status']): string {
  switch (status) {
    case 'active':
      return 'Connected';
    case 'invalid_credentials':
      return 'Credentials rejected';
    case 'revoked':
      return 'Access revoked';
    case 'unmanaged':
      return 'Not managed';
    default:
      return status;
  }
}

export function statusClass(status: ProviderConnection['status']): string {
  switch (status) {
    case 'active':
      return 'bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-300';
    case 'invalid_credentials':
    case 'revoked':
      return 'bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-300';
    case 'unmanaged':
      // Amber, not red: nothing is broken, but we cannot act on it.
      return 'bg-amber-100 text-amber-800 dark:bg-amber-900 dark:text-amber-200';
    default:
      return 'bg-gray-100 text-gray-800 dark:bg-gray-700 dark:text-gray-300';
  }
}
