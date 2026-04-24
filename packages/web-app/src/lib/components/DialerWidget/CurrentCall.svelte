<script lang="ts">
  import H6 from '$lib/components/html/H6.svelte';
  import CallTime from '$lib/components/DialerWidget/CallTime.svelte';
  import HangupButton from '$lib/components/DialerWidget/buttons/HangupButton.svelte';
  import HoldButton from '$lib/components/DialerWidget/buttons/HoldButton.svelte';
  import DialPadButton from '$lib/components/DialerWidget/buttons/DialPadButton.svelte';
  import MuteButton from '$lib/components/DialerWidget/buttons/MuteButton.svelte';
  import DialPad from '$lib/components/DialerWidget/DialPad.svelte';
  import { slide } from 'svelte/transition';
  import { createEventDispatcher, onMount } from 'svelte';
  import TransferButton from '$lib/components/DialerWidget/buttons/TransferButton.svelte';
  import type { Session } from 'sip.js';
  import type { SessionManager } from 'sip.js/lib/platform/web';

  const dispatch = createEventDispatcher<{
    hangup: void;
    hold: void;
    unhold: void;
    mute: void;
    unmute: void;
    dtmfNumberPress: { number: string };
    blindTransfer: { transferAddress: string };
    attendedTransfer: { transferAddress: string };
    confirmAttendedTransfer: void;
    cancelAttendedTransfer: void;
  }>();

  export let sessionManager: SessionManager;
  export let startTime: Date | undefined;
  export let session: Session;
  export let heldForAttendedTransfer: Session | undefined | null;

  let showDialPad = false;

  let hold = false;
  $: {
    if (hold) {
      dispatch('hold');
    } else {
      dispatch('unhold');
    }
  }

  let muted = false;
  $: {
    if (muted) {
      dispatch('mute');
    } else {
      dispatch('unmute');
    }
  }

  let dtmfSentNumbers = '';
  function onDialKeyPress(e) {
    const dtmfNumber = e.detail.number;
    dispatch('dtmfNumberPress', { number: dtmfNumber });
    dtmfSentNumbers += dtmfNumber;
  }

  function onConfirmAttendedTransfer() {
    dispatch('confirmAttendedTransfer');
  }

  function onCancelAttendedTransfer() {
    dispatch('cancelAttendedTransfer');
  }

  let showTransferMenu = false;
  let transferAddress = '';

  onMount(() => {
    hold = sessionManager.isHeld(session);
    muted = sessionManager.isMuted(session);
  });
</script>

<div
  class="p-4 mb-4 bg-white border border-gray-200 rounded-lg shadow hover:bg-gray-100 dark:bg-gray-800 dark:border-gray-700 dark:hover:bg-gray-700"
