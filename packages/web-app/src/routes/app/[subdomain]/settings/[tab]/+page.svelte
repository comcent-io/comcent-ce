<script lang="ts">
  import { page } from '$app/stores';
  import WebhookSettings from './WebhookSettings.svelte';
  import ApiKeysSettings from './ApiKeysSettings.svelte';
  import AiSettings from './AiSettings.svelte';

  const tabs = [
    { name: 'Webhooks', tab: 'webhooks', current: true },
    { name: 'API Keys', tab: 'api-keys', current: false },
    { name: 'AI & Analysis', tab: 'ai-analysis', current: false },
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

{#if currentTab === 'webhooks'}
  <WebhookSettings />
{:else if currentTab === 'api-keys'}
  <ApiKeysSettings />
{:else if currentTab === 'ai-analysis'}
  <AiSettings />
{/if}
