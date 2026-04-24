<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import { page } from '$app/stores';
  import { browser } from '$app/environment';
  import { Socket } from 'phoenix';
  import { getIdTokenFromCookie } from '$lib/getIdTokenFromCookie';
  import LiveCalls from '$lib/components/LiveCalls.svelte';

  let status: { name: string; value: number }[] = [];
  let socket: Socket | undefined;

  async function fetchStatus() {
    const response = await fetch(`/api/v2/${$page.params.subdomain}/dashboard/aggregate-presence`);
    if (!response.ok) throw new Error((await response.json()).error ?? response.statusText);
    const data = await response.json();
    status = data.status;
  }

  onMount(async () => {
    await fetchStatus();

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

    const channel = socket.channel(`presence:${$page.params.subdomain}`, {});

    channel
      .join()
      .receive('ok', (resp: any) => {
        console.log(`Joined channel presence:${$page.params.subdomain}`, resp);
      })
      .receive('error', (resp: any) => {
        console.log(`Unable to join channel presence:${$page.params.subdomain}`, resp);
      });

    channel.on(`presence_update`, (payload: any) => {
      if (payload.userId && payload.presence) {
        const previousPresence = payload.previousPresence;
        if (previousPresence) {
          const previousPresenceIndex = status.findIndex(
            (item) => item.name.toLowerCase() === previousPresence.toLowerCase(),
          );
          if (previousPresenceIndex !== -1) {
            status[previousPresenceIndex].value = Math.max(
              0,
              status[previousPresenceIndex].value - 1,
            );
          }
        }
        const statusIndex = status.findIndex(
          (item) => item.name.toLowerCase() === payload.presence.toLowerCase(),
        );
        if (statusIndex !== -1) {
          status[statusIndex].value += 1;
        }
        status = [...status];
      }
    });

    socket.onOpen(function () {
      console.info('Websocket connected');
    });

    socket.onClose(function () {
      console.info('Websocket disconnected');
    });

    socket.onError(function (error: any) {
      console.info('Websocket error', error);
    });
  });

  onDestroy(() => {
    if (socket) {
      socket.disconnect();
    }
  });
</script>

<h3 class="text-3xl font-bold dark:text-white">Dashboard</h3>

<br />
<br />
<div class="grid grid-cols-1 lg:grid-cols-4 gap-6">
  <!-- Status Cards -->
  <div class="lg:col-span-4">
    <div class="flex gap-2">
      {#each status as { name, value }}
        <div
          class="w-1/4 max-w-xs p-6 bg-white border border-gray-200 rounded-lg shadow dark:bg-gray-800 dark:border-gray-700 text-center"
        >
          <h5 class="mb-2 text-2xl font-bold tracking-tight text-gray-900 dark:text-white">
            {value}
          </h5>
          <p class="mb-3 font-normal text-gray-700 dark:text-gray-400">{name}</p>
        </div>
      {/each}
    </div>
  </div>

  <!-- Live Calls -->
  <div class="lg:col-span-4">
    <LiveCalls />
  </div>
</div>
