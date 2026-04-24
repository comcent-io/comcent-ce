<script lang="ts">
  import moment from 'moment-timezone';

  interface Promise {
    id: string;
    promise: string;
    status: string;
    dueDate: string;
    assignedTo: string;
  }

  export let promises: Promise[] = [];

  function formatDateWithTime(dateString: string): string {
    return moment(dateString).format('YYYY/MM/DD hh:mm A');
  }
</script>

<div
  class="bg-slate-100 dark:bg-gray-800 rounded-lg shadow-sm border border-slate-400 dark:border-gray-700 p-4 mb-4"
>
  <div class="flex items-center space-x-2 mb-3">
    <div class="bg-amber-600 rounded-lg p-2 shadow-md">
      <svg class="w-4 h-4 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="2"
          d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"
        ></path>
      </svg>
    </div>
    <h3 class="text-sm font-bold text-gray-900 dark:text-white">Promises</h3>
    {#if promises.length > 0}
      <span class="text-xs text-slate-500 dark:text-slate-400">
        ({promises.length}
        {promises.length === 1 ? 'promise' : 'promises'})
      </span>
    {/if}
  </div>

  {#if promises.length > 0}
    <div class="space-y-2">
      {#each promises as promise}
        <div
          class="bg-slate-200 dark:bg-gray-700 rounded-lg p-4 border border-slate-400 dark:border-gray-600 shadow-sm"
        >
          <div class="flex items-start justify-between gap-3">
            <div class="flex-1 space-y-2">
              <p class="text-sm font-medium text-gray-900 dark:text-white">
                {promise.promise}
              </p>
              <div class="flex flex-wrap gap-3 text-xs text-slate-600 dark:text-slate-400">
                <div class="flex items-center space-x-1">
                  <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z"
                    ></path>
                  </svg>
                  <span>Assigned to: {promise.assignedTo || 'Unassigned'}</span>
                </div>
                {#if promise.dueDate}
                  <div class="flex items-center space-x-1">
                    <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"
                      ></path>
                    </svg>
                    <span>Due: {formatDateWithTime(promise.dueDate)}</span>
                  </div>
                {/if}
              </div>
            </div>
            <div>
              <span
                class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium {promise.status ===
                'OPEN'
                  ? 'bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200'
                  : 'bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200'}"
              >
                {promise.status === 'OPEN' ? 'Open' : 'Closed'}
              </span>
            </div>
          </div>
        </div>
      {/each}
    </div>
  {:else}
    <div class="p-6 text-center bg-slate-100 dark:bg-gray-800 rounded-lg">
      <div class="bg-slate-200 dark:bg-gray-700 rounded-full p-4 mb-3 shadow-inner inline-block">
        <svg
          class="w-8 h-8 text-slate-400 dark:text-slate-500"
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"
          ></path>
        </svg>
      </div>
      <p class="text-sm font-semibold text-gray-900 dark:text-white mb-1">No Promises Available</p>
      <p class="text-xs text-slate-500 dark:text-slate-400">
        No promises were created for this call
      </p>
    </div>
  {/if}
</div>
