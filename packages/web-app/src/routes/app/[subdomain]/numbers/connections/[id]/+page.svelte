<script lang="ts">
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import { page } from '$app/state';
  import { routeParam } from '$lib/routeParam';
  import toast from '$lib/toast';
  import Pill from '$lib/components/Pill.svelte';
  import {
    disconnect,
    disconnectPreview,
    listConnections,
    refreshNumbers,
    rotateCredentials,
    statusLabel,
    statusTone,
    type DisconnectPreview,
    type NumberState,
    type ProviderConnection,
  } from '$lib/providerConnections';

  const subdomain = routeParam('subdomain');
  const connectionId = routeParam('id');
  const basePath = `/app/${subdomain}`;

  let connection: ProviderConnection | null = $state(null);
  let numberStates: NumberState[] = $state([]);
  let preview = $state<DisconnectPreview | null>(null);

  // Derived here rather than in the template: a campaign holds the number with
  // a restricting foreign key so release refuses, while a flow only warns.
  let blockedNumbers = $derived(preview?.blocked ?? []);
  let warnOnlyNumbers = $derived(
    (preview?.inUse ?? []).filter((n: string) => !blockedNumbers.includes(n)),
  );

  let loading = $state(true);
  let checking = $state(false);
  let errorMessage = $state('');

  let showRotate = $state(false);
  let newKeySid = $state('');
  let newKeySecret = $state('');
  let rotating = $state(false);

  let showDisconnect = $state(false);
  let disconnectMode: 'release' | 'keep' | '' = $state('');
  let disconnecting = $state(false);

  let drifted = $derived(numberStates.filter((n) => n.state === 'drifted'));
  let missing = $derived(numberStates.filter((n) => n.state === 'missing'));

  onMount(load);

  async function load() {
    loading = true;
    const result = await listConnections(subdomain);
    loading = false;

    if (!result.ok) {
      errorMessage = result.error;
      return;
    }
    connection = result.data.providerConnections.find((c) => c.id === connectionId) ?? null;
    if (!connection) errorMessage = 'Connection not found';
  }

  async function check() {
    checking = true;
    errorMessage = '';
    const result = await refreshNumbers(subdomain, connectionId);
    checking = false;

    if (!result.ok) {
      errorMessage = result.error;
      return;
    }
    const states = result.data.numbers;
    numberStates = states;

    // Counted from the response, not from the `$:` values above: those are
    // recomputed on the next flush, so reading them here saw the *previous*
    // check and reported "everything matches" while rendering drift rows.
    const problems = states.filter((n) => n.state === 'drifted' || n.state === 'missing').length;

    if (problems === 0) toast.success('Everything matches Twilio');
    else toast(`${problems} number(s) differ from Twilio`, { icon: '⚠️' });
  }

  async function rotate() {
    rotating = true;
    errorMessage = '';
    const result = await rotateCredentials(subdomain, connectionId, {
      api_key_sid: newKeySid.trim(),
      api_key_secret: newKeySecret.trim(),
    });
    rotating = false;

    if (!result.ok) {
      errorMessage = result.error;
      return;
    }

    connection = result.data;
    newKeySid = '';
    newKeySecret = '';
    showRotate = false;
    toast.success('Credentials replaced');
  }

  async function openDisconnect() {
    const result = await disconnectPreview(subdomain, connectionId);
    if (!result.ok) {
      errorMessage = result.error;
      return;
    }
    preview = result.data;
    showDisconnect = true;
  }

  async function runDisconnect() {
    if (disconnectMode === '') return;
    disconnecting = true;

    const result = await disconnect(subdomain, connectionId, disconnectMode);
    disconnecting = false;

    if (!result.ok) {
      errorMessage = result.error;
      return;
    }

    const s = result.data;
    if (s.failed.length > 0) {
      // Reported rather than hidden: the customer needs to know which numbers
      // are still pointing at Comcent so they can fix them by hand.
      toast.error(`${s.failed.length} number(s) could not be restored — see details`);
      errorMessage =
        'Could not restore: ' + s.failed.map((f) => `${f.e164} (${f.error})`).join(', ');
      return;
    }

    toast.success(
      s.mode === 'release'
        ? `Disconnected. ${s.restored} number(s) restored in Twilio.`
        : 'Disconnected. Numbers left untouched in Twilio.',
    );
    await goto(`${basePath}/numbers`);
  }
</script>

