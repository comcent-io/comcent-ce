<script lang="ts">
  import moment from 'moment';
  import { page } from '$app/stores';
  import Pagination from '$lib/components/Pagination.svelte';
  import { getJson } from '$lib/http';
  import toast from 'svelte-french-toast';
  import { goto } from '$app/navigation';

  let callStoriesResponse: any = null;
  $: callStories = callStoriesResponse?.callStories ?? [];
  $: totalCount = callStoriesResponse?.totalCount ?? 0;
  $: totalPages = Math.ceil(totalCount / itemsPerPage);

  let currentPage = 1;
  let itemsPerPage = 10;
  const subdomain = $page.params.subdomain;
  let expandedRowIndex: number | null = null;
  let startDate = '';
  let endDate = '';
  let baseUrl = `/app/${subdomain}/settings/billing/usage`;
  let latestRequestId = 0;

  $: {
    const searchParams = $page.url.searchParams;
    currentPage = parseInt(searchParams.get('page') || '1', 10);
    itemsPerPage = parseInt(searchParams.get('itemsPerPage') || '10', 10);
    fetchData();
  }

  $: {
    if (startDate && endDate) {
      baseUrl = `/app/${subdomain}/settings/billing/usage?startDate=${startDate}&endDate=${endDate}`;
    }
  }

  const toggleRow = (index: number) => {
    expandedRowIndex = expandedRowIndex === index ? null : index;
  };

  const orgAuditLogTypes: any = {
    CALL_TALK_TIME: { name: 'Talk Time', units: 'minutes' },
    CALL_TRANSCRIPTION: { name: 'Transcription', units: 'minutes' },
    CALL_SENTIMENT_ANALYSIS: {
      name: 'Sentiment Analysis',
      units: 'minutes',
    },
    CALL_SUMMARY_ANALYSIS: {
      name: 'Summary Analysis',
      units: 'minutes',
    },
    CALL_RECORDING_S3_FILE_SIZE: { name: 'Recording File Size (S3)', units: 'KB' },
    VOICEBOT: { name: 'Voicebot', units: 'minutes' },
  };

  async function fetchData() {
    const requestId = ++latestRequestId;
    const requestedCurrentPage = currentPage;
    const requestedItemsPerPage = itemsPerPage;
    const requestedStartDate = startDate;
    const requestedEndDate = endDate;

    const result = await getJson(
      `/api/v2/${subdomain}/billing/usage?page=${currentPage.toString()}&itemsPerPage=${itemsPerPage.toString()}&startDate=${startDate}&endDate=${endDate}`,
    );
    if (requestId !== latestRequestId) return;
    if (requestedCurrentPage !== currentPage) return;
    if (requestedItemsPerPage !== itemsPerPage) return;
    if (requestedStartDate !== startDate) return;
    if (requestedEndDate !== endDate) return;
    if (!result.ok) {
      toast.error(result.error || 'Failed to fetch data');
      return;
    }

    callStoriesResponse = result.data;
  }

  async function updateUsageUrl(nextPage: number, nextItemsPerPage: number) {
    const nextUrl = new URL(baseUrl, $page.url.origin);
    nextUrl.searchParams.set('page', nextPage.toString());
    nextUrl.searchParams.set('itemsPerPage', nextItemsPerPage.toString());
    await goto(`${nextUrl.pathname}${nextUrl.search}`, {
      replaceState: true,
      noScroll: true,
      keepFocus: true,
    });
  }

  async function handlePageChange(pageNumber: number) {
    currentPage = pageNumber;
    await updateUsageUrl(pageNumber, itemsPerPage);
    await fetchData();
  }

  async function handleItemsPerPageChange(nextItemsPerPage: number) {
    itemsPerPage = nextItemsPerPage;
    currentPage = 1;
    await updateUsageUrl(1, nextItemsPerPage);
    await fetchData();
  }

  async function handleSubmit(event: Event) {
    event.preventDefault();
    if (startDate && endDate) {
      if (currentPage !== 1) {
        currentPage = 1;
      }
      goto(`${baseUrl}&page=${currentPage}&itemsPerPage=${itemsPerPage}`);
    }
    await fetchData();
  }
</script>

<h3 class="text-3xl font-bold dark:text-white mb-4 mt-4">Wallet Usage</h3>

