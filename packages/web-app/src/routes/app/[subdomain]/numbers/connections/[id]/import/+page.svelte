<script lang="ts">
  import { SvelteSet } from 'svelte/reactivity';
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import { page } from '$app/state';
  import { routeParam } from '$lib/routeParam';
  import toast from '$lib/toast';
  import {
    importNumbersSequentially,
    listAvailableNumbers,
    type AvailableNumber,
    type ImportResult,
  } from '$lib/providerConnections';

  const subdomain = routeParam('subdomain');
  const connectionId = routeParam('id');
  const basePath = `/app/${subdomain}`;

  let numbers: AvailableNumber[] = $state([]);
  let selected = $state(new SvelteSet<string>());
  let loading = $state(true);
  let importing = $state(false);
  let errorMessage = $state('');
  let results: ImportResult[] = $state([]);

  // Each number costs ~3s of Twilio round-trips, so a batch of ten leaves the
  // page silent for half a minute. Track how far along we are and which number
  // is in flight, so the wait is legible instead of looking hung.
  let importTotal = $state(0);
  let importDone = $state(0);
  let importCurrent = $state('');
  let importPercent = $derived(
    importTotal === 0 ? 0 : Math.round((importDone / importTotal) * 100),
  );

  // Twilio silently moves a number off whatever trunk it is on, so taking one
  // has to be a deliberate choice rather than a side effect of ticking a box.
  let confirmTrunkMove = $state(false);

  // Typed so the template can index `capabilities` without widening to string.
  const capabilityKeys = ['voice', 'sms', 'mms'] as const;

  let selectedList = $derived([...selected]);
  let selectedOnOtherTrunk = $derived(
    numbers.filter((n) => selected.has(n.providerSid) && n.trunkSid),
  );
  let blockedByTrunk = $derived(selectedOnOtherTrunk.length > 0 && !confirmTrunkMove);
  let canImport = $derived(selectedList.length > 0 && !importing && !blockedByTrunk);

  onMount(load);

  async function load() {
    loading = true;
    errorMessage = '';
    const result = await listAvailableNumbers(subdomain, connectionId);
    loading = false;

    if (!result.ok) {
      errorMessage = result.error;
      return;
    }
    numbers = result.data.numbers;
  }

  function toggle(sid: string) {
    if (selected.has(sid)) selected.delete(sid);
    else selected.add(sid);
  }

  /** Label for the number currently being imported, so progress names a number. */
  function labelFor(sid: string | undefined): string {
    if (!sid) return '';
    return numbers.find((n) => n.providerSid === sid)?.e164 ?? sid;
  }

  async function runImport() {
    importing = true;
    errorMessage = '';
    results = [];

    const queue = selectedList;
    importTotal = queue.length;
    importDone = 0;
    importCurrent = labelFor(queue[0]);

    await importNumbersSequentially(
      subdomain,
      connectionId,
      queue,
      confirmTrunkMove,
      (result, done) => {
        // Results land one at a time, so the list fills in as we go rather
        // than appearing all at once at the end.
        results = [...results, result];
        importDone = done;
        importCurrent = done < queue.length ? labelFor(queue[done]) : '';
      },
    );

    importing = false;
    importCurrent = '';

    // Per-number results: one failure must not hide the successes.
    const ok = results.filter((r) => r.ok).length;
    const failed = results.length - ok;

    if (ok > 0) toast.success(`Imported ${ok} number${ok === 1 ? '' : 's'}`);
    if (failed > 0) toast.error(`${failed} could not be imported`);

    selected = new SvelteSet();
    await load();
  }
</script>

