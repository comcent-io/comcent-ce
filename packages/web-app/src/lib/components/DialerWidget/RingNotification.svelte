<script lang="ts">
  import { createEventDispatcher } from 'svelte';
  import type { Invitation } from 'sip.js';

  export let primary: Invitation;
  export let waiting: Invitation[] = [];
  export let isIgnored = false;
  export let currentCallerName: string | undefined = undefined;

  const dispatch = createEventDispatcher();

  function onAnswer(invitation: Invitation) {
    dispatch('answer', invitation);
  }

  function onDecline(invitation: Invitation) {
    dispatch('decline', invitation);
  }

  function onIgnore(invitation: Invitation) {
    dispatch('ignore', invitation);
  }

  function displayName(invitation: Invitation) {
    return invitation.remoteIdentity.displayName || invitation.remoteIdentity.uri.aor;
  }

  function subAddress(invitation: Invitation) {
    return invitation.remoteIdentity.displayName ? invitation.remoteIdentity.uri.aor : '';
  }

  function viaNumber(invitation: Invitation) {
    const inboundInfo = invitation.request.headers['X-Inbound-Info']?.[0]?.raw;
    const firstPath = inboundInfo?.split('|')?.[0];
    const number = firstPath?.split(':')?.[1];
    const name = firstPath?.split(':')?.[2];
    return name && number ? `${name} (${number})` : '';
  }
</script>

<div
  class="mb-4 overflow-hidden rounded-2xl border bg-white shadow-lg dark:bg-gray-900 {isIgnored
    ? 'border-gray-200 dark:border-gray-700'
    : 'border-red-200 dark:border-red-900'}"
>
  <div
    class="flex items-center gap-2 px-3.5 py-2.5 {isIgnored
      ? 'bg-gray-100 dark:bg-gray-800'
      : 'bg-red-50 dark:bg-red-950'}"
  >
    <span class="h-2 w-2 rounded-full {isIgnored ? 'bg-gray-400' : 'bg-red-500 dark:bg-red-400'}" />
    <span
      class="text-xs font-bold uppercase tracking-wide {isIgnored
        ? 'text-gray-500 dark:text-gray-400'
        : 'text-red-700 dark:text-red-300'}"
    >
      {#if isIgnored}
        Silenced — still ringing
      {:else if waiting.length > 0}
        Incoming Call — {waiting.length} more waiting
      {:else}
        Incoming Call
      {/if}
    </span>
  </div>

  <div class="p-4">
    <div class="min-w-0">
      <h6 class="truncate text-lg font-bold text-gray-900 dark:text-white">
        {displayName(primary)}
      </h6>
      {#if subAddress(primary)}
        <p class="truncate text-sm text-gray-500 dark:text-gray-400">{subAddress(primary)}</p>
      {/if}
      {#if viaNumber(primary)}
        <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">
          <span class="font-semibold">Inbound Number:</span>
          {viaNumber(primary)}
        </p>
      {/if}
    </div>

    {#if currentCallerName}
      <div
        class="mt-3 rounded-lg bg-blue-50 px-3 py-2 text-xs text-blue-800 dark:bg-blue-950 dark:text-blue-200"
      >
        Answering will place <span class="font-semibold">{currentCallerName}</span>
        on hold.
      </div>
    {/if}

    <div class="mt-4 flex gap-2">
      <button
        type="button"
        on:click={() => onAnswer(primary)}
        class="flex-1 rounded-lg bg-green-600 py-2.5 text-sm font-bold text-white transition-colors hover:bg-green-700 focus:outline-none focus:ring-4 focus:ring-green-300 dark:focus:ring-green-800"
      >
        Answer
      </button>
      <button
        type="button"
        on:click={() => onDecline(primary)}
        class="flex-1 rounded-lg bg-red-600 py-2.5 text-sm font-bold text-white transition-colors hover:bg-red-700 focus:outline-none focus:ring-4 focus:ring-red-300 dark:focus:ring-red-800"
      >
        Decline
      </button>
      {#if !isIgnored}
        <button
          type="button"
          on:click={() => onIgnore(primary)}
          class="rounded-lg border border-gray-300 px-4 py-2.5 text-sm font-semibold text-gray-600 transition-colors hover:bg-gray-100 dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-800"
        >
          Ignore
        </button>
      {/if}
    </div>

    {#if waiting.length > 0}
      <div class="mt-3 border-t border-red-100 pt-3 dark:border-red-900/40">
        <div
          class="mb-2 text-xs font-bold uppercase tracking-wide text-gray-500 dark:text-gray-400"
        >
          Also Waiting
        </div>
        <div class="flex flex-col gap-1.5">
          {#each waiting as invitation (invitation.id)}
            <div
              class="flex items-center gap-2 rounded-lg border border-gray-200 bg-gray-50 px-2.5 py-1.5 dark:border-gray-700 dark:bg-gray-800"
            >
              <div class="min-w-0 flex-1">
                <div class="truncate text-sm font-medium text-gray-800 dark:text-gray-100">
                  {displayName(invitation)}
                </div>
                {#if subAddress(invitation) || viaNumber(invitation)}
                  <div class="truncate text-xs text-gray-500 dark:text-gray-400">
                    {subAddress(invitation) || viaNumber(invitation)}
                  </div>
                {/if}
              </div>
              <button
                type="button"
                on:click={() => onAnswer(invitation)}
                class="whitespace-nowrap rounded-md bg-green-600 px-2.5 py-1.5 text-xs font-semibold text-white transition-colors hover:bg-green-700"
              >
                Answer
              </button>
              <button
                type="button"
                on:click={() => onDecline(invitation)}
                class="whitespace-nowrap rounded-md border border-gray-300 px-2 py-1.5 text-xs text-gray-600 transition-colors hover:bg-gray-100 dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-700"
              >
                Decline
              </button>
            </div>
          {/each}
        </div>
      </div>
    {/if}
  </div>
</div>
