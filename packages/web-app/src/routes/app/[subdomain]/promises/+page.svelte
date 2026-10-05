<script lang="ts">
  import { SvelteSet } from 'svelte/reactivity';
  import { page } from '$app/state';
  import { routeParam } from '$lib/routeParam';
  import { onMount, untrack } from 'svelte';
  import toast from '$lib/toast';
  import Button from '$lib/components/Button.svelte';
  import Card from '$lib/components/Card.svelte';
  import Checkbox from '$lib/components/form/Checkbox.svelte';
  import EmptyState from '$lib/components/form/EmptyState.svelte';
  import Label from '$lib/components/form/Label.svelte';
  import PageHeader from '$lib/components/form/PageHeader.svelte';
  import Select from '$lib/components/form/Select.svelte';
  import PromiseTable from '$lib/components/promises/PromiseTable.svelte';
  import CallDetailsModal from '$lib/components/promises/CallDetailsModal.svelte';

  const statusFilters = [
    { status: 'OPEN', label: 'Open' },
    { status: 'CLOSED', label: 'Closed' },
  ];

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
  let promises: Promise[] = $state([]);
  let orgMembers: OrgMember[] = $state([]);
  let loading = $state(true);
  let selectedStatuses: string[] = $state(['OPEN']);
  let assignedToFilter: string = $state('assignedToMe');
  let selectedPromises = $state(new SvelteSet<string>());
  let closingInProgress = $state(false);
  let stats = $state({
    completionRatio: 0,
    totalCreatedToday: 0,
    closedToday: 0,
  });

  // Modal state
  let showCallDetailsModal = $state(false);
  let currentCallStoryId: string = $state('');

  // Constants
  const subdomain = routeParam('subdomain');
  const currentUsername = page.data.member.username;
  const userRole = page.data.member.role;

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
      selectedPromises = new SvelteSet();

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
  }

  function selectAllPromises() {
    const allOpenSelected =
      openPromises.length > 0 && openPromises.every((p) => selectedPromises.has(p.id));

    if (allOpenSelected) {
      openPromises.forEach((p) => selectedPromises.delete(p.id));
    } else {
      openPromises.forEach((p) => selectedPromises.add(p.id));
    }
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
  // Reactive statements
  let openPromises = $derived(promises.filter((p) => p.status === 'OPEN'));
  let openPromisesCount = $derived(openPromises.length);
  // Refetch when a filter changes.
  $effect(() => {
    if (selectedStatuses || assignedToFilter) {
      untrack(() => fetchPromises());
    }
  });
</script>

<PageHeader
  title="Promises"
  description="What your team promised callers they would do, and by when. Close a promise once it is done."
>
  {#snippet actions()}
    {#if selectedPromises.size > 0}
      <Button onclick={closeSelectedPromises} progress={closingInProgress}>
        Close {selectedPromises.size} selected
      </Button>
    {/if}
  {/snippet}
</PageHeader>

{#snippet stat(label: string, value: string, note: string)}
  <Card>
    <p class="text-sm font-medium text-gray-500 dark:text-gray-400">{label}</p>
    <p class="mt-3 text-3xl font-bold text-gray-900 dark:text-white">{value}</p>
    <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">{note}</p>
  </Card>
{/snippet}

<div class="space-y-6">
  <div class="grid max-w-3xl grid-cols-1 gap-4 sm:grid-cols-2">
    {@render stat(
      'Open',
      String(openPromisesCount),
      openPromisesCount === 1 ? 'promise to keep' : 'promises to keep',
    )}
    {@render stat(
      "Today's completion",
      `${(stats.completionRatio * 100).toFixed(1)}%`,
      `${stats.closedToday} of ${stats.totalCreatedToday} closed today`,
    )}
  </div>

  <div>
    <div class="mb-4 flex flex-wrap items-center gap-x-6 gap-y-3">
      {#if userRole === 'ADMIN'}
        <div class="flex items-center gap-2">
          <Label for="promises-assigned-to" class="!mb-0">Assigned to</Label>
          <Select
            id="promises-assigned-to"
            class="!w-auto"
            value={assignedToFilter}
            onchange={(e) => setAssignedToFilter(e.currentTarget.value)}
          >
            <option value="assignedToMe">Me</option>
            <option value="all">Anyone</option>
          </Select>
        </div>
      {/if}
      <div class="flex items-center gap-4" role="group" aria-labelledby="promises-status-label">
        <span id="promises-status-label"><Label tag="span" class="!mb-0">Status</Label></span>
        {#each statusFilters as filter (filter.status)}
          <label class="flex cursor-pointer items-center gap-2 text-sm">
            <Checkbox
              checked={selectedStatuses.includes(filter.status)}
              onchange={() => toggleStatusFilter(filter.status)}
            />
            <span class="text-gray-900 dark:text-white">{filter.label}</span>
          </label>
        {/each}
      </div>
      {#if !loading && openPromisesCount > 0}
        <span class="text-sm text-gray-500 dark:text-gray-400 sm:ms-auto">
          {selectedPromises.size} of {openPromisesCount} selected
        </span>
      {/if}
    </div>

    <PromiseTable
      {promises}
      {orgMembers}
      {selectedPromises}
      {loading}
      onToggleSelection={togglePromiseSelection}
      onSelectAll={selectAllPromises}
      onUpdateAssignment={updatePromiseAssignment}
      onViewDetails={openCallDetailsModal}
    >
      {#snippet empty()}
        <EmptyState
          title={selectedStatuses.length === 0 ? 'Choose a status' : 'No promises'}
          description={selectedStatuses.length === 0
            ? 'Tick Open, Closed or both to see promises.'
            : 'Promises made on your calls show here.'}
        />
      {/snippet}
    </PromiseTable>
  </div>
</div>

<!-- Call Details Modal -->
<CallDetailsModal
  bind:showModal={showCallDetailsModal}
  callStoryId={currentCallStoryId}
  {subdomain}
/>
