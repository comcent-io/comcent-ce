<script lang="ts">
  import { page } from '$app/stores';
  import { onMount } from 'svelte';
  import toast from 'svelte-french-toast';
  import Spinner from '$lib/components/Icons/Spinner.svelte';
  import PromiseStatsCard from '$lib/components/promises/PromiseStatsCard.svelte';
  import PromiseTable from '$lib/components/promises/PromiseTable.svelte';
  import CallDetailsModal from '$lib/components/promises/CallDetailsModal.svelte';

  export const data = undefined;

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

  // State variables
  let promises: Promise[] = [];
  let orgMembers: OrgMember[] = [];
  let loading = true;
  let selectedStatuses: string[] = ['OPEN'];
  let assignedToFilter: string = 'assignedToMe';
  let selectedPromises: Set<string> = new Set();
  let closingInProgress = false;
  let stats = {
    completionRatio: 0,
    totalCreatedToday: 0,
    closedToday: 0,
  };

  // Modal state
  let showCallDetailsModal = false;
  let currentCallStoryId: string = '';

  // Constants
  const subdomain = $page.params.subdomain;
  const currentUsername = $page.data.member.username;
  const userRole = $page.data.member.role;

  // Reactive statements
  $: openPromises = promises.filter((p) => p.status === 'OPEN');
  $: openPromisesCount = openPromises.length;

  // Watch for filter changes
  $: if (selectedStatuses || assignedToFilter) {
    fetchPromises();
  }

  // LocalStorage functions
  function loadFilterState() {
    if (typeof window === 'undefined') return;

    const saved = localStorage.getItem(`promises-filter-${subdomain}`);
    if (!saved) return;

    try {
      const parsed = JSON.parse(saved);
      if (parsed.statuses?.length > 0) {
        selectedStatuses = parsed.statuses;
      }
      if (userRole === 'ADMIN' && parsed.assignedTo) {
        assignedToFilter = parsed.assignedTo;
      }
    } catch (error) {
      console.warn('Failed to parse saved filter state:', error);
    }
  }

  function saveFilterState() {
    if (typeof window === 'undefined') return;

    localStorage.setItem(
      `promises-filter-${subdomain}`,
      JSON.stringify({
        statuses: selectedStatuses,
        assignedTo: assignedToFilter,
      }),
    );
  }

  // API functions
  async function fetchPromises() {
    loading = true;
    try {
      const statusesToFetch = selectedStatuses.length > 0 ? selectedStatuses : ['OPEN'];
      const params = new URLSearchParams();
      statusesToFetch.forEach((status) => params.append('status', status));

      if (userRole === 'MEMBER' || (userRole === 'ADMIN' && assignedToFilter === 'assignedToMe')) {
        params.append('assignedTo', currentUsername);
      }

      const response = await fetch(`/api/v2/${subdomain}/promises?${params.toString()}`);
      if (!response.ok) throw new Error((await response.json()).error ?? response.statusText);
      const data = await response.json();
      promises = data.promises || [];
      stats = data.stats || {
        completionRatio: 0,
        totalCreatedToday: 0,
        closedToday: 0,
      };
    } catch (error: any) {
      toast.error(`Failed to fetch promises: ${error.message || 'Unknown error'}`);
    } finally {
      loading = false;
    }
  }

  async function fetchOrgMembers() {
    try {
      const response = await fetch(`/api/v2/${subdomain}/members`);
      if (!response.ok) throw new Error((await response.json()).error ?? response.statusText);
      const data = await response.json();
      orgMembers = data.members || [];
    } catch (error: any) {
      toast.error(`Failed to fetch members: ${error.message || 'Unknown error'}`);
    }
  }

  async function updatePromiseAssignment(promiseId: string, newAssignedTo: string) {
    try {
      const response = await fetch(`/api/v2/${subdomain}/promises/${promiseId}/assign`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ assignedTo: newAssignedTo }),
      });
      if (!response.ok) throw new Error((await response.json()).error ?? response.statusText);
      const data = await response.json();

      promises = promises.map((p) =>
        p.id === promiseId ? { ...p, assignedTo: data.promise.assignedTo } : p,
      );

      toast.success('Promise assignment updated successfully');
    } catch (error: any) {
      toast.error(`Failed to update assignment: ${error.message || 'Unknown error'}`);
    }
  }

  async function closeSelectedPromises() {
    if (selectedPromises.size === 0) {
      toast.error('Please select at least one promise to close');
      return;
    }

    closingInProgress = true;
    try {
      const promiseIds = Array.from(selectedPromises);

      const response = await fetch(`/api/v2/${subdomain}/promises/close`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ promiseIds }),
      });
      if (!response.ok) throw new Error((await response.json()).error ?? response.statusText);

      promises = promises.filter((p) => !selectedPromises.has(p.id));
      selectedPromises = new Set();

      toast.success(`Successfully closed ${promiseIds.length} promise(s)`);
    } catch (error: any) {
      toast.error(`Failed to close promises: ${error.message || 'Unknown error'}`);
    } finally {
      closingInProgress = false;
    }
  }

  // Filter functions
  function toggleStatusFilter(status: string) {
    selectedStatuses = selectedStatuses.includes(status)
      ? selectedStatuses.filter((s) => s !== status)
      : [...selectedStatuses, status];
    saveFilterState();
  }

  function setAssignedToFilter(value: string) {
    assignedToFilter = value;
    saveFilterState();
  }

  // Selection functions
  function togglePromiseSelection(promiseId: string) {
    if (selectedPromises.has(promiseId)) {
      selectedPromises.delete(promiseId);
    } else {
      selectedPromises.add(promiseId);
    }
    selectedPromises = selectedPromises;
  }

  function selectAllPromises() {
    const allOpenSelected =
      openPromises.length > 0 && openPromises.every((p) => selectedPromises.has(p.id));

    if (allOpenSelected) {
      openPromises.forEach((p) => selectedPromises.delete(p.id));
    } else {
      openPromises.forEach((p) => selectedPromises.add(p.id));
    }
    selectedPromises = selectedPromises;
  }

  // Modal functions
  function openCallDetailsModal(callStoryId: string) {
    if (!callStoryId) {
      toast.error('No call story associated with this promise');
      return;
    }

    currentCallStoryId = callStoryId;
    showCallDetailsModal = true;
  }

  // Lifecycle
  onMount(() => {
    loadFilterState();
    fetchPromises();
    fetchOrgMembers();
  });
