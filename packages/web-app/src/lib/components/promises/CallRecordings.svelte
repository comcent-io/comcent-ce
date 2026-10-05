<script lang="ts">
  import EmptyState from '$lib/components/form/EmptyState.svelte';
  import AudioPlayer from './AudioPlayer.svelte';

  interface AudioRecording {
    url: string;
    fileName: string;
    currentParty: string;
  }

  interface Props {
    recordings?: AudioRecording[];
  }

  let { recordings = [] }: Props = $props();
</script>

{#if recordings.length > 0}
  <div class="space-y-3">
    {#each recordings as recording (recording.url)}
      <AudioPlayer url={recording.url} currentParty={recording.currentParty} />
    {/each}
  </div>
{:else}
  <EmptyState title="No recording" description="This call was not recorded." />
{/if}