<div class="p-4">
  <h1 class="text-3xl font-bold dark:text-white mb-2">Import numbers</h1>
  <p class="text-gray-600 dark:text-gray-400 mb-6 max-w-3xl">
    Fetched live from Twilio, so this is exactly what your account holds right now.
  </p>

  {#if errorMessage}
    <div
      class="mb-4 p-4 rounded-lg bg-red-50 text-red-800 dark:bg-red-900 dark:text-red-200 max-w-3xl"
      role="alert"
    >
      {errorMessage}
    </div>
  {/if}

  {#if loading}
    <p class="text-gray-500 dark:text-gray-400">Loading numbers from Twilio…</p>
  {:else if numbers.length === 0}
    <p class="text-gray-500 dark:text-gray-400">This Twilio account has no phone numbers.</p>
  {:else}
    <div class="relative overflow-x-auto shadow-md sm:rounded-lg max-w-4xl">
      <table class="w-full text-sm text-left text-gray-500 dark:text-gray-400">
        <thead
          class="text-xs text-gray-700 uppercase bg-gray-50 dark:bg-gray-700 dark:text-gray-400"
        >
          <tr>
            <th class="px-4 py-3 w-10"></th>
            <th class="px-6 py-3">Number</th>
            <th class="px-6 py-3">Name</th>
            <th class="px-6 py-3">Capabilities</th>
            <th class="px-6 py-3">Status</th>
          </tr>
        </thead>
        <tbody>
          {#each numbers as n}
            <tr class="bg-white border-b dark:bg-gray-900 dark:border-gray-700">
              <td class="px-4 py-4">
                <input
                  type="checkbox"
                  disabled={!n.importable}
                  checked={selected.has(n.providerSid)}
                  onchange={() => toggle(n.providerSid)}
                  class="w-4 h-4 disabled:opacity-40"
                />
              </td>
              <td class="px-6 py-4 font-medium text-gray-900 whitespace-nowrap dark:text-white">
                {n.e164}
              </td>
              <td class="px-6 py-4">{n.friendlyName ?? '—'}</td>
              <td class="px-6 py-4">
                <span class="flex gap-1 flex-wrap">
                  {#each capabilityKeys as cap}
                    {#if n.capabilities[cap]}
                      <span
                        class="text-xs px-2 py-0.5 rounded bg-gray-100 dark:bg-gray-700 dark:text-gray-300"
                      >
                        {cap}
                      </span>
                    {/if}
                  {/each}
                </span>
              </td>
              <td class="px-6 py-4">
                {#if !n.importable}
                  <span class="text-gray-500 dark:text-gray-400">{n.reason}</span>
                {:else if n.trunkSid}
                  <span class="text-amber-700 dark:text-amber-400">on another trunk</span>
                {:else}
                  <span class="text-green-700 dark:text-green-400">available</span>
                {/if}
              </td>
            </tr>
          {/each}
        </tbody>
      </table>
    </div>

    {#if selectedOnOtherTrunk.length > 0}
      <div
        class="mt-4 max-w-4xl p-4 rounded-lg bg-amber-50 text-amber-900 dark:bg-amber-900 dark:text-amber-100"
      >
        <p class="font-semibold mb-1">
          {selectedOnOtherTrunk.length} selected number{selectedOnOtherTrunk.length === 1
            ? ' is'
            : 's are'} already attached to another SIP trunk
        </p>
        <p class="text-sm mb-2">
          Importing will move {selectedOnOtherTrunk.length === 1 ? 'it' : 'them'} to Comcent. Whatever
          that trunk currently serves will stop receiving these calls. Twilio does not warn about this,
          so we do.
        </p>
        <label class="flex items-center gap-2 text-sm">
          <input type="checkbox" bind:checked={confirmTrunkMove} class="w-4 h-4" />
          I understand, move {selectedOnOtherTrunk.length === 1 ? 'it' : 'them'} to Comcent
        </label>
      </div>
    {/if}

    {#if importing}
      <div class="mt-4 max-w-xl" role="status" aria-live="polite">
        <div class="flex justify-between text-sm mb-1 dark:text-gray-300">
          <span>
            Importing {Math.min(importDone + 1, importTotal)} of {importTotal}
            {#if importCurrent}
              — {importCurrent}
            {/if}
          </span>
          <span class="text-gray-500 dark:text-gray-400">{importPercent}%</span>
        </div>
        <div class="w-full bg-gray-200 rounded-full h-2 dark:bg-gray-700">
          <div
            class="bg-blue-600 h-2 rounded-full transition-all duration-300"
            style="width: {importPercent}%"
          ></div>
        </div>
        <p class="text-xs text-gray-500 dark:text-gray-400 mt-1">
          Each number takes a few seconds to set up in Twilio. You can leave this page open.
        </p>
      </div>
    {/if}

    <div class="mt-4 flex gap-3 items-center">
      <button
        onclick={runImport}
        disabled={!canImport}
        class="text-white bg-blue-700 hover:bg-blue-800 disabled:opacity-50 disabled:cursor-not-allowed font-medium rounded-lg text-sm px-5 py-2.5"
      >
        {importing
          ? 'Importing…'
          : `Import ${selectedList.length || ''} number${selectedList.length === 1 ? '' : 's'}`}
      </button>
      <button
        onclick={() => goto(`${basePath}/numbers`)}
        class="text-gray-900 bg-white border border-gray-300 hover:bg-gray-100 font-medium rounded-lg text-sm px-5 py-2.5 dark:bg-gray-800 dark:text-white dark:border-gray-600"
      >
        Done
      </button>
    </div>
  {/if}

  {#if results.length > 0}
    <!-- Last on the page on purpose: this list grows by a row as each number
         lands, and anything below it would be pushed down on every tick. The
         progress bar in particular has to stay still to be readable. -->
    <div class="mt-6 max-w-3xl rounded-lg border border-gray-200 dark:border-gray-700 p-4">
      <h2 class="font-semibold mb-2 dark:text-white">
        {importing ? 'Importing…' : 'Last import'}
      </h2>
      <ul class="text-sm space-y-1">
        {#each results as r}
          <li
            class={r.ok ? 'text-green-700 dark:text-green-400' : 'text-red-700 dark:text-red-400'}
          >
            {r.ok ? '✓' : '✗'}
            {r.e164 ?? r.providerSid}{r.error ? ` — ${r.error}` : ''}
          </li>
        {/each}
      </ul>
    </div>
  {/if}
</div>
