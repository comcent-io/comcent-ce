<script lang="ts">
  import moment from 'moment-timezone';
  import PhoneConnectIcon from './icons/PhoneConnectIcon.svelte';
  import PhoneDisconnectIcon from './icons/PhoneDisconnectIcon.svelte';
  export let calls;

  export let onSpeakOrListen;
  export let onHangUp;
  export let onInviteAccepted = (callId: string) => {};
  export let webRtcConnected;
</script>

<div>
  {#each calls as call}
    <div
      class="block rounded-lg border border-gray-200 bg-white p-6 shadow hover:bg-gray-100 dark:border-gray-700 dark:bg-gray-800 dark:hover:bg-gray-700"
    >
      <h5 class="mb-2 text-2xl font-bold tracking-tight text-gray-900 dark:text-white">
        {moment(call.startedAt).format('YYYY/MM/DD hh:mm a')}
      </h5>
      <div class="mb-4 flex space-x-4">
        <p class="font-normal text-gray-700 dark:text-gray-400">
          From: {call.fromNumber}
        </p>
        <p class="font-normal text-gray-700 dark:text-gray-400">
          To: {call.toNumber}
        </p>
      </div>
      {#if call.state === 'RINGING'}
        <button
          on:click={() => {
            onInviteAccepted(call.callId);
          }}
          type="button"
          class="mb-2 me-2 rounded-full bg-blue-700 px-2.5 py-2.5 text-sm font-medium text-white hover:bg-blue-800 focus:outline-none focus:ring-4 focus:ring-blue-300 dark:bg-blue-600 dark:hover:bg-blue-700 dark:focus:ring-blue-800"
        >
          <PhoneConnectIcon />
        </button>
      {/if}
      {#if call.state === 'CONNECTED'}
        <button
          on:click={() => onSpeakOrListen(call.callId)}
          type="button"
          class="mb-2 me-2 rounded-lg bg-blue-700 px-5 py-2.5 text-sm font-medium text-white hover:bg-blue-800 focus:outline-none focus:ring-4 focus:ring-blue-300 dark:bg-blue-600 dark:hover:bg-blue-700 dark:focus:ring-blue-800"
        >
          {#if call.isAudioConnected && webRtcConnected}
            Disconnect Audio
          {:else}
            Connect Audio
          {/if}
        </button>
      {/if}
      <button
        on:click={() => onHangUp(call.callId)}
        type="button"
        class="mb-3 me-2 rounded-full bg-red-700 px-2.5 py-2.5 text-sm font-medium text-white hover:bg-red-800 focus:outline-none focus:ring-4 focus:ring-red-300 dark:bg-red-600 dark:hover:bg-red-700 dark:focus:ring-red-900"
      >
        <PhoneDisconnectIcon />
      </button>
    </div>
  {/each}
</div>
