<script lang="ts">
  import { page } from '$app/stores';
  import Balance from './Balance.svelte';
  import Transactions from './Transactions.svelte';
  import Usage from './Usage.svelte';

  const tabs = [
    { name: 'Balance', tab: 'balance' },
    { name: 'Usage', tab: 'usage' },
    { name: 'Transactions', tab: 'transactions' },
  ];

  $: currentTab = $page.params.tab;

  const inactiveTabClass =
    'inline-block p-4 border-b-2 border-transparent rounded-t-lg hover:text-gray-600 hover:border-gray-300 dark:hover:text-gray-300';
  const activeTabClass =
    'inline-block p-4 text-blue-600 border-b-2 border-blue-600 rounded-t-lg active dark:text-blue-500 dark:border-blue-500';
</script>

<div
  class="text-sm font-medium text-center text-gray-500 border-b border-gray-200 dark:text-gray-400 dark:border-gray-700"
>
  <ul class="flex flex-wrap -mb-px">
    {#each tabs as tab}
      <li class="me-2">
        <a href={tab.tab} class={currentTab === tab.tab ? activeTabClass : inactiveTabClass}>
          {tab.name}
        </a>
      </li>
    {/each}
  </ul>
</div>

{#if currentTab === 'balance'}
  <Balance />
{:else if currentTab === 'usage'}
  <Usage />
{:else if currentTab === 'transactions'}
  <Transactions />
{/if}
