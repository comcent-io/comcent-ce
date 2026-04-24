<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import { page } from '$app/stores';
  import { browser } from '$app/environment';
  import { Socket } from 'phoenix';
  import { getIdTokenFromCookie } from '$lib/getIdTokenFromCookie';
  import moment from 'moment';

  type LiveCall = {
    callStoryId: string;
    startAt: string | null;
    currentParty: string | null;
    direction: string | null;
    caller: string | null;
    callee: string | null;
  };

  let liveCalls: LiveCall[] = [];
  let socket: Socket | undefined;
  let loading = true;

  async function fetchLiveCalls() {
    try {
      const response = await fetch(`/api/v2/${$page.params.subdomain}/calls/live`);
      if (!response.ok) throw new Error((await response.json()).error ?? response.statusText);
      const data = await response.json();
      liveCalls = data.liveCalls || [];
      loading = false;
    } catch (error) {
      console.error('Error fetching live calls:', error);
      loading = false;
    }
  }

  function getDirectionLabel(direction: string | undefined | null): string {
    if (!direction) {
      return 'Unknown';
    }
    return direction === 'inbound' ? 'Inbound' : 'Outbound';
  }

  function displayName(name: string | undefined | null): string {
    if (!name) {
      return 'Unknown';
    }
    if (name.includes('@')) {
      return name.split('@')[0];
    }
    return name;
  }

  let interval: NodeJS.Timeout | undefined;

  onMount(async () => {
    await fetchLiveCalls();

    if (!browser) {
      return;
    }

    const idToken = getIdTokenFromCookie();

    socket = new Socket(`/ws`, {
      params: {
        subdomain: $page.params.subdomain,
        token: idToken,
      },
    });

    socket.connect();

    const channel = socket.channel(`live_calls:${$page.params.subdomain}`, {});

    channel
      .join()
      .receive('ok', (resp: any) => {
        console.log(`Joined channel live_calls:${$page.params.subdomain}`, resp);
      })
      .receive('error', (resp: any) => {
        console.log(`Unable to join channel live_calls:${$page.params.subdomain}`, resp);
      });

    channel.on('live_call_update', (payload: any) => {
      if (payload.action === 'call_started') {
        const existingCallIndex = liveCalls.findIndex(
          (call) => call.callStoryId === payload.callData.callStoryId,
        );
        if (existingCallIndex >= 0) {
          // Update existing call
          liveCalls[existingCallIndex] = {
            ...liveCalls[existingCallIndex],
            currentParty: payload.callData.currentParty,
          };
          liveCalls = [...liveCalls];
          return;
        }
        const newCall: LiveCall = {
          callStoryId: payload.callData.callStoryId,
          startAt: payload.callData.startAt,
          currentParty: payload.callData.currentParty,
          direction: payload.callData.direction,
          caller: payload.callData.caller,
          callee: payload.callData.callee,
        };
        liveCalls = [...liveCalls, newCall];
      } else if (payload.action === 'call_ended') {
        liveCalls = liveCalls.filter((call) => call.callStoryId !== payload.callData.callStoryId);
      }
    });

    socket.onOpen(function () {
      console.info('Websocket connected for live calls');
    });

    socket.onClose(function () {
      console.info('Websocket disconnected for live calls');
    });

    socket.onError(function (error: any) {
      console.info('Websocket error for live calls', error);
    });

    // Update duration every second
    interval = setInterval(() => {
      liveCalls = [...liveCalls]; // Trigger reactivity
    }, 1000);
  });

  onDestroy(() => {
    if (interval) {
      clearInterval(interval);
    }
    if (socket) {
      socket.disconnect();
    }
  });
</script>

<div class="bg-white dark:bg-gray-800 rounded-lg shadow-lg p-6">
  <div class="flex items-center justify-between mb-6">
    <h3 class="text-xl font-bold dark:text-white">Live Calls</h3>
    <div class="flex items-center space-x-2">
      <div class="w-3 h-3 bg-green-500 rounded-full animate-pulse"></div>
      <span class="text-sm text-gray-500 dark:text-gray-400">Live</span>
    </div>
  </div>

  {#if loading}
    <div class="flex items-center justify-center py-8">
      <div class="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600"></div>
    </div>
  {:else if liveCalls.length === 0}
    <div class="text-center py-8">
      <div class="text-gray-400 dark:text-gray-500 mb-2">
        <svg class="mx-auto h-12 w-12" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M3 5a2 2 0 012-2h3.28a1 1 0 01.948.684l1.498 4.493a1 1 0 01-.502 1.21l-2.257 1.13a11.042 11.042 0 005.516 5.516l1.13-2.257a1 1 0 011.21-.502l4.493 1.498a1 1 0 01.684.949V19a2 2 0 01-2 2h-1C9.716 21 3 14.284 3 6V5z"
          />
        </svg>
      </div>
      <p class="text-gray-500 dark:text-gray-400">No active calls</p>
    </div>
  {:else}
    <div class="space-y-4">
      {#each liveCalls as call (call.callStoryId)}
        <div
          class="border border-gray-200 dark:border-gray-700 rounded-lg p-4 hover:bg-gray-50 dark:hover:bg-gray-700 transition-colors"
        >
          <div class="flex items-center justify-between mb-3">
            <div class="flex items-center space-x-3">
              <div class="w-3 h-3 bg-green-500 rounded-full animate-pulse"></div>
              <span
                class="px-2 py-1 text-xs font-medium rounded-full {call.direction === 'inbound'
                  ? 'bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200'
                  : 'bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200'}"
              >
                {getDirectionLabel(call.direction)}
              </span>
            </div>
            <span class="text-xs text-gray-500 dark:text-gray-400">
              {moment(call.startAt).format('HH:mm:ss')}
            </span>
          </div>

          <div class="grid grid-cols-1 md:grid-cols-3 gap-4 text-sm">
            <div>
              <span class="text-gray-500 dark:text-gray-400">From:</span>
              <span class="ml-2 font-medium text-gray-900 dark:text-white">
                {displayName(call.caller)}
              </span>
            </div>
            <div>
              <span class="text-gray-500 dark:text-gray-400">To:</span>
              <span class="ml-2 font-medium text-gray-900 dark:text-white">
                {displayName(call.callee)}
              </span>
            </div>
            <div>
              <span class="text-gray-500 dark:text-gray-400">Current Party:</span>
              <span class="ml-2 font-medium text-gray-900 dark:text-white">
                {displayName(call.currentParty)}
              </span>
            </div>
          </div>
        </div>
      {/each}
    </div>
  {/if}
</div>
