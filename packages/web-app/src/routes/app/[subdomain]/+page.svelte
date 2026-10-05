<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import { page } from '$app/state';
  import { browser } from '$app/environment';
  import { Socket } from 'phoenix';
  import { getIdTokenFromCookie } from '$lib/getIdTokenFromCookie';
  import LiveCalls from '$lib/components/LiveCalls.svelte';
  import Card from '$lib/components/Card.svelte';
  import PageHeader from '$lib/components/form/PageHeader.svelte';
  import PresenceDot from '$lib/components/PresenceDot.svelte';

  let status: { name: string; value: number }[] = $state([]);
  let socket: Socket | undefined;

  async function fetchStatus() {
    const response = await fetch(`/api/v2/${page.params.subdomain}/dashboard/aggregate-presence`);
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
        subdomain: page.params.subdomain,
        token: idToken,
      },
    });

    socket.connect();

    const channel = socket.channel(`presence:${page.params.subdomain}`, {});

    channel
      .join()
      .receive('ok', (resp: any) => {
        console.log(`Joined channel presence:${page.params.subdomain}`, resp);
      })
      .receive('error', (resp: any) => {
        console.log(`Unable to join channel presence:${page.params.subdomain}`, resp);
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

<PageHeader
  title="Dashboard"
  description="Your team's presence right now, and the calls in progress."
/>

<div class="space-y-6">
  <div class="grid grid-cols-2 gap-4 lg:grid-cols-4">
    {#each status as { name, value } (name)}
      <Card>
        <div class="flex items-center gap-2">
          <PresenceDot presence={name} size="md" />
          <p class="text-sm font-medium text-gray-500 dark:text-gray-400">{name}</p>
        </div>
        <p class="mt-3 text-3xl font-bold text-gray-900 dark:text-white">{value}</p>
        <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">
          {value === 1 ? 'member' : 'members'}
        </p>
      </Card>
    {/each}
  </div>

  <LiveCalls />
</div>
