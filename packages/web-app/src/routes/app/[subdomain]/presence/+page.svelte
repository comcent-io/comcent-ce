<script lang="ts">
  import { browser } from '$app/environment';
  import { page } from '$app/stores';
  import { getJson } from '$lib/http';
  import TimeSince from './TimeSince.svelte';
  import { onDestroy, onMount } from 'svelte';
  import { Socket } from 'phoenix';
  import { getIdTokenFromCookie } from '$lib/getIdTokenFromCookie';
  import { env } from '$env/dynamic/public';

  const sipDomain = env.PUBLIC_SIP_DOMAIN || 'example.com';

  let members: any[] = [];
  let lastFetchKey = '';

  const colors: Record<string, string> = {
    Available: 'bg-green-600',
    'Logged Out': 'bg-gray-400',
    'On Call': 'bg-red-600',
    'On Break': 'bg-yellow-600',
  };

  async function fetchMembers() {
    const result = await getJson<{ members: any[] }>(`/api/v2/${$page.params.subdomain}/members`);
    if (!result.ok) {
      members = [];
      return;
    }

    members = result.data.members ?? [];
  }

  let socket: Socket | undefined;
  onMount(() => {
    if (!browser) {
      return;
    }

    fetchMembers();

    const idToken = getIdTokenFromCookie();
    console.log('idToken', idToken);

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
      const updatedMember = members.find((m) => m.user.id === payload.userId);
      if (updatedMember) {
        console.log(`Updating member ${updatedMember.user.name} to ${payload.presence}`);
        updatedMember.presence = payload.presence;
        updatedMember.presenceSpan = [{ startAt: new Date() }];
        members = [...members];
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

  $: if (browser) {
    const nextFetchKey = $page.params.subdomain;
    if (nextFetchKey !== lastFetchKey) {
      lastFetchKey = nextFetchKey;
      fetchMembers();
    }
  }
</script>

<h3 class="text-3xl font-bold dark:text-white mb-5">Presence</h3>

<div class="flex gap-4 flex-wrap -mx-2">
  {#each members as member}
    <div
      class="p-4 w-full max-w-sm bg-white border border-gray-200 rounded-lg shadow dark:bg-gray-800 dark:border-gray-700"
    >
      <div class="flex gap-2 items-center">
        <img
          class="w-16 h-16 mb-3 rounded-full shadow-lg"
          src={member.user.picture}
          alt="Profile"
        />
        <div class="object-cover">
          <h5 class="text-md font-medium text-gray-900 dark:text-white">{member.user.name}</h5>
          <div class="text-sm text-gray-500 dark:text-gray-400">
            {member.username}@{$page.params.subdomain}.{sipDomain}
          </div>
          <div class="text-sm text-gray-500 dark:text-gray-400">
            <div class="inline-block w-2 h-2 rounded-full {colors[member.presence]}"></div>
            {member.presence}
            <TimeSince startAt={member.presenceSpan?.[0]?.startAt} />
          </div>
        </div>
      </div>
    </div>
  {/each}
</div>
