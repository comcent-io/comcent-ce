<script lang="ts">
  import { page } from '$app/state';
  import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';
  import { goto } from '$app/navigation';
  import toast from '$lib/toast';
  import Spinner from '$lib/components/Icons/Spinner.svelte';
  import Button from '$lib/components/Button.svelte';
  import Table from '$lib/components/Table.svelte';
  import EmptyState from '$lib/components/form/EmptyState.svelte';
  import PageHeader from '$lib/components/form/PageHeader.svelte';
  import SecondaryButton from '$lib/components/form/SecondaryButton.svelte';
  import { onMount } from 'svelte';

  let { data } = $props();

  let isDeletePopUp = $state(false);
  let isDeleteInProgress = $state(false);
  let queues: any[] = $state([]);
  let loading = $state(true);
  const subdomain = page.params.subdomain;

  interface QueueToBeDeletedType {
    id: string;
    name: string;
  }

  let queueToBeDeleted: QueueToBeDeletedType | null = $state(null);

  function toggleDeletePopUp() {
    isDeletePopUp = !isDeletePopUp;
  }

  onMount(async () => {
    try {
      const response = await fetch(`/api/v2/${subdomain}/queues`);
      if (!response.ok) throw new Error((await response.json()).error ?? response.statusText);
      const data = await response.json();
      queues = data.queues;
    } catch (error: any) {
      toast.error(`${error.message}`);
    } finally {
      loading = false;
    }
  });

  async function handleDelete() {
    isDeletePopUp = false;
    isDeleteInProgress = true;
    const deletedQueue = queueToBeDeleted;
    try {
      const response = await fetch(`/api/v2/${subdomain}/queues/${deletedQueue?.id}`, {
        method: 'DELETE',
      });
      if (!response.ok) throw new Error((await response.json()).error ?? response.statusText);
      queues = queues.filter((queue) => queue.id !== deletedQueue?.id);
      queueToBeDeleted = null;
      toast.success(`${deletedQueue?.name} queue deleted successfully`);
    } catch (error: any) {
      toast.error(`${error.message}`);
    } finally {
      isDeleteInProgress = false;
    }
  }
</script>

<PageHeader
  title="Queues"
  description="Groups of agents who share incoming calls, such as Sales or Support. A call sent to a queue rings the next free agent in it."
>
  {#snippet actions()}
    <Button href={`${data.basePath}/queues/create`}>Add</Button>
  {/snippet}
</PageHeader>

{#if isDeletePopUp}
  <ConfirmDialog
    message={`Are you sure you want to delete the ${queueToBeDeleted?.name}?`}
    onCancel={toggleDeletePopUp}
    onConfirm={handleDelete}
  />
{/if}

<Table
  columns={[
    'Name',
    'Extension',
    'Wrap-up time',
    'Reject delay',
    'Missed calls before logout',
    { label: 'Actions', srOnly: true },
  ]}
  {loading}
  isEmpty={queues.length === 0}
>
  {#snippet empty()}
    <EmptyState
      title="No queues yet"
      description="A queue shares incoming calls among a group of agents. Click Add above to create your first one, then add agents to it."
    />
  {/snippet}
  {#each queues as queue (queue.id)}
    <tr>
      <th scope="row" class="whitespace-nowrap font-medium text-gray-900 dark:text-white">
        {queue.name}
      </th>
      <td class="tabular-nums">{queue.extension ?? '—'}</td>
      <td class="tabular-nums">{queue.wrapUpTime}s</td>
      <td class="tabular-nums">{queue.rejectDelayTime}s</td>
      <td class="tabular-nums">{queue.maxNoAnswers}</td>
      <td>
        <div class="flex items-center justify-end gap-4">
          <SecondaryButton size="sm" href={`${data.basePath}/queues/${queue.id}/dashboard`}>
            Dashboard
          </SecondaryButton>
          <SecondaryButton size="sm" href={`${data.basePath}/queues/${queue.id}/edit`}>
            Edit
          </SecondaryButton>
          {#if isDeleteInProgress && queue.id === queueToBeDeleted?.id}
            <Spinner />
          {:else}
            <SecondaryButton
              size="sm"
              tone="danger"
              onclick={() => {
                queueToBeDeleted = queue;
                toggleDeletePopUp();
              }}
            >
              Delete
            </SecondaryButton>
          {/if}
        </div>
      </td>
    </tr>
  {/each}
</Table>
