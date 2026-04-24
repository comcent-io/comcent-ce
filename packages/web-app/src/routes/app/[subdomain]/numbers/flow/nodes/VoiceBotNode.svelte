<script lang="ts">
  import { page } from '$app/stores';
  import { onMount } from 'svelte';
  import type { SelectedOutlet } from '../SelectedOutlet';
  import type { VoiceBotNode } from './VoiceBotNode';
  import Draggable from '../utils/Draggable.svelte';
  import Inlet from '../utils/Inlet.svelte';
  import CloseButton from '../utils/CloseButton.svelte';
  import { createEventDispatcher } from 'svelte';
  import EditIcon from '$lib/components/Icons/EditIcon.svelte';
  import RefreshIcon from '$lib/components/Icons/RefreshIcon.svelte';

  const dispatch = createEventDispatcher();
  export let node: VoiceBotNode;
  export let selectedOutlet: SelectedOutlet | null;
  export let inletConnected = false;
  export let inletConnectable = false;

  interface VoiceBotType {
    id: string;
    name: string;
  }

  let selectedVoiceBotId = node.data.data.voiceBotId ?? '';

  export let voiceBots: VoiceBotType[] = [];
  let isRefreshing = false;

  async function fetchVoiceBots() {
    const response = await fetch(`/api/v2/${$page.params.subdomain}/voice-bots`);
    const data = await response.json();
    voiceBots = data.voiceBots ?? [];
    if (!selectedVoiceBotId && node.data.data.voiceBotId) {
      selectedVoiceBotId = node.data.data.voiceBotId;
    }
  }

  async function refreshVoiceBots() {
    isRefreshing = true;
    try {
      await fetchVoiceBots();
    } finally {
      isRefreshing = false;
    }
  }

  onMount(() => {
    fetchVoiceBots();
  });

  function onVoiceBotChange() {
    const selectedVoiceBot = voiceBots.find((voiceBot) => voiceBot.id === selectedVoiceBotId);
    if (!selectedVoiceBot) {
      return;
    }
    node.data.data.voiceBotName = selectedVoiceBot.name;
    node.data.data.voiceBotId = selectedVoiceBot.id;
    dispatch('updated', { node });
  }

  $: selectedVoiceBot = voiceBots.find((voiceBot) => voiceBot.id === selectedVoiceBotId);
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
        for={`voice-bot-${node.data.id}`}
        class="block text-xs font-semibold uppercase tracking-wide text-slate-500 dark:text-slate-300"
      >
        Voice bot
      </label>
      <div class="flex items-center gap-2">
        <select
          id={`voice-bot-${node.data.id}`}
          class="block min-w-0 flex-1 rounded-md border border-slate-300 bg-white p-2 text-sm text-slate-900 focus:border-blue-500 focus:ring-blue-500 dark:border-slate-600 dark:bg-slate-800 dark:text-white"
          bind:value={selectedVoiceBotId}
          on:change={onVoiceBotChange}
        >
          <option value="" disabled>Select a voice bot</option>
          {#each voiceBots as voiceBot}
            <option value={voiceBot.id}>{voiceBot.name}</option>
          {/each}
        </select>
        <button
          type="button"
          on:click={refreshVoiceBots}
          disabled={isRefreshing}
          class="inline-flex h-9 w-9 shrink-0 items-center justify-center rounded-md border border-slate-300 text-blue-700 hover:bg-blue-700 hover:text-white disabled:cursor-not-allowed disabled:opacity-50 dark:border-slate-600 dark:text-blue-400 dark:hover:text-white"
          title="Refresh Voice Bots"
        >
          <RefreshIcon />
        </button>
        {#if selectedVoiceBot}
          <a
            href={`/app/${$page.params.subdomain}/voice-bots/${selectedVoiceBot.id}/edit`}
            class="inline-flex h-9 w-9 shrink-0 items-center justify-center rounded-md border border-slate-300 text-blue-700 hover:bg-blue-700 hover:text-white dark:border-slate-600 dark:text-blue-400 dark:hover:text-white"
            target="_blank"
            title="Edit Voice Bot"
          >
            <EditIcon />
          </a>
        {/if}
      </div>
      <a
        href={`/app/${$page.params.subdomain}/voice-bots/create`}
        class="inline-flex text-xs font-semibold text-blue-700 hover:underline dark:text-blue-400"
        target="_blank"
      >
        Create a new voice bot
      </a>
    </div>
  </Inlet>
</Draggable>
