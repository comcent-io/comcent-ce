<script lang="ts">
  import PhoneDisconnectIcon from '$lib/components/Icons/PhoneDisconnectIcon.svelte';
  import PhoneIcon from '$lib/components/Icons/PhoneIcon.svelte';
  import { createEventDispatcher } from 'svelte';
  import type { Invitation } from 'sip.js';

  export let invitation: Invitation;

  const dispatch = createEventDispatcher();

  function onAnswer() {
    dispatch('answer', invitation);
  }

  function onDecline() {
    dispatch('decline', invitation);
  }

  let viaNumber = '';
  $: {
    const inboundInfo = invitation.request.headers['X-Inbound-Info']?.[0]?.raw;
    const firstPath = inboundInfo?.split('|')?.[0];
    const number = firstPath?.split(':')?.[1];
    const name = firstPath?.split(':')?.[2];
    if (name && number) {
      viaNumber = `${name} (${number})`;
    }
  }
</script>

<div
  class="p-4 mb-4 bg-white border border-gray-200 rounded-lg shadow hover:bg-gray-100 dark:bg-gray-800 dark:border-gray-700 dark:hover:bg-gray-700"
>
  <div class="flex items-center justify-between">
    <div>
      <h6 class="text-lg font-bold dark:text-white">
        {invitation.remoteIdentity.displayName || invitation.remoteIdentity.uri.aor}
      </h6>
      {#if invitation.remoteIdentity.displayName}
        <p class="mb-3 text-gray-500 dark:text-gray-400">{invitation.remoteIdentity.uri.aor}</p>
      {/if}

      {#if viaNumber}
        <p class="text-gray-500 dark:text-gray-400 font-bold">Inbound Number</p>
        <p class="mb-3 text-gray-500 dark:text-gray-400">{viaNumber}</p>
      {/if}
    </div>
    <div>
      <button
        type="button"
        on:click={onAnswer}
        class="mr-4 rounded-full text-white bg-green-700 hover:bg-green-800 focus:ring-4 focus:outline-none focus:ring-green-300 font-medium text-sm p-4 inline-flex justify-center items-center dark:bg-green-600 dark:hover:bg-green-700 dark:focus:ring-green-800"
      >
        <PhoneIcon />
        <span class="sr-only">Answer</span>
      </button>
      <button
        type="button"
        on:click={onDecline}
        class=" rounded-full text-white bg-red-700 hover:bg-red-800 focus:ring-4 focus:outline-none focus:ring-red-300 font-medium text-sm p-4 inline-flex justify-center items-center dark:bg-red-600 dark:hover:bg-red-700 dark:focus:ring-red-800"
      >
        <PhoneDisconnectIcon />
        <span class="sr-only">Decline</span>
      </button>
    </div>
  </div>
</div>