</script>

<div class="p-6">
  <!-- Header -->
  <h1 class="text-3xl font-bold text-gray-900 dark:text-white mb-8">Promises</h1>

  {#if loading}
    <div class="flex justify-center items-center h-64">
      <Spinner />
    </div>
  {:else}
    <!-- Summary Cards -->
    <div
      class="grid grid-cols-1 md:grid-cols-2 {userRole === 'ADMIN'
        ? 'lg:grid-cols-4'
        : 'lg:grid-cols-3'} gap-6 mb-8"
    >
      <!-- Open Promises Card -->
      <PromiseStatsCard icon="check" title="Open" value={openPromisesCount} color="blue" />

      <!-- Completion Ratio Card -->
      <PromiseStatsCard
        icon="chart"
        title="Today's Completion"
        value="{(stats.completionRatio * 100).toFixed(1)}%"
        subtitle="{stats.closedToday}/{stats.totalCreatedToday} closed"
        color="blue"
      />

      <!-- Assigned To Filter Card - Only visible for ADMIN -->
      {#if userRole === 'ADMIN'}
        <PromiseStatsCard icon="user" title="Assigned To" value="" color="green">
          <select
            class="mt-2 block w-full px-3 py-2 text-sm text-gray-900 bg-white border border-gray-300 rounded-lg focus:ring-blue-500 focus:border-blue-500 dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500"
            value={assignedToFilter}
            on:change={(e) => setAssignedToFilter(e.currentTarget.value)}
          >
            <option value="assignedToMe">Assigned to Me</option>
            <option value="all">All</option>
          </select>
        </PromiseStatsCard>
      {/if}

      <!-- Status Filter Card -->
      <PromiseStatsCard icon="status" title="Status" value="" color="purple">
        <div class="mt-2 space-y-2">
          <label class="flex items-center">
            <input
              type="checkbox"
              class="w-4 h-4 text-blue-600 bg-gray-100 border-gray-300 rounded focus:ring-blue-500 dark:focus:ring-blue-600 dark:ring-offset-gray-800 focus:ring-2 dark:bg-gray-700 dark:border-gray-600"
              checked={selectedStatuses.includes('OPEN')}
              on:change={() => toggleStatusFilter('OPEN')}
            />
            <span class="ml-2 text-sm text-gray-900 dark:text-white">Open</span>
          </label>
          <label class="flex items-center">
            <input
              type="checkbox"
              class="w-4 h-4 text-blue-600 bg-gray-100 border-gray-300 rounded focus:ring-blue-500 dark:focus:ring-blue-600 dark:ring-offset-gray-800 focus:ring-2 dark:bg-gray-700 dark:border-gray-600"
              checked={selectedStatuses.includes('CLOSED')}
              on:change={() => toggleStatusFilter('CLOSED')}
            />
            <span class="ml-2 text-sm text-gray-900 dark:text-white">Closed</span>
          </label>
        </div>
      </PromiseStatsCard>
    </div>

    <!-- Action Bar -->
    {#if promises.length > 0}
      <div class="mb-4 flex items-center justify-between">
        <div class="flex items-center space-x-4">
          <span class="text-sm text-gray-600 dark:text-gray-400">
            {selectedPromises.size} of {openPromisesCount} selected
          </span>
        </div>
        <div class="flex items-center space-x-2">
          {#if selectedPromises.size > 0}
            <button
              on:click={closeSelectedPromises}
              disabled={closingInProgress}
              class="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md text-white bg-red-600 hover:bg-red-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-red-500 disabled:opacity-50 disabled:cursor-not-allowed"
            >
              {#if closingInProgress}
                <Spinner />
                <span class="ml-2">Closing...</span>
              {:else}
                Close Selected
              {/if}
            </button>
          {/if}
        </div>
      </div>
    {/if}

    <!-- Promises Table -->
    <PromiseTable
      {promises}
      {orgMembers}
      {selectedPromises}
      onToggleSelection={togglePromiseSelection}
      onSelectAll={selectAllPromises}
      onUpdateAssignment={updatePromiseAssignment}
      onViewDetails={openCallDetailsModal}
    >
      <svelte:fragment slot="empty-message">
        {selectedStatuses.length === 0
          ? 'Please select at least one status to view promises.'
          : 'There are no promises to display for the selected status(es).'}
      </svelte:fragment>
    </PromiseTable>
  {/if}
</div>

<!-- Call Details Modal -->
<CallDetailsModal
  bind:showModal={showCallDetailsModal}
  callStoryId={currentCallStoryId}
  {subdomain}
/>
