<script lang="ts">
  import { page } from '$app/stores';
  import { onMount } from 'svelte';
  import type { SelectedOutlet } from '../SelectedOutlet';
  import type { QueueNode } from './QueueNode';
  import Draggable from '../utils/Draggable.svelte';
  import Inlet from '../utils/Inlet.svelte';
  import CloseButton from '../utils/CloseButton.svelte';
  import { createEventDispatcher } from 'svelte';
  import toast from 'svelte-french-toast';

  const dispatch = createEventDispatcher();
  export let node: QueueNode;
  export let selectedOutlet: SelectedOutlet | null;
  export let inletConnected = false;
  export let inletConnectable = false;
  let selectedQueue = node.data.data.queue ?? '';
  let isLoadingQueues = false;

  function onQueueChange() {
    node.data.data.queue = selectedQueue;
    dispatch('updated', { node });
  }

  export let queues: any = [];
  async function fetchQueues() {
    isLoadingQueues = true;
    try {
      const response = await fetch(`/api/v2/${$page.params.subdomain}/queues`);
      if (!response.ok) throw new Error((await response.json()).error ?? response.statusText);
      const data = await response.json();
      queues = data.queues;
      if (!selectedQueue && node.data.data.queue) {
        selectedQueue = node.data.data.queue;
      }
    } catch (error) {
      toast.error('Error fetching queues');
    } finally {
      isLoadingQueues = false;
    }
  }

  onMount(() => {
    fetchQueues();
  });
</script>

<Draggable
  {node}
  title={node.data.type}
  class="block w-[17rem] rounded-lg border-2 border-amber-400 bg-white shadow dark:border-amber-400 dark:bg-gray-800"
  on:dragEnd
>
  <svelte:fragment slot="headerActions">
    <CloseButton on:close />
  </svelte:fragment>
  <Inlet
    {selectedOutlet}
    {node}
    connected={inletConnected}
    connectable={inletConnectable}
    on:inletSelected
    on:disconnectInlet
  >
    <div class="space-y-2 p-3">
      <label
        for={`queue-${node.data.id}`}
        class="block text-xs font-semibold uppercase tracking-wide text-slate-500 dark:text-slate-300"
      >
        Queue
      </label>
      <select
        id={`queue-${node.data.id}`}
        class="block w-full rounded-md border border-slate-300 bg-white p-2 text-sm text-slate-900 focus:border-blue-500 focus:ring-blue-500 dark:border-slate-600 dark:bg-slate-800 dark:text-white"
        bind:value={selectedQueue}
        disabled={isLoadingQueues}
        on:change={onQueueChange}
      >
        <option value="" disabled>{isLoadingQueues ? 'Loading queues…' : 'Select a queue'}</option>
        {#each queues as queue}
          <option value={queue.name}>{queue.name}</option>
        {/each}
      </select>
    </div>
  </Inlet>
</Draggable>
