<script lang="ts">
  import { page } from '$app/state';
  import { onDestroy, onMount } from 'svelte';
  import { browser } from '$app/environment';
  import { Socket } from 'phoenix';
  import { getIdTokenFromCookie } from '$lib/getIdTokenFromCookie';
  import Card from '$lib/components/Card.svelte';
  import PartyAvatar from '$lib/components/PartyAvatar.svelte';
  import Pill from '$lib/components/Pill.svelte';
  import Spinner from '$lib/components/Icons/Spinner.svelte';
  import EmptyState from '$lib/components/form/EmptyState.svelte';
  import PageHeader from '$lib/components/form/PageHeader.svelte';
  import { partyName } from '$lib/party';

  type WaitingCall = {
    fromUser: string;
    attemptingToConnect: boolean;
    dateTime: string;
    attemptingToConnectToMember?: {
      username: string;
    };
  };

  type AvailableMember = {
    username: string;
  };

  type QueueDashboardData = {
    queueName: string;
    waitingCalls: WaitingCall[];
    availableMembers: AvailableMember[];
    totalAgents: number;
  };

  let queueDashboardData: QueueDashboardData | undefined = $state();
  let loadFailed = $state(false);
  let columnsEl: HTMLDivElement | undefined = $state();
  let currentTime = new Date();

  // Function to calculate waiting time
  function getWaitingTime(dateTime: string): string {
    const startTime = new Date(dateTime);
    const diffInMinutes = Math.floor((currentTime.getTime() - startTime.getTime()) / (1000 * 60));
    if (diffInMinutes < 1) {
      return 'just now';
    } else if (diffInMinutes === 1) {
      return '1 minute';
    } else {
      return `${diffInMinutes} minutes`;
    }
  }

  // Update current time every minute
  let timeInterval: ReturnType<typeof setInterval>;
  onMount(() => {
    timeInterval = setInterval(() => {
      currentTime = new Date();
      // Force a re-render by updating a reactive variable
      queueDashboardData = queueDashboardData ? { ...queueDashboardData } : undefined;
    }, 60000); // Update every minute
  });

  onDestroy(() => {
    if (timeInterval) {
      clearInterval(timeInterval);
    }
  });

  // Function to update line positions
  function updateLinePositions() {
    if (!queueDashboardData) return;

    const data = queueDashboardData;
    // Create map of available members for O(1) lookup
    const availableMemberMap: Record<string, AvailableMember & { index: number }> = {};
    data.availableMembers.forEach((member, index) => {
      availableMemberMap[member.username] = { ...member, index };
    });

    // Single pass through waiting calls
    data.waitingCalls.forEach((waitingCall: WaitingCall, i: number) => {
      const memberUsername = waitingCall.attemptingToConnectToMember?.username;
      if (!memberUsername) return;

      const memberWithIndex = availableMemberMap[memberUsername];
      if (!memberWithIndex) return;

      const waitingCallEl = document.getElementById(`waiting-call-${i}`);
      const availableMemberEl = document.getElementById(
        `available-member-${memberWithIndex.index}`,
      );
      const line = document.getElementById(`line-${memberUsername}`);

      if (waitingCallEl && availableMemberEl && line) {
        const waitingCallRect = waitingCallEl.getBoundingClientRect();
        const availableMemberRect = availableMemberEl.getBoundingClientRect();

        // The lines are drawn over the two columns, so measure from them.
        if (!columnsEl) return;

        const containerRect = columnsEl.getBoundingClientRect();

        // Calculate start point from the incoming call number
        const startX = waitingCallRect.right - containerRect.left;
        const startY = waitingCallRect.top + waitingCallRect.height / 2 - containerRect.top;

        // Calculate end point at the available member div
        const endX = availableMemberRect.left - containerRect.left;
        const endY = availableMemberRect.top + availableMemberRect.height / 2 - containerRect.top;

        // Update line attributes
        line.setAttribute('x1', startX.toString());
        line.setAttribute('y1', startY.toString());
        line.setAttribute('x2', endX.toString());
        line.setAttribute('y2', endY.toString());
      }
    });
  }

  let socket: Socket | undefined;
  onMount(() => {
    if (!browser) {
      return;
    }

    const idToken = getIdTokenFromCookie();
    if (!idToken) {
      console.error('No idToken found in cookie');
      return;
    }

    socket = new Socket(`/ws`, {
      params: {
        subdomain: page.params.subdomain,
        token: idToken,
      },
    });

    socket.connect();

    const channel = socket.channel(
      `queue_dashboard:${page.params.subdomain}:${page.params.id}`,
      {},
    );

    channel
      .join()
      .receive('ok', (resp: any) => {
        console.log(
          `Joined channel queue_dashboard:${page.params.subdomain}:${page.params.id}`,
          resp,
        );
      })
      .receive('error', (resp: any) => {
        console.log(
          `Unable to join channel queue_dashboard:${page.params.subdomain}:${page.params.id}`,
          resp,
        );
      });

    channel.on(`queue_dashboard_update`, (payload: any) => {
      queueDashboardData = payload;
      // Update line positions when data changes
      setTimeout(updateLinePositions, 0);
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

    // Initial update of line positions
    setTimeout(updateLinePositions, 0);

    // Update on window resize
    if (typeof window !== 'undefined') {
      window.addEventListener('resize', updateLinePositions);
    }
  });

  onDestroy(() => {
    if (socket) {
      socket.disconnect();
    }
    if (typeof window !== 'undefined') {
      window.removeEventListener('resize', updateLinePositions);
    }
  });

  onMount(async () => {
    const response = await fetch(`/api/v2/${page.params.subdomain}/queues/${page.params.id}/state`);
    if (!response.ok) {
      loadFailed = true;
      throw new Error((await response.json()).error ?? response.statusText);
    }
    const data = await response.json();
    queueDashboardData = data.state;
    // Update line positions after initial data load
    setTimeout(updateLinePositions, 0);
  });
</script>

<PageHeader
  title={queueDashboardData ? `${queueDashboardData.queueName} queue dashboard` : 'Queue dashboard'}
  description="The callers waiting in this queue right now, and the members free to take them."
  backHref={`/app/${page.params.subdomain}/queues`}
  backLabel="Queues"
/>

{#snippet stat(label: string, value: number, note: string)}
  <Card>
    <p class="text-sm font-medium text-gray-500 dark:text-gray-400">{label}</p>
    <p class="mt-3 text-3xl font-bold text-gray-900 dark:text-white">{value}</p>
    <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">{note}</p>
  </Card>
{/snippet}

{#snippet columnHeading(title: string, count: string)}
  <div
    class="mb-4 flex items-center justify-between gap-3 border-b border-gray-200 pb-3 dark:border-gray-700"
  >
    <h4 class="text-lg font-semibold text-gray-900 dark:text-white">{title}</h4>
    <Pill>{count}</Pill>
  </div>
{/snippet}

{#if queueDashboardData}
  <div class="space-y-6">
    <div class="grid grid-cols-1 gap-4 sm:grid-cols-3">
      {@render stat(
        'Waiting calls',
        queueDashboardData.waitingCalls.length,
        'callers in the queue',
      )}
      {@render stat(
        'Available members',
        queueDashboardData.availableMembers.length,
        'free to take a call',
      )}
      {@render stat('Total members', queueDashboardData.totalAgents, 'in this queue')}
    </div>

    <div class="relative grid grid-cols-2 gap-8" bind:this={columnsEl}>
      <!-- Waiting calls -->
      <Card>
        {@render columnHeading('Waiting calls', String(queueDashboardData.waitingCalls.length))}
        {#if queueDashboardData.waitingCalls.length === 0}
          <EmptyState title="No one is waiting" description="Callers show here as they queue." />
        {:else}
          <div class="space-y-3">
            {#each queueDashboardData.waitingCalls as waitingCall, i (i)}
              <div class="flex items-center gap-3">
                <PartyAvatar party={waitingCall.fromUser} />
                <div class="min-w-0 flex-1">
                  <p class="truncate text-sm font-medium text-gray-900 dark:text-white">
                    {partyName(waitingCall.fromUser)}
                  </p>
                  <p class="text-xs text-gray-500 dark:text-gray-400">
                    Waiting since {getWaitingTime(waitingCall.dateTime)}
                  </p>
                </div>
                {#if waitingCall.attemptingToConnect}
                  <Pill tone="amber" dot>Connecting</Pill>
                {:else}
                  <Pill tone="red" dot>Waiting</Pill>
                {/if}
                <div
                  class="h-8 w-1.5 shrink-0 rounded-full {waitingCall.attemptingToConnect
                    ? 'bg-amber-500'
                    : 'bg-red-500'}"
                  id="waiting-call-{i}"
                ></div>
              </div>
            {/each}
          </div>
        {/if}
      </Card>

      <!-- Available members -->
      <Card>
        {@render columnHeading(
          'Available members',
          `${queueDashboardData.availableMembers.length} of ${queueDashboardData.totalAgents}`,
        )}
        {#if queueDashboardData.availableMembers.length === 0}
          <EmptyState
            title="No member is available"
            description="Members show here when they are free to take this queue's calls."
          />
        {:else}
          <div class="space-y-3">
            {#each queueDashboardData.availableMembers as availableMember, j (j)}
              {@const offered = queueDashboardData.waitingCalls.some(
                (call) => call.attemptingToConnectToMember?.username === availableMember.username,
              )}
              <div class="flex items-center gap-3">
                <div
                  class="h-8 w-1.5 shrink-0 rounded-full {offered
                    ? 'bg-amber-500'
                    : 'bg-green-500'}"
                  id="available-member-{j}"
                ></div>
                <PartyAvatar party={availableMember.username} />
                <p
                  class="min-w-0 flex-1 truncate text-sm font-medium text-gray-900 dark:text-white"
                >
                  {availableMember.username}
                </p>
                {#if offered}
                  <Pill tone="amber" dot>Offered a call</Pill>
                {:else}
                  <Pill tone="green" dot>Available</Pill>
                {/if}
              </div>
            {/each}
          </div>
        {/if}
      </Card>

      <!-- Lines from each caller to the member being offered the call -->
      {#each queueDashboardData.waitingCalls as waitingCall, i (i)}
        {#if waitingCall.attemptingToConnectToMember?.username}
          <div class="pointer-events-none absolute left-0 top-0 h-full w-full" style="z-index: 1;">
            <svg class="absolute left-0 top-0 h-full w-full" style="overflow: visible;">
              <line
                x1="0"
                y1="0"
                x2="100%"
                y2="0"
                class="stroke-current text-amber-500"
                style="stroke-width: 2;"
                id="line-{waitingCall.attemptingToConnectToMember.username}"
              />
            </svg>
          </div>
        {/if}
      {/each}
    </div>
  </div>
{:else if loadFailed}
  <EmptyState title="Queue not found" description="It may have been deleted." />
{:else}
  <div class="flex justify-center py-10"><Spinner /></div>
{/if}

<style>
  /* Add styles for the connecting lines */
  svg line {
    stroke-dasharray: 5;
    animation: dash 1s linear infinite;
  }

  @keyframes dash {
    to {
      stroke-dashoffset: -10;
    }
  }
</style>
