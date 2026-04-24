<script lang="ts">
  import moment from 'moment-timezone';

  interface Promise {
    id: string;
    promise: string;
    status: string;
    dueDate: string;
    createdAt: string;
    assignedTo: string;
    createdBy: string;
    callStoryId: string;
  }

  interface OrgMember {
    id: number;
    username: string;
    extensionNumber: string;
    presence: string;
    user: {
      id: number;
      name: string;
      email: string;
    };
  }

  export let promises: Promise[] = [];
  export let orgMembers: OrgMember[] = [];
  export let selectedPromises: Set<string> = new Set();
  export let onToggleSelection: (promiseId: string) => void;
  export let onSelectAll: () => void;
  export let onUpdateAssignment: (promiseId: string, newAssignedTo: string) => void;
  export let onViewDetails: (callStoryId: string) => void;

  function formatDate(dateString: string): string {
    return moment(dateString).format('YYYY/MM/DD');
  }

  function formatDateWithTime(dateString: string): string {
    return moment(dateString).format('YYYY/MM/DD hh:mm A');
  }

  $: openPromises = promises.filter((p) => p.status === 'OPEN');
  $: allOpenSelected =
    openPromises.length > 0 && openPromises.every((p) => selectedPromises.has(p.id));
</script>

<div
  class="bg-white dark:bg-gray-800 shadow-sm rounded-lg border border-gray-200 dark:border-gray-700"
>
  {#if promises.length > 0}
    <div class="overflow-x-auto">
      <table class="w-full text-sm text-left text-gray-500 dark:text-gray-400">
        <thead
          class="text-xs text-gray-700 uppercase bg-gray-50 dark:bg-gray-700 dark:text-gray-400"
        >
          <tr>
            <th scope="col" class="px-6 py-3 font-medium">
              <input
                type="checkbox"
                class="w-4 h-4 text-blue-600 bg-gray-100 border-gray-300 rounded focus:ring-blue-500 dark:focus:ring-blue-600 dark:ring-offset-gray-800 focus:ring-2 dark:bg-gray-700 dark:border-gray-600"
                checked={allOpenSelected}
                on:change={onSelectAll}
              />
            </th>
            <th scope="col" class="px-6 py-3 font-medium">CREATED DATE</th>
            <th scope="col" class="px-6 py-3 font-medium">PROMISE</th>
            <th scope="col" class="px-6 py-3 font-medium">CREATED BY</th>
            <th scope="col" class="px-6 py-3 font-medium">ASSIGNED TO</th>
            <th scope="col" class="px-6 py-3 font-medium">DUE DATE</th>
            <th scope="col" class="px-6 py-3 font-medium">STATUS</th>
            <th scope="col" class="px-6 py-3 font-medium">ACTIONS</th>
          </tr>
        </thead>
        <tbody>
          {#each promises as promise}
            <tr
              class="bg-white border-b dark:bg-gray-900 dark:border-gray-700 hover:bg-gray-50 dark:hover:bg-gray-800"
            >
              <td class="px-6 py-4">
                <input
                  type="checkbox"
                  class="w-4 h-4 text-blue-600 bg-gray-100 border-gray-300 rounded focus:ring-blue-500 dark:focus:ring-blue-600 dark:ring-offset-gray-800 focus:ring-2 dark:bg-gray-700 dark:border-gray-600 disabled:opacity-50 disabled:cursor-not-allowed"
                  checked={selectedPromises.has(promise.id)}
                  disabled={promise.status === 'CLOSED'}
                  on:change={() => onToggleSelection(promise.id)}
                />
              </td>
              <td class="px-6 py-4 font-medium text-gray-900 dark:text-white">
                {formatDate(promise.createdAt)}
              </td>
              <td class="px-6 py-4">
                <div class="font-medium text-gray-900 dark:text-white">
                  {promise.promise}
                </div>
              </td>
              <td class="px-6 py-4 text-gray-900 dark:text-white">
                {promise.createdBy || 'Unknown'}
              </td>
              <td class="px-6 py-4">
                <select
                  class="block w-full px-3 py-2 text-sm text-gray-900 bg-white border border-gray-300 rounded-lg focus:ring-blue-500 focus:border-blue-500 dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500"
                  value={promise.assignedTo}
                  disabled={promise.status === 'CLOSED'}
                  on:change={(e) => onUpdateAssignment(promise.id, e.currentTarget.value)}
                >
                  {#each orgMembers as member}
                    <option value={member.username}>
                      {member.username}
                    </option>
                  {/each}
                </select>
              </td>
              <td class="px-6 py-4 font-medium text-gray-900 dark:text-white">
                {promise.dueDate ? formatDateWithTime(promise.dueDate) : ''}
              </td>
              <td class="px-6 py-4">
                <span
                  class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium {promise.status ===
                  'OPEN'
                    ? 'bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200'
                    : 'bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200'}"
                >
                  {promise.status === 'OPEN' ? 'Open' : 'Closed'}
                </span>
              </td>
              <td class="px-6 py-4">
                <button
                  on:click={() => onViewDetails(promise.callStoryId)}
                  disabled={!promise.callStoryId}
                  class="font-medium text-blue-600 dark:text-blue-500 hover:underline disabled:text-gray-400 disabled:cursor-not-allowed disabled:no-underline"
                >
                  View Details
                </button>
              </td>
            </tr>
          {/each}
        </tbody>
      </table>
    </div>
  {:else}
    <div class="text-center py-12">
      <svg
        class="mx-auto h-12 w-12 text-gray-400"
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
      <h3 class="mt-2 text-sm font-medium text-gray-900 dark:text-white">No promises found</h3>
      <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
        <slot name="empty-message">There are no promises to display.</slot>
      </p>
    </div>
  {/if}
</div>
