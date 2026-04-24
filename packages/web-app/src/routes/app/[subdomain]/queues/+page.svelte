<script lang="ts">
  import { page } from '$app/stores';
  import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';
  import { goto } from '$app/navigation';
  import toast from 'svelte-french-toast';
  import Spinner from '$lib/components/Icons/Spinner.svelte';
  import { onMount } from 'svelte';

  export let data;

  let isDeletePopUp = false;
  let isDeleteInProgress = false;
  let queues: any[] = [];
  const subdomain = $page.params.subdomain;

  interface QueueToBeDeletedType {
    id: string;
    name: string;
  }

  let queueToBeDeleted: QueueToBeDeletedType | null = null;

  function toggleDeletePopUp() {
    isDeletePopUp = !isDeletePopUp;
  }

  onMount(async () => {
    try {
      const response = await fetch(`/api/v2/${subdomain}/queues`);
      if (!response.ok) throw new Error((await response.json()).error ?? response.statusText);
      const data = await response.json();
      queues = data.queues;
    } catch (error: any) {
      toast.error(`${error.message}`);
    }
  });

  async function handleDelete() {
    isDeletePopUp = false;
    isDeleteInProgress = true;
    const deletedQueue = queueToBeDeleted;
    try {
      const response = await fetch(`/api/v2/${subdomain}/queues/${deletedQueue?.id}`, {
        method: 'DELETE',
      });
      if (!response.ok) throw new Error((await response.json()).error ?? response.statusText);
      queues = queues.filter((queue) => queue.id !== deletedQueue?.id);
      queueToBeDeleted = null;
      toast.success(`${deletedQueue?.name} queue deleted successfully`);
    } catch (error: any) {
      toast.error(`${error.message}`);
    } finally {
      isDeleteInProgress = false;
    }
  }
</script>

<h3 class="text-3xl font-bold dark:text-white">Queues</h3>

<div class="my-4">
  <a
    href={`${data.basePath}/queues/create`}
    class="text-white bg-blue-700 hover:bg-blue-800 focus:ring-4 focus:ring-blue-300 font-medium rounded-lg text-sm px-5 py-2.5 mr-2 mb-2 dark:bg-blue-600 dark:hover:bg-blue-700 focus:outline-none dark:focus:ring-blue-800"
  >
    Add
  </a>
</div>

{#if isDeletePopUp}
  <ConfirmDialog
    message={`Are you sure you want to delete the ${queueToBeDeleted?.name}?`}
    on:cancel={toggleDeletePopUp}
    on:confirm={handleDelete}
  />
{/if}

<div class="relative overflow-x-auto shadow-md sm:rounded-lg">
  <table class="w-full text-sm text-left text-gray-500 dark:text-gray-400">
    <thead class="text-xs text-gray-700 uppercase bg-gray-50 dark:bg-gray-700 dark:text-gray-400">
      <tr>
        <th scope="col" class="px-6 py-3">Name</th>
        <th scope="col" class="px-6 py-3">Number</th>
        <th scope="col" class="px-6 py-3">Wrap Up Time</th>
        <th scope="col" class="px-6 py-3">Reject Delay Time</th>
        <th scope="col" class="px-6 py-3">Max No Answers</th>
        <th scope="col" class="px-6 py-3">Action</th>
      </tr>
    </thead>
    <tbody>
      {#each queues as queue}
        <tr class="bg-white border-b dark:bg-gray-900 dark:border-gray-700">
          <th
            scope="row"
            class="px-6 py-4 font-medium text-gray-900 whitespace-nowrap dark:text-white"
          >
            {queue.name}
          </th>
          <td class="px-6 py-4">
            {queue.extension}
          </td>
          <td class="px-6 py-4">
            {queue.wrapUpTime}
          </td>
          <td class="px-6 py-4">
            {queue.rejectDelayTime}
          </td>
          <td class="px-6 py-4">
            {queue.maxNoAnswers}
          </td>
          <td class="flex items-center space-x-4 px-6 py-4">
            <a
              href={`${data.basePath}/queues/${queue.id}/edit`}
              class="font-medium text-blue-600 dark:text-blue-500 hover:underline"
            >
              Edit
            </a>
            {#if isDeleteInProgress && queue.id === queueToBeDeleted?.id}
              <Spinner />
            {:else}
              <button
                type="button"
                on:click={() => {
                  queueToBeDeleted = queue;
                  toggleDeletePopUp();
                }}
                class="font-medium text-red-600 dark:text-red-500 hover:underline"
              >
                Delete
              </button>
            {/if}
            <a
              href={`${data.basePath}/queues/${queue.id}/dashboard`}
              class="font-medium text-blue-600 dark:text-blue-500 hover:underline"
            >
              Dashboard
            </a>
          </td>
        </tr>
      {/each}
    </tbody>
  </table>
</div>
