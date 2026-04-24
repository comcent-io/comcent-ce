<script lang="ts">
  import NextIcon from '$lib/components/Icons/NextIcon.svelte';
  import PreviousIcon from '$lib/components/Icons/PreviousIcon.svelte';
  import _ from 'lodash';
  import { goto } from '$app/navigation';
  import { page } from '$app/stores';

  export let baseUrl: string;
  export let totalPages: number;
  export let currentPage: number;
  export let itemsPerPage: number;
  export let totalCount: number;
  export let onPageChange: ((page: number) => void) | undefined = undefined;
  export let onItemsPerPageChange: ((itemsPerPage: number) => void) | undefined = undefined;

  const appendQueryParams = (url: string | undefined, params: Record<string, string | number>) => {
    const origin = $page.url.origin;
    if (origin && url) {
      const urlObj = new URL(url, origin);
      Object.entries(params).forEach(([key, value]) => {
        urlObj.searchParams.set(key, value.toString());
      });
      return urlObj.toString();
    }

    return url || '';
  };

  let pageNumbers: any[] = [];
  $: if (currentPage === 1 || currentPage === 2) {
    pageNumbers = _.range(1, Math.min(3, totalPages) + 1);
  } else if (currentPage > 2) {
    pageNumbers =
      totalPages > currentPage
        ? [currentPage - 1, currentPage, currentPage + 1]
        : [currentPage - 2, currentPage - 1, currentPage];
  }

  let form: any = null;
  const handleSelectChange = async () => {
    const totalPages = Math.ceil(totalCount / itemsPerPage);
    const newPage = totalPages < currentPage ? totalPages : currentPage;

    if (onItemsPerPageChange) {
      onItemsPerPageChange(itemsPerPage);
    } else {
      await goto(appendQueryParams(baseUrl, { page: newPage, itemsPerPage }));
    }
  };

  const handlePageClick = async (page: number) => {
    if (onPageChange) {
      onPageChange(page);
    } else {
      await goto(appendQueryParams(baseUrl, { page, itemsPerPage }));
    }
  };
</script>

<div class="flex space-x-4 mt-4">
  <nav aria-label="Page navigation example">
    <ul class="inline-flex -space-x-px text-base h-10">
      {#if totalPages > 3 && currentPage > 2}
        <li
          class="first:rounded-s-lg last:rounded-e-lg flex items-center justify-center px-4 h-10 ms-0 leading-tight text-gray-500 bg-white border border-gray-300 hover:bg-gray-100 hover:text-gray-700 dark:bg-gray-800 dark:border-gray-700 dark:text-gray-400 dark:hover:bg-gray-700 dark:hover:text-white cursor-pointer"
          on:click={() => handlePageClick(1)}
        >
          <span class="">Start</span>
        </li>
      {/if}

      {#if currentPage > 1}
        <li
          class="first:rounded-s-lg last:rounded-e-lg flex items-center justify-center px-4 h-10 ms-0 leading-tight text-gray-500 bg-white border border-gray-300 hover:bg-gray-100 hover:text-gray-700 dark:bg-gray-800 dark:border-gray-700 dark:text-gray-400 dark:hover:bg-gray-700 dark:hover:text-white cursor-pointer"
          on:click={() => handlePageClick(currentPage - 1)}
        >
          <span class="sr-only">Previous</span>
          <PreviousIcon />
        </li>
      {/if}

      {#each pageNumbers as page}
        <li
          class="{currentPage === page
            ? 'bg-gray-100 text-gray-700 dark:bg-gray-700 dark:text-white text-bold'
            : ''} first:rounded-s-lg last:rounded-e-lg flex items-center justify-center px-4 h-10 ms-0 leading-tight text-gray-500 bg-white border border-gray-300 hover:bg-gray-100 hover:text-gray-700 dark:bg-gray-800 dark:border-gray-700 dark:text-gray-400 dark:hover:bg-gray-700 dark:hover:text-white cursor-pointer"
          on:click={() => handlePageClick(page)}
        >
          <span>
            {page}
          </span>
        </li>
      {/each}

      {#if currentPage < totalPages}
        <li
          class="first:rounded-s-lg last:rounded-e-lg flex items-center justify-center px-4 h-10 ms-0 leading-tight text-gray-500 bg-white border border-gray-300 hover:bg-gray-100 hover:text-gray-700 dark:bg-gray-800 dark:border-gray-700 dark:text-gray-400 dark:hover:bg-gray-700 dark:hover:text-white cursor-pointer"
          on:click={() => handlePageClick(currentPage + 1)}
        >
          <span class="sr-only">Next</span>
          <NextIcon />
        </li>
      {/if}

      {#if currentPage + 1 < totalPages && totalPages > 3}
        <li
          class="first:rounded-s-lg last:rounded-e-lg flex items-center justify-center px-4 h-10 ms-0 leading-tight text-gray-500 bg-white border border-gray-300 hover:bg-gray-100 hover:text-gray-700 dark:bg-gray-800 dark:border-gray-700 dark:text-gray-400 dark:hover:bg-gray-700 dark:hover:text-white cursor-pointer"
          on:click={() => handlePageClick(totalPages)}
        >
          <span>End</span>
        </li>
      {/if}
    </ul>
  </nav>

  <form bind:this={form}>
    <div class="flex h-10 space-x-1">
      <input type="hidden" name="page" value={currentPage} />
      <label for="items" class="mb-2 text-sm font-medium text-gray-900 dark:text-white">
        Number of items
      </label>
      <select
        name="itemsPerPage"
        id="itemsPerPage"
        bind:value={itemsPerPage}
        on:change={handleSelectChange}
        on:click|preventDefault
        class="bg-gray-50 border border-gray-300 text-gray-900 text-sm rounded-lg focus:ring-blue-500 focus:border-blue-500 block w-full p-2.5 dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500"
      >
        <option value={5}>5</option>
        <option value={10}>10</option>
        <option value={20}>20</option>
        <option value={50}>50</option>
      </select>
    </div>
  </form>
</div>
