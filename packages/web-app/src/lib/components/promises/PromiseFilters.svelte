<script lang="ts">
  import PromiseStatsCard from './PromiseStatsCard.svelte';

  export let selectedStatuses: string[] = [];
  export let assignedToFilter: string = 'assignedToMe';
  export let userRole: string;
  export let onStatusChange: (status: string) => void;
  export let onAssignedToChange: (value: string) => void;
</script>

<div class="grid grid-cols-1 md:grid-cols-2 gap-6">
  <!-- Assigned To Filter - Only visible for ADMIN -->
  {#if userRole === 'ADMIN'}
    <PromiseStatsCard icon="user" title="Assigned To" value="" color="green">
      <select
        class="mt-2 block w-full px-3 py-2 text-sm text-gray-900 bg-white border border-gray-300 rounded-lg focus:ring-blue-500 focus:border-blue-500 dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500"
        value={assignedToFilter}
        on:change={(e) => onAssignedToChange(e.currentTarget.value)}
      >
        <option value="assignedToMe">Assigned to Me</option>
        <option value="all">All</option>
      </select>
    </PromiseStatsCard>
  {/if}

  <!-- Status Filter -->
  <PromiseStatsCard icon="status" title="Status" value="" color="purple">
    <div class="mt-2 space-y-2">
      <label class="flex items-center">
        <input
          type="checkbox"
          class="w-4 h-4 text-blue-600 bg-gray-100 border-gray-300 rounded focus:ring-blue-500 dark:focus:ring-blue-600 dark:ring-offset-gray-800 focus:ring-2 dark:bg-gray-700 dark:border-gray-600"
          checked={selectedStatuses.includes('OPEN')}
          on:change={() => onStatusChange('OPEN')}
        />
        <span class="ml-2 text-sm text-gray-900 dark:text-white">Open</span>
      </label>
      <label class="flex items-center">
        <input
          type="checkbox"
          class="w-4 h-4 text-blue-600 bg-gray-100 border-gray-300 rounded focus:ring-blue-500 dark:focus:ring-blue-600 dark:ring-offset-gray-800 focus:ring-2 dark:bg-gray-700 dark:border-gray-600"
          checked={selectedStatuses.includes('CLOSED')}
          on:change={() => onStatusChange('CLOSED')}
        />
        <span class="ml-2 text-sm text-gray-900 dark:text-white">Closed</span>
      </label>
    </div>
  </PromiseStatsCard>
</div>
