<script lang="ts">
  import { browser } from '$app/environment';
  import Pagination from '$lib/components/Pagination.svelte';
  import { getJson } from '$lib/http';
  import moment from 'moment';
  import { page } from '$app/stores';

  const subdomain = $page.params.subdomain;
  let transactions: any[] = [];
  let totalPages = 0;
  let currentPage = 1;
  let itemsPerPage = 10;
  let totalCount = 0;
  let latestRequestId = 0;
  let lastFetchKey = '';

  async function fetchTransactions() {
    const requestId = ++latestRequestId;
    const searchParams = $page.url.searchParams;
    const requestedCurrentPage = parseInt(searchParams.get('page') || '1', 10);
    const requestedItemsPerPage = parseInt(searchParams.get('itemsPerPage') || '10', 10);
    const result = await getJson<{
      transactions?: any[];
      totalPages?: number;
      totalCount?: number;
      currentPage?: number;
      itemsPerPage?: number;
    }>(
      `/api/v2/${subdomain}/billing/transactions?page=${requestedCurrentPage}&itemsPerPage=${requestedItemsPerPage}`,
    );

    if (requestId !== latestRequestId) return;

    currentPage = requestedCurrentPage;
    itemsPerPage = requestedItemsPerPage;

    if (!result.ok) {
      transactions = [];
      totalPages = 0;
      totalCount = 0;
      return;
    }

    transactions = result.data.transactions ?? [];
    totalPages = result.data.totalPages ?? 0;
    totalCount = result.data.totalCount ?? 0;
    currentPage = result.data.currentPage ?? requestedCurrentPage;
    itemsPerPage = result.data.itemsPerPage ?? requestedItemsPerPage;
  }

  $: if (browser) {
    const nextFetchKey = `${$page.url.search}|${$page.params.subdomain}`;
    if (nextFetchKey !== lastFetchKey) {
      lastFetchKey = nextFetchKey;
      fetchTransactions();
    }
  }
</script>

<h3 class="text-3xl font-bold dark:text-white mb-4 mt-4">Transactions</h3>

<div class="mt-4 relative overflow-x-auto shadow-md sm:rounded-lg">
  <table class="w-full text-sm text-left rtl:text-right text-gray-500 dark:text-gray-400">
    <thead class="text-xs text-gray-700 uppercase bg-gray-50 dark:bg-gray-700 dark:text-gray-400">
      <tr>
        <th scope="col" class="px-6 py-3">Date time</th>
        <th scope="col" class="px-6 py-3">Transaction Id</th>
        <th scope="col" class="px-6 py-3">Payment method</th>
        <th scope="col" class="px-6 py-3">Email</th>
        <th scope="col" class="px-6 py-3">Amount</th>
      </tr>
    </thead>
    <tbody>
      {#each transactions as transaction}
        <!-- Parent Row -->
        <tr class="bg-white border-b dark:bg-gray-900 dark:border-gray-700">
          <td class="px-6 py-4">
            {moment(transaction.date).format('YYYY/MM/DD hh:mm a')}
          </td>
          <td class="px-6 py-4">{transaction.orderId}</td>
          <td class="px-6 py-4">{transaction.paymentGateway}</td>
          <td class="px-6 py-4">
            {transaction.customerEmail}
          </td>
          <td class="px-6 py-4">
            $ {transaction.amount.toFixed(2)}
          </td>
        </tr>
      {/each}
    </tbody>
  </table>
</div>

<Pagination
  baseUrl={`/app/${subdomain}/settings/billing/transactions`}
  {totalPages}
  {currentPage}
  {itemsPerPage}
  {totalCount}
/>
