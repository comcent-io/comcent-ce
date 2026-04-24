<script lang="ts">
  import { page } from '$app/stores';
  import { onDestroy, onMount } from 'svelte';
  import { browser } from '$app/environment';
  import { Socket } from 'phoenix';
  import { getIdTokenFromCookie } from '$lib/getIdTokenFromCookie';

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

  let queueDashboardData: QueueDashboardData | undefined;
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
        const containerEl = waitingCallEl.parentElement?.parentElement?.parentElement;

        if (!containerEl) return;

        const containerRect = containerEl.getBoundingClientRect();

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
        subdomain: $page.params.subdomain,
        token: idToken,
      },
    });

    socket.connect();

    const channel = socket.channel(
      `queue_dashboard:${$page.params.subdomain}:${$page.params.id}`,
      {},
    );

    channel
      .join()
      .receive('ok', (resp: any) => {
        console.log(
          `Joined channel queue_dashboard:${$page.params.subdomain}:${$page.params.id}`,
          resp,
        );
      })
      .receive('error', (resp: any) => {
        console.log(
          `Unable to join channel queue_dashboard:${$page.params.subdomain}:${$page.params.id}`,
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
    const response = await fetch(
      `/api/v2/${$page.params.subdomain}/queues/${$page.params.id}/state`,
    );
    if (!response.ok) throw new Error((await response.json()).error ?? response.statusText);
    const data = await response.json();
    queueDashboardData = data.state;
    // Update line positions after initial data load
    setTimeout(updateLinePositions, 0);
  });
</script>

{#if queueDashboardData}
  <div class="p-6">
    <h3 class="text-3xl font-bold dark:text-white mb-8">
      {queueDashboardData.queueName} queue dashboard
    </h3>

    <!-- Agent Count Summary -->
    <div class="grid grid-cols-2 gap-8 relative">
      <div class="bg-white dark:bg-gray-800 rounded-lg shadow-lg p-6 mb-8">
        <div class="flex items-center justify-between">
          <div class="flex items-center space-x-8">
            <div class="text-center">
              <p class="text-2xl font-bold text-red-600 dark:text-red-400">
                {queueDashboardData.waitingCalls.length}
              </p>
              <p class="text-sm text-gray-600 dark:text-gray-400">Waiting Calls</p>
            </div>
          </div>
        </div>
      </div>

      <div class="bg-white dark:bg-gray-800 rounded-lg shadow-lg p-6 mb-8">
        <div class="flex items-center justify-end">
          <div class="flex items-center space-x-8">
            <div class="text-center">
              <p class="text-2xl font-bold text-green-600 dark:text-green-400">
                {queueDashboardData.availableMembers.length}
              </p>
              <p class="text-sm text-gray-600 dark:text-gray-400">Available Agents</p>
            </div>
            <div class="text-center">
              <p class="text-2xl font-bold text-blue-600 dark:text-blue-400">
                {queueDashboardData.totalAgents}
              </p>
              <p class="text-sm text-gray-600 dark:text-gray-400">Total Agents</p>
            </div>
          </div>
        </div>
      </div>
    </div>

    <div class="grid grid-cols-2 gap-8 relative">
      <!-- Incoming Calls Column -->
      <div class="bg-white dark:bg-gray-800 rounded-lg shadow-lg p-6">
        <h3
          class="text-xl font-bold dark:text-white mb-6 pb-2 border-b border-gray-200 dark:border-gray-700"
        >
          Incoming Calls ({queueDashboardData.waitingCalls.length})
        </h3>
        <div class="space-y-4">
          {#if queueDashboardData.waitingCalls.length === 0}
            <p class="text-gray-500 dark:text-gray-400 italic">No incoming calls</p>
          {:else}
            {#each queueDashboardData.waitingCalls as waitingCall, i}
              <div class="flex items-center space-x-4">
                <div class="flex flex-col">
                  <p class="text-sm font-semibold text-gray-900 dark:text-white">
                    {waitingCall.fromUser}
                  </p>
                  <p class="text-xs text-yellow-500 font-medium">
                    Waiting since {getWaitingTime(waitingCall.dateTime)}
                  </p>
                </div>
                <div
                  class="bg-{waitingCall.attemptingToConnect
                    ? 'yellow'
                    : 'red'}-500 shadow-sm relative w-2 h-7"
                  id="waiting-call-{i}"
                ></div>
              </div>
            {/each}
          {/if}
        </div>
      </div>

      <!-- Available Members Column -->
      <div class="bg-white dark:bg-gray-800 rounded-lg shadow-lg p-6">
        <h3
          class="text-xl font-bold dark:text-white mb-6 pb-2 border-b border-gray-200 dark:border-gray-700"
        >
          Available Members ({queueDashboardData.availableMembers
            .length}/{queueDashboardData.totalAgents})
        </h3>
        <div class="space-y-4">
          {#if queueDashboardData.availableMembers.length === 0}
            <p class="text-gray-500 dark:text-gray-400 italic">No available members</p>
          {:else}
            {#each queueDashboardData.availableMembers as availableMember, j}
              <div class="flex items-center space-x-4">
                <div
                  class="bg-{queueDashboardData.waitingCalls.some(
                    (call) =>
                      call.attemptingToConnectToMember?.username === availableMember.username,
                  )
                    ? 'yellow'
                    : 'red'}-500 shadow-sm relative w-2 h-7"
                  id="available-member-{j}"
                ></div>
                <p class="text-sm font-semibold text-gray-900 dark:text-white">
                  {availableMember.username}
                </p>
              </div>
            {/each}
          {/if}
        </div>
      </div>

      <!-- Connection Lines -->
      {#each queueDashboardData.waitingCalls as waitingCall}
        {#if waitingCall.attemptingToConnectToMember?.username}
          <div class="absolute top-0 left-0 w-full h-full pointer-events-none" style="z-index: 1;">
            <svg class="absolute top-0 left-0 w-full h-full" style="overflow: visible;">
              <line
                x1="0"
                y1="0"
                x2="100%"
                y2="0"
                class="stroke-current text-yellow-500"
                style="stroke-width: 2;"
                id="line-{waitingCall.attemptingToConnectToMember.username}"
              />
            </svg>
          </div>
        {/if}
      {/each}
    </div>
  </div>
{:else}
  <div class="p-6">
    <p class="text-md font-semibold text-red-500">Data not found</p>
  </div>
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
