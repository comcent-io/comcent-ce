<script lang="ts">
  import type { Snippet } from 'svelte';
  import { formatTableDate, formatTableDateTime } from '$lib/format';
  import Pill from '$lib/components/Pill.svelte';
  import Table from '$lib/components/Table.svelte';
  import Checkbox from '$lib/components/form/Checkbox.svelte';
  import SecondaryButton from '$lib/components/form/SecondaryButton.svelte';
  import Select from '$lib/components/form/Select.svelte';

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

  interface Props {
    promises?: Promise[];
    orgMembers?: OrgMember[];
    selectedPromises?: Set<string>;
    loading?: boolean;
    onToggleSelection: (promiseId: string) => void;
    onSelectAll: () => void;
    onUpdateAssignment: (promiseId: string, newAssignedTo: string) => void;
    onViewDetails: (callStoryId: string) => void;
    /** Shown instead of the rows when there are no promises (an EmptyState). */
    empty?: Snippet;
  }

  let {
    promises = [],
    orgMembers = [],
    selectedPromises = new Set(),
    loading = false,
    onToggleSelection,
    onSelectAll,
    onUpdateAssignment,
    onViewDetails,
    empty,
  }: Props = $props();

  let openPromises = $derived(promises.filter((p) => p.status === 'OPEN'));
  let allOpenSelected = $derived(
    openPromises.length > 0 && openPromises.every((p) => selectedPromises.has(p.id)),
  );
</script>

<!-- The header checkbox needs a cell of its own, so it sits just above. -->
{#if !loading && openPromises.length > 0}
  <label class="mb-2 inline-flex cursor-pointer items-center gap-2 text-sm">
    <Checkbox checked={allOpenSelected} onchange={onSelectAll} />
    <span class="text-gray-700 dark:text-gray-300">Select all open promises</span>
  </label>
{/if}

<Table
  columns={[
    { label: 'Select', srOnly: true },
    'Created',
    'Promise',
    'Created by',
    'Assigned to',
    'Due',
    'Status',
    { label: 'Call', srOnly: true },
  ]}
  {loading}
  isEmpty={promises.length === 0}
  {empty}
>
  {#each promises as promise (promise.id)}
    <tr>
      <td>
        <Checkbox
          aria-label="Select this promise"
          checked={selectedPromises.has(promise.id)}
          disabled={promise.status === 'CLOSED'}
          class="disabled:cursor-not-allowed disabled:opacity-50"
          onchange={() => onToggleSelection(promise.id)}
        />
      </td>
      <td class="whitespace-nowrap">{formatTableDate(promise.createdAt)}</td>
      <td class="font-medium text-gray-900 dark:text-white">{promise.promise}</td>
      <td>{promise.createdBy || 'Unknown'}</td>
      <td>
        <Select
          aria-label="Assigned to"
          class="min-w-36"
          value={promise.assignedTo}
          disabled={promise.status === 'CLOSED'}
          onchange={(e) => onUpdateAssignment(promise.id, e.currentTarget.value)}
        >
          {#each orgMembers as member (member.username)}
            <option value={member.username}>{member.username}</option>
          {/each}
        </Select>
      </td>
      <td class="whitespace-nowrap">{formatTableDateTime(promise.dueDate)}</td>
      <td>
        {#if promise.status === 'OPEN'}
          <Pill tone="amber" dot>Open</Pill>
        {:else}
          <Pill tone="green" dot>Closed</Pill>
        {/if}
      </td>
      <td class="text-right">
        <SecondaryButton
          size="sm"
          disabled={!promise.callStoryId}
          onclick={() => onViewDetails(promise.callStoryId)}
        >
          View call
        </SecondaryButton>
      </td>
    </tr>
  {/each}
</Table>
