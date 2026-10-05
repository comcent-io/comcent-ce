<script lang="ts">
  import { browser } from '$app/environment';
  import { page } from '$app/state';
  import { getJson } from '$lib/http';
  import TimeSince from './TimeSince.svelte';
  import { onDestroy, onMount, untrack } from 'svelte';
  import { Socket } from 'phoenix';
  import { getIdTokenFromCookie } from '$lib/getIdTokenFromCookie';
  import { publicSipUserRootDomain } from '$lib/publicConfig';
  import Pill from '$lib/components/Pill.svelte';
  import PresenceDot from '$lib/components/PresenceDot.svelte';
  import Table from '$lib/components/Table.svelte';
  import UserAvatar from '$lib/components/UserAvatar.svelte';
  import EmptyState from '$lib/components/form/EmptyState.svelte';
  import PageHeader from '$lib/components/form/PageHeader.svelte';

  const sipDomain = publicSipUserRootDomain || 'example.com';

  let members: any[] = $state([]);
  let loading = $state(true);
  let lastFetchKey = '';

  async function fetchMembers() {
    const result = await getJson<{ members: any[] }>(`/api/v2/${page.params.subdomain}/members`);
    loading = false;
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

  // Refetch when the URL or the org changes. The fetch itself is untracked,
  // so the state it reads and writes does not re-run this.
  $effect(() => {
    const nextFetchKey = page.params.subdomain ?? '';
    if (nextFetchKey !== lastFetchKey) {
      lastFetchKey = nextFetchKey;
      untrack(() => fetchMembers());
    }
  });
</script>

<PageHeader
  title="Presence"
  description="Who on your team is available, on a call, on a break or logged out right now, and for how long. It updates live."
/>

<Table columns={['Member', 'SIP address', 'Status']} {loading} isEmpty={members.length === 0}>
  {#snippet empty()}
    <EmptyState
      title="No members yet"
      description="Invite your team from Members. Once they sign in, you can see here who is free to take a call."
    />
  {/snippet}
  {#each members as member (member.user.id)}
    <tr>
      <td>
        <div class="flex items-center gap-3">
          <span class="relative shrink-0">
            <UserAvatar
              picture={member.user.picture}
              name={member.user.name}
              email={member.user.email}
            />
            <!-- The status dot on the avatar, ringed so it reads on any photo. -->
            <span
              class="absolute -bottom-0.5 -right-0.5 flex rounded-full ring-2 ring-white dark:ring-gray-800"
            >
              <PresenceDot presence={member.presence} size="md" />
            </span>
          </span>
          <span class="font-medium text-gray-900 dark:text-white">{member.user.name}</span>
        </div>
      </td>
      <td class="whitespace-nowrap">{member.username}@{page.params.subdomain}.{sipDomain}</td>
      <td>
        <div class="flex flex-wrap items-center gap-2">
          <Pill>
            <PresenceDot presence={member.presence} />
            {member.presence}
          </Pill>
          <TimeSince startAt={member.presenceSpan?.[0]?.startAt} />
        </div>
      </td>
    </tr>
  {/each}
</Table>
