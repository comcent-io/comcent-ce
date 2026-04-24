<script lang="ts">
  import { browser } from '$app/environment';
  import { page } from '$app/stores';
  import { goto } from '$app/navigation';
  import TableRow from '../../../call-story/TableRow.svelte';
  import CloseIcon from '$lib/components/Icons/CloseIcon.svelte';
  import WarningIcon from '$lib/components/Icons/WarningIcon.svelte';
  import SearchIcon from '$lib/components/Icons/SearchIcon.svelte';
  import ComplianceTabs from '../../compliance/ComplianceTabs.svelte';
  import { getJson, postJson } from '$lib/http';
  import toast from 'svelte-french-toast';

  const subdomain = $page.params.subdomain;
  let callStories: any[] = [];
  let error = '';
  let latestRequestId = 0;
  let lastFetchKey = '';

  let isDeletePopUp = false;
  function toggleDeletePopUp() {
    isDeletePopUp = !isDeletePopUp;
  }

  async function fetchCallStories() {
    const number = $page.url.searchParams.get('number');
    const requestId = ++latestRequestId;

    if (!number) {
      callStories = [];
      error = '';
      return;
    }

    const result = await getJson<{ callStories?: any[] }>(
      `/api/v2/${subdomain}/compliance/search?number=${encodeURIComponent(number)}`,
    );

    if (requestId !== latestRequestId) return;

    if (!result.ok) {
      callStories = [];
      error = result.error;
      return;
    }

    callStories = result.data.callStories ?? [];
    error = '';
  }

  $: if (browser) {
    const nextFetchKey = `${$page.url.search}|${$page.params.subdomain}`;
    if (nextFetchKey !== lastFetchKey) {
      lastFetchKey = nextFetchKey;
      fetchCallStories();
    }
  }

  async function handleSearch(event: Event) {
    event.preventDefault();
    const formData = new FormData(event.currentTarget as HTMLFormElement);
    const number = String(formData.get('number') || '');
    await goto(`${window.location.pathname}?number=${encodeURIComponent(number)}`);
  }

  async function handleDeleteCallStories(event: Event) {
    event.preventDefault();
    const number = $page.url.searchParams.get('number');
    const result = await postJson(`/api/v2/${subdomain}/compliance/delete`, { number });
    if (!result.ok) {
      toast.error('Error deleting call stories: ' + result.error);
      return;
    }

    toast.success('Call stories scheduled to delete');
    toggleDeletePopUp();
  }

  async function handleDownloadCallStories(event: Event) {
    event.preventDefault();
    const number = $page.url.searchParams.get('number');
    const result = await postJson(`/api/v2/${subdomain}/compliance/download`, { number });
    if (!result.ok) {
      toast.error('Error downloading call stories: ' + result.error);
      return;
    }

    toast.success('Call stories scheduled to download');
  }

  async function handleAnonymiseCallStories(event: Event) {
    event.preventDefault();
    const number = $page.url.searchParams.get('number');
    const result = await postJson(`/api/v2/${subdomain}/compliance/anonymise`, { number });
    if (!result.ok) {
      toast.error('Error anonymising call stories: ' + result.error);
      return;
    }

    toast.success('Call stories scheduled to annonymise');
  }
</script>

<ComplianceTabs />
<form class="max-w-md mx-auto" on:submit|preventDefault={handleSearch}>
  <label
    for="default-search"
    class="mb-2 text-sm font-medium text-gray-900 sr-only dark:text-white"
  >
    Search
  </label>
  <div class="relative">
    <div class="absolute inset-y-0 start-0 flex items-center ps-3 pointer-events-none">
      <SearchIcon />
    </div>
    <input
      name="number"
      type="search"
      id="default-search"
      class="block w-full p-4 ps-10 text-sm text-gray-900 border border-gray-300 rounded-lg bg-gray-50 focus:ring-blue-500 focus:border-blue-500 dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500"
      placeholder="Enter a customer number"
      required
      value={$page.url.searchParams.get('number')}
    />
    <button
      class="absolute inset-y-0 end-24 flex items-center ps-3 text-gray-400 bg-transparent hover:text-gray-900 dark:hover:text-white"
      type="button"
      on:click={() => goto(window.location.pathname)}
    >
      <CloseIcon />
    </button>
    <button
      type="submit"
      class="text-white absolute end-2.5 bottom-2.5 bg-blue-700 hover:bg-blue-800 focus:ring-4 focus:outline-none focus:ring-blue-300 font-medium rounded-lg text-sm px-4 py-2 dark:bg-blue-600 dark:hover:bg-blue-700 dark:focus:ring-blue-800"
    >
      Search
    </button>
  </div>
</form>

