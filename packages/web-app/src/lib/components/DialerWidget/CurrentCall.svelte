<script lang="ts">
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
  import { isValidPhoneNumber } from 'libphonenumber-js';
  import type { MemberSearchResult } from '$lib/server/types/MemberSearchResult';

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
    newCall: void;
  }>();

  export let sessionManager: SessionManager;
  export let startTime: Date | undefined;
  export let session: Session;
  export let heldForAttendedTransfer: Session | undefined | null;
  export let search: ((text: string) => Promise<MemberSearchResult[]>) | undefined = undefined;

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
  let transferMode: 'blind' | 'attended' = 'blind';
  let transferAddress = '';
  let transferSearchResults: MemberSearchResult[] = [];

  function closeTransferMenu() {
    showTransferMenu = false;
    transferMode = 'blind';
    transferAddress = '';
    transferSearchResults = [];
  }

  async function onTransferAddressInput(e: Event) {
    const value = (e.target as HTMLInputElement).value;
    if (isValidPhoneNumber(value) || value.length < 3 || !search) {
      transferSearchResults = [];
      return;
    }
    transferSearchResults = await search(value);
  }

  function selectTransferMember(member: MemberSearchResult) {
    transferAddress = member.username;
    transferSearchResults = [];
  }

  function onConfirmTransfer() {
    if (transferAddress === '') return;
    const address = transferAddress;
    closeTransferMenu();
    if (transferMode === 'blind') {
      dispatch('blindTransfer', { transferAddress: address });
    } else {
      dispatch('attendedTransfer', { transferAddress: address });
    }
  }

  function callerLabel(s: Session) {
    return s.remoteIdentity.friendlyName ?? s.remoteIdentity.uri;
  }

  function callerSub(s: Session) {
    return s.remoteIdentity.friendlyName ? s.remoteIdentity.uri : '';
  }

  onMount(() => {
    hold = sessionManager.isHeld(session);
    muted = sessionManager.isMuted(session);
  });
</script>

