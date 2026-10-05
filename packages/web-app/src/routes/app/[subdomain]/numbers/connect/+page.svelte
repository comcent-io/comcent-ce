<script lang="ts">
  import { goto } from '$app/navigation';
  import { page } from '$app/state';
  import { routeParam } from '$lib/routeParam';
  import toast from '$lib/toast';
  import { createConnection } from '$lib/providerConnections';

  const subdomain = routeParam('subdomain');
  const basePath = `/app/${subdomain}`;

  let accountSid = $state('');
  let apiKeySid = $state('');
  let apiKeySecret = $state('');
  let label = $state('');
  let saving = $state(false);
  let errorMessage = $state('');

  let canSubmit = $derived(
    accountSid.trim().startsWith('AC') &&
      apiKeySid.trim() !== '' &&
      apiKeySecret.trim() !== '' &&
      !saving,
  );

  async function submit() {
    saving = true;
    errorMessage = '';

    const result = await createConnection(subdomain, {
      external_account_sid: accountSid.trim(),
      api_key_sid: apiKeySid.trim(),
      api_key_secret: apiKeySecret.trim(),
      label: label.trim() || undefined,
    });

    saving = false;

    if (!result.ok) {
      // The server distinguishes rejected credentials from an unreachable
      // provider; surfacing its message rather than a generic one is the
      // difference between "fix your key" and "try again later".
      errorMessage = result.error;
      return;
    }

    toast.success('Twilio account connected');
    await goto(`${basePath}/numbers/connections/${result.data.id}/import`);
  }
</script>

<div class="p-4">
  <h1 class="text-3xl font-bold dark:text-white mb-2">Connect a Twilio account</h1>
  <p class="text-gray-600 dark:text-gray-400 mb-6 max-w-2xl">
    Comcent uses these credentials to list your phone numbers and point the ones you choose at
    Comcent. Twilio continues to bill you directly.
  </p>

  {#if errorMessage}
    <div
      class="mb-4 p-4 rounded-lg bg-red-50 text-red-800 dark:bg-red-900 dark:text-red-200 max-w-2xl"
      role="alert"
    >
      {errorMessage}
    </div>
  {/if}

  <div class="max-w-2xl bg-white dark:bg-gray-800 rounded-lg shadow p-6">
    <ol class="mb-4 text-sm text-gray-600 dark:text-gray-400 list-decimal list-inside space-y-1">
      <li>
        In the Twilio Console, go to <b>Account → API keys &amp; tokens</b>
      </li>
      <li>
        Click <b>Create API key</b>
        and choose key type
        <b>Standard</b>
      </li>
      <li>Copy the SID and secret below — Twilio shows the secret only once</li>
    </ol>

    <details class="mb-6 text-sm">
      <summary class="cursor-pointer text-blue-700 dark:text-blue-400">
        Why Standard, and what can Comcent do with it?
      </summary>
      <div class="mt-2 text-gray-600 dark:text-gray-400 space-y-2">
        <p>
          A <b>Standard</b>
          key can manage phone numbers and SIP trunking, which is what Comcent needs. It deliberately
          <b>cannot</b>
          manage your account or create further API keys, so it is a smaller grant than your Auth Token.
        </p>
        <p>Comcent uses it to:</p>
        <ul class="list-disc list-inside">
          <li>list your phone numbers, so you can choose which to import</li>
          <li>create a SIP trunk and its credentials, so calls can reach Comcent</li>
          <li>point the numbers you select at that trunk — and put them back if you disconnect</li>
        </ul>
        <p>
          It does <b>not</b>
          buy numbers, place calls, or send messages on your behalf. Twilio continues to bill you directly,
          and you can revoke the key in the Twilio Console at any time.
        </p>
        <p>
          A <b>Restricted</b>
          key also works if you prefer to grant less. It needs read and write on
          <b>Phone Numbers</b>
          and on
          <b>SIP Trunking</b>
          .
        </p>
      </div>
    </details>

    <label class="block mb-4">
      <span class="block mb-1 text-sm font-medium text-gray-900 dark:text-white">Account SID</span>
      <input
        bind:value={accountSid}
        placeholder="AC…"
        class="w-full p-2.5 text-sm rounded-lg border border-gray-300 bg-gray-50 dark:bg-gray-700 dark:border-gray-600 dark:text-white"
      />
      <span class="text-xs text-gray-500 dark:text-gray-400">
        On the Twilio Console home page, under Account Info.
      </span>
    </label>

    <label class="block mb-4">
      <span class="block mb-1 text-sm font-medium text-gray-900 dark:text-white">API key SID</span>
      <input
        bind:value={apiKeySid}
        placeholder="SK…"
        class="w-full p-2.5 text-sm rounded-lg border border-gray-300 bg-gray-50 dark:bg-gray-700 dark:border-gray-600 dark:text-white"
      />
    </label>

    <label class="block mb-4">
      <span class="block mb-1 text-sm font-medium text-gray-900 dark:text-white">
        API key secret
      </span>
      <input
        type="password"
        bind:value={apiKeySecret}
        class="w-full p-2.5 text-sm rounded-lg border border-gray-300 bg-gray-50 dark:bg-gray-700 dark:border-gray-600 dark:text-white"
      />
      <span class="text-xs text-gray-500 dark:text-gray-400">
        Stored encrypted. It is never shown again after saving.
      </span>
    </label>

    <label class="block mb-6">
      <span class="block mb-1 text-sm font-medium text-gray-900 dark:text-white">
        Label <span class="font-normal text-gray-500">(optional)</span>
      </span>
      <input
        bind:value={label}
        placeholder="e.g. Production"
        class="w-full p-2.5 text-sm rounded-lg border border-gray-300 bg-gray-50 dark:bg-gray-700 dark:border-gray-600 dark:text-white"
      />
      <span class="text-xs text-gray-500 dark:text-gray-400">
        Helps tell accounts apart if you connect more than one.
      </span>
    </label>

    <div class="flex gap-3">
      <button
        onclick={submit}
        disabled={!canSubmit}
        class="text-white bg-blue-700 hover:bg-blue-800 disabled:opacity-50 disabled:cursor-not-allowed font-medium rounded-lg text-sm px-5 py-2.5"
      >
        {saving ? 'Checking credentials…' : 'Connect'}
      </button>
      <button
        onclick={() => goto(`${basePath}/numbers`)}
        class="text-gray-900 bg-white border border-gray-300 hover:bg-gray-100 font-medium rounded-lg text-sm px-5 py-2.5 dark:bg-gray-800 dark:text-white dark:border-gray-600"
      >
        Cancel
      </button>
    </div>

    <p class="mt-4 text-xs text-gray-500 dark:text-gray-400">
      Credentials are verified with Twilio before anything is saved, so a typo cannot leave a
      half-configured connection behind.
    </p>
  </div>
</div>