{#if error}
  <p class="mx-auto max-w-sm mt-4 text-red-600 dark:text-red-400 text-md font-semibold">
    {error}
  </p>
{/if}
{#if callStories.length > 0}
  <div>
    <div class="flex flex-wrap justify-between items-center">
      <p class="mt-4 text-black dark:text-white text-md font-semibold">
        {`Showing ${callStories.length} ${callStories.length === 1 ? 'item' : 'items'}`}
      </p>
      <div class="flex justify-end items-start mt-4 mr-4 space-x-2">
        <button
          on:click={toggleDeletePopUp}
          type="button"
          class="focus:outline-none text-white bg-red-700 hover:bg-red-800 focus:ring-4 focus:ring-red-300 font-medium rounded-lg text-sm px-5 py-2.5 me-2 mb-2 dark:bg-red-600 dark:hover:bg-red-700 dark:focus:ring-red-900"
        >
          Delete
        </button>
        <input name="number" type="hidden" required value={$page.url.searchParams.get('number')} />
        <button
          on:click={handleDownloadCallStories}
          type="button"
          class="text-white bg-blue-700 hover:bg-blue-800 focus:ring-4 focus:ring-blue-300 font-medium rounded-lg text-sm px-5 py-2.5 me-2 mb-2 dark:bg-blue-600 dark:hover:bg-blue-700 focus:outline-none dark:focus:ring-blue-800"
        >
          Download
        </button>
        <input name="number" type="hidden" required value={$page.url.searchParams.get('number')} />
        <button
          on:click={handleAnonymiseCallStories}
          type="button"
          class="py-2.5 px-5 me-2 mb-2 text-sm font-medium text-gray-900 focus:outline-none bg-white rounded-lg border border-gray-200 hover:bg-gray-100 hover:text-blue-700 focus:z-10 focus:ring-4 focus:ring-gray-100 dark:focus:ring-gray-700 dark:bg-gray-800 dark:text-gray-400 dark:border-gray-600 dark:hover:text-white dark:hover:bg-gray-700"
        >
          Anonymise
        </button>
      </div>
    </div>
    {#if isDeletePopUp}
      <div
        tabindex="-1"
        class="overflow-y-auto overflow-x-hidden fixed top-0 right-0 left-0 z-50 flex justify-center items-center w-full md:inset-0 h-[calc(100%-1rem)] max-h-full"
      >
        <div class="relative p-4 w-full max-w-md max-h-full">
          <div class="relative bg-white rounded-lg shadow dark:bg-gray-700">
            <button
              on:click={toggleDeletePopUp}
              type="button"
              class="absolute top-3 end-2.5 text-gray-400 bg-transparent hover:bg-gray-200 hover:text-gray-900 rounded-lg text-sm w-8 h-8 ms-auto inline-flex justify-center items-center dark:hover:bg-gray-600 dark:hover:text-white"
              data-modal-hide="popup-modal"
            >
              <CloseIcon />
            </button>
            <div class="p-4 md:p-5 text-center">
              <WarningIcon />
              <h3 class="mb-5 text-lg font-normal text-gray-500 dark:text-gray-400">
                Are you sure you want to delete this Call History?
              </h3>
              <div class="flex space-x-2 ml-16">
                <input
                  name="number"
                  type="hidden"
                  required
                  value={$page.url.searchParams.get('number')}
                />
                <button
                  on:click={handleDeleteCallStories}
                  type="button"
                  class="text-white bg-red-600 hover:bg-red-800 focus:ring-4 focus:outline-none focus:ring-red-300 dark:focus:ring-red-800 font-medium rounded-lg text-sm inline-flex items-center px-5 py-2.5 text-center"
                >
                  Yes, I'm sure
                </button>
                <button
                  on:click={toggleDeletePopUp}
                  type="button"
                  class="py-2.5 px-5 text-sm font-medium text-gray-900 focus:outline-none bg-white rounded-lg border border-gray-200 hover:bg-gray-100 hover:text-blue-700 focus:z-10 focus:ring-4 focus:ring-gray-100 dark:focus:ring-gray-700 dark:bg-gray-800 dark:text-gray-400 dark:border-gray-600 dark:hover:text-white dark:hover:bg-gray-700"
                >
                  No, cancel
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>
    {/if}
    <div class="mt-2 relative overflow-x-auto shadow-md sm:rounded-lg">
      <table class="w-full text-sm text-left rtl:text-right text-gray-500 dark:text-gray-400">
        <thead
          class="text-xs text-gray-700 uppercase bg-gray-50 dark:bg-gray-700 dark:text-gray-400"
        >
          <tr>
            <th scope="col" class="px-6 py-3">Date Time</th>
            <th scope="col" class="px-6 py-3">Direction</th>
            <th scope="col" class="px-6 py-3">Caller</th>
            <th scope="col" class="px-6 py-3">Callee</th>
            <th scope="col" class="px-6 py-3">Action</th>
          </tr>
        </thead>
        <tbody>
          {#each callStories as callStory}
            <TableRow {callStory} />
          {/each}
        </tbody>
      </table>
    </div>
  </div>
{/if}