<div class="p-4">
  <a href={`${basePath}/numbers`} class="text-sm text-blue-700 hover:underline dark:text-blue-400">
    ← Numbers
  </a>

  {#if loading}
    <p class="mt-4 text-gray-500 dark:text-gray-400">Loading…</p>
  {:else if !connection}
    <p class="mt-4 text-red-600">{errorMessage}</p>
  {:else}
    <div class="flex items-center gap-3 mt-2 mb-6">
      <h1 class="text-3xl font-bold dark:text-white">{connection.label}</h1>
      <Pill tone={statusTone(connection.status)}>{statusLabel(connection.status)}</Pill>
    </div>

    {#if errorMessage}
      <div
        class="mb-4 p-4 rounded-lg bg-red-50 text-red-800 dark:bg-red-900 dark:text-red-200 max-w-3xl"
        role="alert"
      >
        {errorMessage}
      </div>
    {/if}

    {#if connection.status === 'unmanaged'}
      <div
        class="mb-4 p-4 rounded-lg bg-amber-50 text-amber-900 dark:bg-amber-900 dark:text-amber-100 max-w-3xl text-sm"
      >
        <b>You asked us to stop managing this Twilio account.</b>
        <p class="mt-1">
          Your API key has been deleted, so Comcent can no longer see or change anything in Twilio.
          Your numbers are still routed here and calls still work — that runs over the SIP trunk,
          which does not need the key.
        </p>
        <p class="mt-2">
          Until you add a key, we cannot import numbers, check the setup against Twilio, or hand the
          numbers back. The trunk we created is still in your Twilio account.
        </p>
      </div>
    {/if}

    <div class="max-w-3xl grid gap-4">
      <!-- Account -->
      <section class="bg-white dark:bg-gray-800 rounded-lg shadow p-6">
        <h2 class="font-semibold mb-3 dark:text-white">Account</h2>
        <dl class="text-sm grid grid-cols-3 gap-y-2 text-gray-600 dark:text-gray-400">
          <dt>Provider</dt>
          <dd class="col-span-2 dark:text-gray-300">{connection.provider}</dd>
          <dt>Account SID</dt>
          <dd class="col-span-2 font-mono text-xs dark:text-gray-300">
            {connection.externalAccountSid}
          </dd>
          <dt>API key</dt>
          <dd class="col-span-2 dark:text-gray-300">
            {connection.credentialsHint ?? '—'}
            <span class="text-xs text-gray-500">(the secret is never shown)</span>
          </dd>
          <dt>Last verified</dt>
          <dd class="col-span-2 dark:text-gray-300">
            {connection.lastVerifiedAt ?? 'never'}
          </dd>
        </dl>
      </section>

      <!-- Credentials -->
      <section class="bg-white dark:bg-gray-800 rounded-lg shadow p-6">
        <h2 class="font-semibold mb-1 dark:text-white">Credentials</h2>
        <p class="text-sm text-gray-600 dark:text-gray-400 mb-3">
          {#if connection.status === 'unmanaged'}
            Add a key to let Comcent manage this account again. Nothing is re-provisioned — the
            existing trunk and numbers are picked back up exactly as they are.
          {:else}
            Replace these after regenerating the key in Twilio. Calls keep flowing either way;
            without a working key we simply cannot manage the account.
          {/if}
        </p>

        {#if showRotate}
          <div class="grid gap-3 max-w-md">
            <input
              bind:value={newKeySid}
              placeholder="New API key SID (SK…)"
              class="w-full p-2.5 text-sm rounded-lg border border-gray-300 bg-gray-50 dark:bg-gray-700 dark:border-gray-600 dark:text-white"
            />
            <input
              type="password"
              bind:value={newKeySecret}
              placeholder="New API key secret"
              class="w-full p-2.5 text-sm rounded-lg border border-gray-300 bg-gray-50 dark:bg-gray-700 dark:border-gray-600 dark:text-white"
            />
            <div class="flex gap-2">
              <button
                onclick={rotate}
                disabled={rotating || !newKeySid || !newKeySecret}
                class="text-white bg-blue-700 hover:bg-blue-800 disabled:opacity-50 rounded-lg text-sm px-4 py-2"
              >
                {rotating ? 'Checking…' : 'Replace'}
              </button>
              <button
                onclick={() => (showRotate = false)}
                class="text-gray-900 bg-white border border-gray-300 rounded-lg text-sm px-4 py-2 dark:bg-gray-800 dark:text-white dark:border-gray-600"
              >
                Cancel
              </button>
            </div>
            <p class="text-xs text-gray-500 dark:text-gray-400">
              Verified with Twilio before saving, so a wrong key cannot leave the connection worse
              than it is now.
            </p>
          </div>
        {:else}
          <button
            onclick={() => (showRotate = true)}
            class="text-gray-900 bg-white border border-gray-300 hover:bg-gray-100 rounded-lg text-sm px-4 py-2 dark:bg-gray-800 dark:text-white dark:border-gray-600"
          >
            {connection.status === 'unmanaged' ? 'Add an API key' : 'Replace credentials'}
          </button>
        {/if}
      </section>

      <!-- Numbers / drift -->
      <section class="bg-white dark:bg-gray-800 rounded-lg shadow p-6">
        <div class="flex items-center justify-between mb-1">
          <h2 class="font-semibold dark:text-white">Numbers</h2>
          {#if connection.status !== 'unmanaged'}
            <div class="flex gap-2">
              <a
                href={`${basePath}/numbers/connections/${connectionId}/import`}
                class="text-sm text-blue-700 hover:underline dark:text-blue-400"
              >
                Import more
              </a>
              <button
                onclick={check}
                disabled={checking}
                class="text-sm text-blue-700 hover:underline dark:text-blue-400 disabled:opacity-50"
              >
                {checking ? 'Checking…' : 'Check against Twilio'}
              </button>
            </div>
          {/if}
        </div>
        <p class="text-sm text-gray-600 dark:text-gray-400 mb-3">
          Compares the numbers we manage against Twilio. Only the ones we manage — a number you
          never imported is none of our business.
        </p>

        {#if numberStates.length === 0}
          <p class="text-sm text-gray-500 dark:text-gray-400">Not checked yet.</p>
        {:else}
          <ul class="text-sm space-y-1">
            {#each numberStates as n}
              <li>
                {#if n.state === 'ok'}
                  <span class="text-green-700 dark:text-green-400">✓ {n.e164}</span>
                {:else if n.state === 'drifted'}
                  <span class="text-amber-700 dark:text-amber-400">
                    ⚠ {n.e164} — changed in Twilio since we configured it
                  </span>
                {:else if n.state === 'missing'}
                  <span class="text-red-700 dark:text-red-400">
                    ✗ {n.e164} — no longer exists in Twilio
                  </span>
                {:else}
                  <span class="text-gray-600 dark:text-gray-400">{n.e164} — {n.error}</span>
                {/if}
              </li>
            {/each}
          </ul>
        {/if}
      </section>

      <!-- Danger zone -->
      <section
        class="bg-white dark:bg-gray-800 rounded-lg shadow p-6 border border-red-200 dark:border-red-900"
      >
        <h2 class="font-semibold mb-1 text-red-700 dark:text-red-400">Disconnect</h2>
        <p class="text-sm text-gray-600 dark:text-gray-400 mb-3">
          Importing a number moved it onto a Comcent trunk. You can hand those numbers back, or keep
          them running here but take back your API key.
        </p>

        {#if connection.status === 'unmanaged'}
          <p class="text-sm text-gray-600 dark:text-gray-400">
            Handing the numbers back means changing them in Twilio, which needs an API key. Add one
            above first. We have kept a record of how each number was configured before we touched
            it, so it can still be restored exactly.
          </p>
        {:else if !showDisconnect}
          <button
            onclick={openDisconnect}
            class="text-red-700 bg-white border border-red-300 hover:bg-red-50 rounded-lg text-sm px-4 py-2 dark:bg-gray-800 dark:border-red-800"
          >
            Disconnect…
          </button>
        {:else if preview}
          <div class="grid gap-3">
            <p class="text-sm dark:text-gray-300">
              This connection manages <b>{preview.numberCount}</b>
              number(s).
              {#if preview.restorable < preview.numberCount}
                <span class="text-amber-700 dark:text-amber-400">
                  {preview.numberCount - preview.restorable} have no recorded original configuration
                  and cannot be restored automatically.
                </span>
              {/if}
            </p>

            {#if blockedNumbers.length > 0}
              <div
                class="p-3 rounded bg-red-50 dark:bg-red-900 text-red-900 dark:text-red-100 text-sm"
              >
                <b>Used by a campaign:</b>
                {blockedNumbers.join(', ')}. Handing these back is blocked until they are detached
                from their campaign — otherwise the numbers would be removed from Twilio's side
                while Comcent still held them.
              </div>
            {/if}

            {#if warnOnlyNumbers.length > 0}
              <div
                class="p-3 rounded bg-amber-50 dark:bg-amber-900 text-amber-900 dark:text-amber-100 text-sm"
              >
                <b>In use right now:</b>
                {warnOnlyNumbers.join(', ')}. Disconnecting interrupts these.
              </div>
            {/if}

            <label class="flex items-start gap-2 text-sm dark:text-gray-300">
              <input type="radio" bind:group={disconnectMode} value="release" class="mt-1" />
              <span>
                <b>Disconnect and hand the numbers back</b>
                — we restore each number's original Twilio settings, delete the trunk we created, and
                remove the numbers from Comcent. Calls stop arriving here. Choose this if you are leaving.
              </span>
            </label>

            <label class="flex items-start gap-2 text-sm dark:text-gray-300">
              <input type="radio" bind:group={disconnectMode} value="keep" class="mt-1" />
              <span>
                <b>Stop managing this account, keep calls flowing</b>
                — we delete your API key and stop touching Twilio. Nothing changes in your Twilio account
                and your numbers keep ringing here, but we can no longer import numbers or repair the
                setup until you add a key again. Choose this if you would rather we did not hold a key.
              </span>
            </label>

            <div class="flex gap-2">
              <button
                onclick={runDisconnect}
                disabled={disconnectMode === '' || disconnecting}
                class="text-white bg-red-700 hover:bg-red-800 disabled:opacity-50 rounded-lg text-sm px-4 py-2"
              >
                {disconnecting ? 'Disconnecting…' : 'Disconnect'}
              </button>
              <button
                onclick={() => (showDisconnect = false)}
                class="text-gray-900 bg-white border border-gray-300 rounded-lg text-sm px-4 py-2 dark:bg-gray-800 dark:text-white dark:border-gray-600"
              >
                Cancel
              </button>
            </div>
          </div>
        {/if}
      </section>
    </div>
  {/if}
</div>
