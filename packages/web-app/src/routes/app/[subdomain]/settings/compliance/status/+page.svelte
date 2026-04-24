<script lang="ts">
  import ComplianceTabs from '../../compliance/ComplianceTabs.svelte';
  import moment from 'moment-timezone';
  import { page } from '$app/stores';
  import { onDestroy, onMount } from 'svelte';
  import { browser } from '$app/environment';
  import { Socket } from 'phoenix';
  import { getIdTokenFromCookie } from '$lib/getIdTokenFromCookie';
  import { getJson } from '$lib/http';

  interface ComplianceTask {
    id: string;
    type: string;
    status: string;
    updatedAt: Date;
    data?: {
      fileName?: string;
    };
  }

  let complianceTasks: ComplianceTask[] = [];

  let socket: Socket | undefined;
  async function fetchComplianceTasks() {
    const result = await getJson<{ complianceTasks: ComplianceTask[] }>(
      `/api/v2/${$page.params.subdomain}/compliance/status`,
    );

    if (!result.ok) {
      complianceTasks = [];
      return;
    }

    complianceTasks = result.data.complianceTasks ?? [];
  }

  onMount(() => {
    if (!browser) {
      return;
    }

    fetchComplianceTasks();

    const idToken = getIdTokenFromCookie();
    console.log('idToken', idToken);

    socket = new Socket(`/ws`, {
      params: {
        subdomain: $page.params.subdomain,
        token: idToken,
      },
    });

    socket.connect();

    const channel = socket.channel(`compliance:${$page.params.subdomain}`, {});

    channel
      .join()
      .receive('ok', (resp: any) => {
        console.log(`Joined channel compliance:${$page.params.subdomain}`, resp);
      })
      .receive('error', (resp: any) => {
        console.log(`Unable to join channel compliance:${$page.params.subdomain}`, resp);
      });

    channel.on(`compliance_update`, (payload: any) => {
      const updatedTask = complianceTasks.find((t) => t.id === payload.complianceTaskId);
      if (updatedTask) {
        console.log(`Updating compliance task ${updatedTask.id} to ${payload.status}`);
        updatedTask.status = payload.status;
        updatedTask.updatedAt = new Date();
        complianceTasks = [...complianceTasks];
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

<ComplianceTabs />

<div class="relative overflow-x-auto shadow-md sm:rounded-lg">
  <table class="w-full text-sm text-left text-gray-500 dark:text-gray-400">
    <thead class="text-xs text-gray-700 uppercase bg-gray-50 dark:bg-gray-700 dark:text-gray-400">
      <tr>
        <th scope="col" class="px-6 py-3">Timestamp</th>
        <th scope="col" class="px-6 py-3">Type</th>
        <th scope="col" class="px-6 py-3">Status</th>
        <th scope="col" class="px-6 py-3">Action</th>
      </tr>
    </thead>
    <tbody>
      {#each complianceTasks as complianceTask}
        <tr class="bg-white border-b dark:bg-gray-900 dark:border-gray-700">
          <td class="px-6 py-4 font-medium text-gray-900 whitespace-nowrap dark:text-white">
            {moment(complianceTask.updatedAt).format('YYYY/MM/DD hh:mm a')}
          </td>
          <td class="px-6 py-4 font-medium text-gray-900 whitespace-nowrap dark:text-white">
            {complianceTask.type}
          </td>
          <th
            scope="row"
            class="px-6 py-4 font-medium text-gray-900 whitespace-nowrap dark:text-white"
          >
            {complianceTask.status}
          </th>
          {#if complianceTask.type === 'DOWNLOAD' && complianceTask.status === 'COMPLETED' && complianceTask.data?.fileName}
            <td class="px-6 py-4 font-medium">
              <a
                href={`/api/v2/${$page.params.subdomain}/compliance/downloads/${complianceTask.data.fileName}`}
                class="text-blue-600 dark:text-blue-500 hover:underline"
              >
                Download
              </a>
            </td>
          {/if}
        </tr>
      {/each}
    </tbody>
  </table>
</div>