>
  <div class="flex justify-between">
    <div>
      <H6>{session.remoteIdentity.friendlyName ?? session.remoteIdentity.uri}</H6>
      <p class="mb-3 text-gray-500 dark:text-gray-400">
        {session.remoteIdentity.friendlyName ? session.remoteIdentity.uri : ''}
      </p>
    </div>
    <div class="flex flex-col justify-center">
      {#if startTime}
        <CallTime {startTime} class="text-2xl mr-8" />
      {:else}
        <p class="text-gray-500 dark:text-gray-400">Connecting...</p>
      {/if}
    </div>
  </div>
  <div class="flex justify-between">
    {#if startTime}
      <MuteButton bind:muted />
      {#if !heldForAttendedTransfer}
        <HoldButton bind:hold />
        {#if !showTransferMenu}
          <TransferButton
            on:click={() => {
              showTransferMenu = !showTransferMenu;
            }}
          />
        {/if}
      {/if}
    {/if}
    <HangupButton on:click={() => dispatch('hangup')} />
    <DialPadButton bind:showDialPad />
  </div>
  {#if showTransferMenu}
    <div transition:slide={{ delay: 250, duration: 300 }} class="mt-3">
      <input
        type="text"
        id="toAddress"
        class="bg-gray-50 mb-3 w-full border border-gray-300 text-gray-900 rounded-lg focus:ring-blue-500 focus:border-blue-500 inline-block p-2.5 dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500"
        bind:value={transferAddress}
      />
      <div class="flex justify-between">
        <button
          type="button"
          on:click={() => {
            showTransferMenu = false;
            dispatch('blindTransfer', { transferAddress });
          }}
          disabled={transferAddress === ''}
          class="text-white bg-blue-700 hover:bg-blue-800 focus:ring-4 focus:ring-blue-300 font-medium rounded-lg text-sm px-5 py-2.5 mr-2 mb-2 dark:bg-blue-600 dark:hover:bg-blue-700 focus:outline-none dark:focus:ring-blue-800"
        >
          Blind Transfer
        </button>

        <button
          type="button"
          on:click={() => {
            showTransferMenu = false;
            dispatch('attendedTransfer', { transferAddress });
          }}
          disabled={transferAddress === ''}
          class=" text-white bg-blue-700 hover:bg-blue-800 focus:ring-4 focus:ring-blue-300 font-medium rounded-lg text-sm px-5 py-2.5 mr-2 mb-2 dark:bg-blue-600 dark:hover:bg-blue-700 focus:outline-none dark:focus:ring-blue-800"
        >
          Attended Transfer
        </button>

        <button
          type="button"
          on:click={() => {
            showTransferMenu = false;
            transferAddress = '';
          }}
          class=" text-white bg-blue-700 hover:bg-red-800 focus:ring-4 focus:ring-blue-300 font-medium rounded-lg text-sm px-5 py-2.5 mr-2 mb-2 dark:bg-red-600 dark:hover:bg-red-700 focus:outline-none dark:focus:ring-blue-800"
        >
          Cancel
        </button>
      </div>
    </div>
  {/if}
  {#if heldForAttendedTransfer}
    <div transition:slide={{ delay: 250, duration: 300 }}>
      <H6>
        {heldForAttendedTransfer.remoteIdentity.friendlyName ??
          heldForAttendedTransfer.remoteIdentity.uri}
      </H6>
      <p class="mb-3 text-gray-500 dark:text-gray-400">
        {heldForAttendedTransfer.remoteIdentity.friendlyName
          ? heldForAttendedTransfer.remoteIdentity.uri
          : ''}
      </p>
      <div class="flex justify-between">
        <button
          type="button"
          on:click={onConfirmAttendedTransfer}
          class=" ml-4 mr-1 text-white bg-orange-700 hover:bg-orange-800 focus:ring-4 focus:outline-none focus:ring-orange-300 font-medium text-sm p-2.5 inline-flex justify-center items-center dark:bg-orange-600 dark:hover:bg-orange-700 dark:focus:ring-orange-800"
        >
          Transfer
        </button>

        <button
          type="button"
          on:click={onCancelAttendedTransfer}
          class=" ml-4 mr-1 text-white bg-orange-700 hover:bg-orange-800 focus:ring-4 focus:outline-none focus:ring-orange-300 font-medium text-sm p-2.5 inline-flex justify-center items-center dark:bg-orange-600 dark:hover:bg-orange-700 dark:focus:ring-orange-800"
        >
          Cancel & Talk
        </button>
      </div>
    </div>
  {/if}
  {#if showDialPad}
    <div transition:slide={{ delay: 250, duration: 300 }} class="mt-3">
      <input
        type="text"
        id="toAddress"
        class="bg-gray-50 mb-3 w-full border border-gray-300 text-gray-900 rounded-lg focus:ring-blue-500 focus:border-blue-500 inline-block p-2.5 dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500"
        value={dtmfSentNumbers}
        disabled
      />
      <DialPad on:dialKeyPress={onDialKeyPress} />
    </div>
  {/if}
</div>
