<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import { page } from '$app/state';
  import { browser } from '$app/environment';
  import { Socket } from 'phoenix';
  import { getIdTokenFromCookie } from '$lib/getIdTokenFromCookie';
  import { formatTime } from '$lib/format';
  import { partyName } from '$lib/party';
  import FormSection from './form/FormSection.svelte';
  import EmptyState from './form/EmptyState.svelte';
  import Pill from './Pill.svelte';
  import Spinner from './Icons/Spinner.svelte';

  type LiveCall = {
    callStoryId: string;
    startAt: string | null;
    currentParty: string | null;
    direction: string | null;
    caller: string | null;
    callee: string | null;
  };

  let liveCalls: LiveCall[] = $state([]);
  let socket: Socket | undefined;
  let loading = $state(true);

  async function fetchLiveCalls() {
    try {
      const response = await fetch(`/api/v2/${page.params.subdomain}/calls/live`);
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

  let interval: NodeJS.Timeout | undefined;

  onMount(async () => {
    await fetchLiveCalls();

    if (!browser) {
      return;
    }

    const idToken = getIdTokenFromCookie();

    socket = new Socket(`/ws`, {
      params: {
        subdomain: page.params.subdomain,
        token: idToken,
      },
    });

    socket.connect();

    const channel = socket.channel(`live_calls:${page.params.subdomain}`, {});

    channel
      .join()
      .receive('ok', (resp: any) => {
        console.log(`Joined channel live_calls:${page.params.subdomain}`, resp);
      })
      .receive('error', (resp: any) => {
        console.log(`Unable to join channel live_calls:${page.params.subdomain}`, resp);
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

<FormSection title="Live calls" description="Calls in progress, updated as they happen.">
  {#snippet aside()}
    <span class="flex items-center gap-2 text-sm text-gray-500 dark:text-gray-400">
      <span class="h-2.5 w-2.5 animate-pulse rounded-full bg-green-500" aria-hidden="true"></span>
      Live
    </span>
  {/snippet}

  {#if loading}
    <div class="flex items-center justify-center py-8">
      <Spinner />
    </div>
  {:else if liveCalls.length === 0}
    <EmptyState
      title="No calls in progress"
      description="A call shows up here the moment it starts, with who is on it."
    />
  {:else}
    <ul class="divide-y divide-gray-200 dark:divide-gray-700">
      {#each liveCalls as call (call.callStoryId)}
        <li class="flex flex-wrap items-center gap-x-6 gap-y-2 py-3 text-sm">
          <span
            class="h-2.5 w-2.5 animate-pulse rounded-full bg-green-500"
            aria-hidden="true"
          ></span>
          <Pill tone={call.direction === 'inbound' ? 'cyan' : 'blue'}>
            {getDirectionLabel(call.direction)}
          </Pill>
          <span class="font-medium text-gray-900 dark:text-white">
            {partyName(call.caller)} → {partyName(call.callee)}
          </span>
          <span class="text-gray-500 dark:text-gray-400">
            With <span class="font-medium text-gray-900 dark:text-white">
              {partyName(call.currentParty)}
            </span>
          </span>
          <span class="ms-auto text-xs text-gray-500 dark:text-gray-400">
            Started {formatTime(call.startAt)}
          </span>
        </li>
      {/each}
    </ul>
  {/if}
</FormSection>
