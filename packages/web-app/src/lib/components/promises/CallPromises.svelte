<script lang="ts">
  import { formatTableDateTime } from '$lib/format';
  import Pill from '$lib/components/Pill.svelte';
  import EmptyState from '$lib/components/form/EmptyState.svelte';

  interface Promise {
    id: string;
    promise: string;
    status: string;
    dueDate: string;
    assignedTo: string;
  }

  interface Props {
    promises?: Promise[];
  }

  let { promises = [] }: Props = $props();
</script>

{#if promises.length > 0}
  <ul class="divide-y divide-gray-200 dark:divide-gray-700">
    {#each promises as promise (promise.id)}
      <li class="flex items-start justify-between gap-3 py-3 first:pt-0 last:pb-0">
        <div class="min-w-0">
          <p class="text-sm font-medium text-gray-900 dark:text-white">{promise.promise}</p>
          <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">
            Assigned to {promise.assignedTo || 'no one'}
            {#if promise.dueDate}
              · Due {formatTableDateTime(promise.dueDate)}
            {/if}
          </p>
        </div>
        {#if promise.status === 'OPEN'}
          <Pill tone="amber" dot>Open</Pill>
        {:else}
          <Pill tone="green" dot>Closed</Pill>
        {/if}
      </li>
    {/each}
  </ul>
{:else}
  <EmptyState title="No promises" description="No promises were made on this call." />
{/if}
