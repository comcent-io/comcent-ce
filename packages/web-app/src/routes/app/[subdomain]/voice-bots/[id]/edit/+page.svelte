<script lang="ts">
  import { untrack } from 'svelte';
  import { page } from '$app/state';
  import { getJson } from '$lib/http';
  import PageHeader from '$lib/components/form/PageHeader.svelte';
  import SkeletonLoadingList from '$lib/components/SkeletonLoadingList.svelte';
  import VoiceBotForm from '../../VoiceBotForm.svelte';
  import type { voiceBotData } from '../../schema';

  let formData: voiceBotData = $state({
    id: '',
    name: '',
    instructions: '',
    notToDoInstructions: '',
    greetingInstructions: '',
    mcpServers: [],
    isHangup: false,
    isEnqueue: false,
    queues: [],
    pipeline: 'DEEPGRAM_AND_OPENAI',
  });
  let lastFetchKey = '';
  // The form is rendered only once the bot has loaded; see the note in
  // sip-trunks/[id]/edit for why an empty form must not be shown first.
  let isLoading = $state(true);

  async function fetchVoiceBot() {
    isLoading = true;
    const result = await getJson<any>(
      `/api/v2/${page.params.subdomain}/voice-bots/${page.params.id}`,
    );
    formData = result.ok ? result.data : {};
    isLoading = false;
  }

  // Refetch when the URL or the org changes. The fetch itself is untracked,
  // so the state it reads and writes does not re-run this.
  $effect(() => {
    const nextFetchKey = `${page.params.subdomain}|${page.params.id}`;
    if (nextFetchKey !== lastFetchKey) {
      lastFetchKey = nextFetchKey;
      untrack(() => fetchVoiceBot());
    }
  });
</script>

<PageHeader
  title="Edit voice bot"
  description="Changes apply to the next call the bot answers."
  backHref={`/app/${page.params.subdomain}/voice-bots`}
  backLabel="Voice bots"
/>

<div class="max-w-3xl">
  {#if isLoading}
    <SkeletonLoadingList />
  {:else}
    <VoiceBotForm {formData} isUpdate={true} />
  {/if}
</div>
