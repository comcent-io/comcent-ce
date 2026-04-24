<script lang="ts">
  import { browser } from '$app/environment';
  import Pagination from '$lib/components/Pagination.svelte';
  import { page } from '$app/stores';
  import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';
  import { goto } from '$app/navigation';
  import { getJson, postJson } from '$lib/http';

  export let data;

  interface numberToBeDeletedType {
    id: string;
    name: string;
  }

  let numberToBeDeleted: numberToBeDeletedType | null = null;
  let numbers: any[] = [];
  let currentPage = 1;
  let itemsPerPage = 10;
  let totalPages = 1;
  let totalCount = 0;
  let isLoading = false;
  let latestRequestId = 0;
  let lastFetchKey = '';

  let isDeletePopUp = false;
  let errorMessage = '';
  const subdomain = $page.params.subdomain;

  async function fetchNumbers() {
    const requestId = ++latestRequestId;
    const searchParams = $page.url.searchParams;
    const requestedCurrentPage = parseInt(searchParams.get('page') || '1', 10);
    const requestedItemsPerPage = parseInt(searchParams.get('itemsPerPage') || '10', 10);
    isLoading = true;

    const result = await getJson<{
      numbers?: any[];
      totalPages?: number;
      currentPage?: number;
      itemsPerPage?: number;
      totalCount?: number;
    }>(
      `/api/v2/${subdomain}/numbers?page=${requestedCurrentPage}&itemsPerPage=${requestedItemsPerPage}`,
    );

    if (requestId !== latestRequestId) return;

    currentPage = requestedCurrentPage;
    itemsPerPage = requestedItemsPerPage;

    if (!result.ok) {
      numbers = [];
      totalPages = 1;
      totalCount = 0;
      isLoading = false;
      errorMessage = result.error;
      return;
    }

    numbers = result.data.numbers ?? [];
    totalPages = result.data.totalPages ?? 1;
    currentPage = result.data.currentPage ?? requestedCurrentPage;
    itemsPerPage = result.data.itemsPerPage ?? requestedItemsPerPage;
    totalCount = result.data.totalCount ?? 0;
    isLoading = false;
  }

  $: if (browser) {
    const nextFetchKey = `${$page.url.search}|${$page.params.subdomain}`;
    if (nextFetchKey !== lastFetchKey) {
      lastFetchKey = nextFetchKey;
      fetchNumbers();
    }
  }

  function toggleDeletePopUp() {
    isDeletePopUp = !isDeletePopUp;
  }

  async function handleSubmit() {
    errorMessage = '';
    try {
      const response = await fetch(`/api/v2/${subdomain}/numbers/${numberToBeDeleted?.id}`, {
        method: 'DELETE',
      });
      if (!response.ok) throw new Error((await response.json()).error ?? response.statusText);
      goto(`/app/${subdomain}/numbers`, { invalidateAll: true });
    } catch (error: any) {
      errorMessage = error.message;
    } finally {
      toggleDeletePopUp();
    }
  }

  async function setOrgDefaultNumber(id: string) {
    const result = await postJson(`/api/v2/${subdomain}/numbers/${id}/set-default`, {});
    if (!result.ok) {
      errorMessage = result.error;
      return;
    }

    errorMessage = '';
    await fetchNumbers();
  }
</script>

<h3 class="text-3xl font-bold dark:text-white">Numbers</h3>

<div class="my-4">
  <a
    href={`${data.basePath}/numbers/create`}
    id="add-new-no-btn"
    class="text-white bg-blue-700 hover:bg-blue-800 focus:ring-4 focus:ring-blue-300 font-medium rounded-lg text-sm px-5 py-2.5 mr-2 mb-2 dark:bg-blue-600 dark:hover:bg-blue-700 focus:outline-none dark:focus:ring-blue-800"
  >
    Add
  </a>
</div>

{#if errorMessage}
  <div class="text-red-500 mb-4">
    {errorMessage}
  </div>
{/if}

{#if isDeletePopUp}
  <ConfirmDialog
    message={`Are you sure you want to delete the ${numberToBeDeleted?.name}?`}
    on:cancel={toggleDeletePopUp}
    on:confirm={handleSubmit}
  />
{/if}

<div class="relative overflow-x-auto shadow-md sm:rounded-lg">
  <table class="w-full text-sm text-left text-gray-500 dark:text-gray-400">
    <thead class="text-xs text-gray-700 uppercase bg-gray-50 dark:bg-gray-700 dark:text-gray-400">
      <tr>
        <th scope="col" class="px-6 py-3">Name</th>
        <th scope="col" class="px-6 py-3">Number</th>
        <th scope="col" class="px-6 py-3">Trunk</th>
        <th scope="col" class="px-6 py-3">Default</th>
        <th scope="col" class="px-6 py-3">Action</th>
      </tr>
    </thead>
    <tbody>
      {#if isLoading}
        <tr class="bg-white border-b dark:bg-gray-900 dark:border-gray-700">
          <td class="px-6 py-4" colspan="5">Loading...</td>
        </tr>
      {:else}
        {#each numbers as number}
          <tr class="bg-white border-b dark:bg-gray-900 dark:border-gray-700">
            <th
              scope="row"
              class="px-6 py-4 font-medium text-gray-900 whitespace-nowrap dark:text-white"
            >
              {number.name}
            </th>
            <td class="px-6 py-4">
              {number.number}
            </td>
            <td class="px-6 py-4">
              {number.sipTrunk.name}
            </td>
            <td class="px-6 py-4">
              {number.isDefaultOutboundNumber ? 'Yes' : ''}
            </td>
            <td class="flex space-x-10 px-6 py-4">
              <a
                href={`${data.basePath}/numbers/${number.id}/edit`}
                class="font-medium text-blue-600 dark:text-blue-500 hover:underline"
              >
                Edit
              </a>

              <button
                type="button"
                on:click={() => setOrgDefaultNumber(number.id)}
                class="font-medium text-blue-600 dark:text-blue-500 hover:underline"
              >
                Set As Default
              </button>

              <button
                type="button"
                on:click={toggleDeletePopUp}
                on:click={() => {
                  numberToBeDeleted = number;
                }}
                class="font-medium text-red-600 dark:text-red-500 hover:underline"
              >
                Delete
              </button>
            </td>
          </tr>
        {/each}
      {/if}
    </tbody>
  </table>
</div>

<Pagination
  baseUrl={`${data.basePath}/numbers`}
  {totalPages}
  {currentPage}
  {itemsPerPage}
  {totalCount}
/>