<form method="POST" on:submit|preventDefault={handleSubmit} class="mt-4">
  <div class="flex items-center mb-6">
    <div class="relative">
      <input
        id="datepicker-range-start"
        name="startDate"
        type="date"
        bind:value={startDate}
        required
        class="bg-gray-50 border border-gray-300 text-gray-900 text-sm rounded-lg focus:ring-blue-500 focus:border-blue-500 block w-full ps-6 p-2.5 dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500"
      />
    </div>
    <span class="mx-4 text-gray-500">to</span>
    <div class="relative">
      <input
        id="datepicker-range-end"
        name="endDate"
        type="date"
        bind:value={endDate}
        required
        class="bg-gray-50 border border-gray-300 text-gray-900 text-sm rounded-lg focus:ring-blue-500 focus:border-blue-500 block w-full ps-6 p-2.5 dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500"
      />
    </div>
    <button
      type="submit"
      class="ml-4 px-4 py-2 text-sm font-medium text-white bg-blue-700 hover:bg-blue-800 border border-transparent rounded-md focus:ring-blue-300 dark:bg-blue-600 dark:hover:bg-blue-700 dark:focus:ring-blue-800"
    >
      Apply
    </button>
  </div>
</form>

<div class="mt-4 relative overflow-x-auto shadow-md sm:rounded-lg">
  <table class="w-full text-sm text-left rtl:text-right text-gray-500 dark:text-gray-400">
    <thead class="text-xs text-gray-700 uppercase bg-gray-50 dark:bg-gray-700 dark:text-gray-400">
      <tr>
        <th scope="col" class="px-6 py-3">Date Time</th>
        <th scope="col" class="px-6 py-3">Caller</th>
        <th scope="col" class="px-6 py-3">Callee</th>
        <th scope="col" class="px-6 py-3">Price</th>
        <th scope="col" class="px-6 py-3">Action</th>
      </tr>
    </thead>
    <tbody>
      {#each callStories as callStory, callStoryIndex}
        <!-- Parent Row -->
        <tr class="bg-white border-b dark:bg-gray-900 dark:border-gray-700">
          <td class="px-6 py-4">
            {moment(callStory.startAt).format('YYYY/MM/DD hh:mm a')}
          </td>
          <td class="px-6 py-4" id="caller">{callStory.caller}</td>
          <td class="px-6 py-4">{callStory.callee}</td>
          <td class="px-6 py-4">
            $ {Number(callStory.totalPrice).toFixed(3)}
          </td>
          <td class="px-6 py-4">
            <button
              type="button"
              on:click={() => toggleRow(callStoryIndex)}
              class="font-medium text-blue-600 dark:text-blue-500 hover:underline"
            >
              {expandedRowIndex === callStoryIndex ? 'Hide details' : 'View details'}
            </button>
          </td>
        </tr>
        <!-- Inner Table Row -->
        {#if expandedRowIndex === callStoryIndex}
          <tr class="bg-gray-100 dark:bg-gray-800">
            <td colspan="5" class="p-4">
              <table
                class="w-full text-sm text-left rtl:text-right text-gray-500 dark:text-gray-400"
              >
                <thead
                  class="text-xs text-gray-700 uppercase bg-gray-200 dark:bg-gray-700 dark:text-gray-400"
                >
                  <tr>
                    <th scope="col" class="px-6 py-3">Type</th>
                    <th scope="col" class="px-6 py-3">Quantity</th>
                    <th scope="col" class="px-6 py-3">Price</th>
                  </tr>
                </thead>
                <tbody>
                  {#each callStory.orgAuditLogs as orgAuditLog}
                    <tr class="border-b dark:border-gray-700">
                      <td class="px-6 py-4">{orgAuditLogTypes[orgAuditLog.type].name}</td>
                      <td class="px-6 py-4">
                        {orgAuditLog.quantity}
                        {orgAuditLogTypes[orgAuditLog.type].units}
                      </td>
                      <td class="px-6 py-4">$ {Number(orgAuditLog.price).toFixed(3)}</td>
                    </tr>
                  {/each}
                </tbody>
              </table>
            </td>
          </tr>
        {/if}
      {/each}
    </tbody>
  </table>
</div>

<Pagination
  {baseUrl}
  {totalPages}
  {currentPage}
  {itemsPerPage}
  {totalCount}
  onPageChange={handlePageChange}
  onItemsPerPageChange={handleItemsPerPageChange}
/>