<div>
  <div class="flex items-start justify-between gap-3">
    <div class="min-w-0">
      <h6 class="truncate text-base font-bold text-gray-900 dark:text-white">
        {callerLabel(session)}
      </h6>
      {#if callerSub(session)}
        <p class="truncate text-sm text-gray-500 dark:text-gray-400">{callerSub(session)}</p>
      {/if}
    </div>
    <div class="shrink-0 text-right">
      {#if startTime}
        <div class="text-xs font-bold uppercase tracking-wide text-green-600 dark:text-green-400">
          Connected
        </div>
        <CallTime {startTime} class="font-mono text-sm" />
      {:else}
        <p class="text-sm text-gray-500 dark:text-gray-400">Connecting...</p>
      {/if}
    </div>
  </div>

  <div class="mt-3 flex gap-1.5">
    {#if startTime}
      <MuteButton bind:muted />
      {#if !heldForAttendedTransfer}
        <HoldButton bind:hold />
        <TransferButton
          active={showTransferMenu}
          on:click={() => {
            if (showTransferMenu) {
              closeTransferMenu();
            } else {
              showTransferMenu = true;
            }
          }}
        />
      {/if}
    {/if}
    <DialPadButton bind:showDialPad />
    <HangupButton on:click={() => dispatch('hangup')} />
  </div>

  {#if startTime && !heldForAttendedTransfer}
    <button
      type="button"
      on:click={() => dispatch('newCall')}
      class="mt-2 flex w-full items-center justify-center gap-1.5 rounded-lg border border-gray-300 py-2 text-xs font-semibold text-gray-600 transition-colors hover:bg-gray-100 dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-800"
    >
      + New Call
    </button>
  {/if}

  {#if showTransferMenu}
    <div
      transition:slide={{ delay: 150, duration: 250 }}
      class="mt-3 rounded-lg border border-gray-200 bg-gray-50 p-3 dark:border-gray-700 dark:bg-gray-800"
    >
      <div class="mb-2 flex gap-2">
        <button
          type="button"
          on:click={() => (transferMode = 'blind')}
          class="flex-1 rounded-md border px-2 py-1.5 text-xs font-semibold transition-colors"
          class:transfer-mode-active={transferMode === 'blind'}
          class:transfer-mode-inactive={transferMode !== 'blind'}
        >
          Blind Transfer
        </button>
        <button
          type="button"
          on:click={() => (transferMode = 'attended')}
          class="flex-1 rounded-md border px-2 py-1.5 text-xs font-semibold transition-colors"
          class:transfer-mode-active={transferMode === 'attended'}
          class:transfer-mode-inactive={transferMode !== 'attended'}
        >
          Attended Transfer
        </button>
      </div>
      <p class="mb-2 text-xs text-gray-500 dark:text-gray-400">
        {transferMode === 'blind'
          ? 'Redirects the call immediately — you will be disconnected.'
          : 'Rings the destination privately first; the customer stays on hold until you complete or cancel.'}
      </p>

      <div class="relative">
        <input
          type="text"
          placeholder="Name or number"
          class="w-full rounded-lg border border-gray-300 bg-white p-2.5 text-sm text-gray-900 focus:border-blue-500 focus:ring-blue-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white dark:placeholder-gray-400"
          bind:value={transferAddress}
          on:input={onTransferAddressInput}
        />
        {#if transferSearchResults.length > 0}
          <div
            class="absolute z-10 mt-1 max-h-48 w-full overflow-y-auto rounded-lg border border-gray-200 bg-white shadow-lg dark:border-gray-600 dark:bg-gray-700"
          >
            <ul class="py-1 text-sm text-gray-700 dark:text-gray-200">
              {#each transferSearchResults as member}
                <li>
                  <button
                    type="button"
                    on:click|preventDefault={() => selectTransferMember(member)}
                    class="block w-full px-3 py-2 text-left hover:bg-gray-100 dark:hover:bg-gray-600"
                  >
                    {member.username} [{member.presence}]
                  </button>
                </li>
              {/each}
            </ul>
          </div>
        {/if}
      </div>

      <div class="mt-2 flex justify-end gap-2">
        <button
          type="button"
          on:click={closeTransferMenu}
          class="rounded-lg px-3 py-2 text-xs font-semibold text-gray-600 transition-colors hover:bg-gray-200 dark:text-gray-300 dark:hover:bg-gray-700"
        >
          Cancel
        </button>
        <button
          type="button"
          on:click={onConfirmTransfer}
          disabled={transferAddress === ''}
          class="rounded-lg bg-blue-600 px-4 py-2 text-xs font-semibold text-white transition-colors hover:bg-blue-700 disabled:cursor-not-allowed disabled:bg-gray-300 dark:disabled:bg-gray-600"
        >
          {transferMode === 'blind' ? 'Transfer Call' : 'Call Privately'}
        </button>
      </div>
    </div>
  {/if}

  {#if heldForAttendedTransfer}
    <div
      transition:slide={{ delay: 150, duration: 250 }}
      class="mt-3 rounded-lg border border-amber-200 bg-amber-50 p-3 dark:border-amber-900 dark:bg-amber-950"
    >
      <div
        class="mb-1 text-xs font-bold uppercase tracking-wide text-amber-700 dark:text-amber-300"
      >
        {callerLabel(session)} is on hold
      </div>
      <h6 class="text-sm font-bold text-gray-900 dark:text-white">
        {callerLabel(heldForAttendedTransfer)}
      </h6>
      {#if callerSub(heldForAttendedTransfer)}
        <p class="text-xs text-gray-500 dark:text-gray-400">
          {callerSub(heldForAttendedTransfer)}
        </p>
      {/if}
      <div class="mt-2 flex gap-2">
        <button
          type="button"
          on:click={onConfirmAttendedTransfer}
          class="flex-1 rounded-lg bg-blue-600 px-3 py-2 text-xs font-semibold text-white transition-colors hover:bg-blue-700"
        >
          Complete Transfer
        </button>
        <button
          type="button"
          on:click={onCancelAttendedTransfer}
          class="flex-1 rounded-lg border border-gray-300 px-3 py-2 text-xs font-semibold text-gray-700 transition-colors hover:bg-gray-100 dark:border-gray-600 dark:text-gray-200 dark:hover:bg-gray-700"
        >
          Resume Call
        </button>
      </div>
    </div>
  {/if}

  {#if showDialPad}
    <div transition:slide={{ delay: 150, duration: 250 }} class="mt-3">
      <input
        type="text"
        class="mb-2 w-full rounded-lg border border-gray-300 bg-gray-50 p-2.5 text-center font-mono text-sm text-gray-900 dark:border-gray-600 dark:bg-gray-700 dark:text-white"
        value={dtmfSentNumbers}
        disabled
      />
      <DialPad on:dialKeyPress={onDialKeyPress} />
    </div>
  {/if}
</div>

<style lang="postcss">
  .transfer-mode-active {
    @apply border-blue-600 bg-blue-50 text-blue-700 dark:border-blue-500 dark:bg-blue-950 dark:text-blue-300;
  }
  .transfer-mode-inactive {
    @apply border-gray-300 bg-white text-gray-600 hover:bg-gray-100 dark:border-gray-600 dark:bg-transparent dark:text-gray-300 dark:hover:bg-gray-700;
  }
</style>
