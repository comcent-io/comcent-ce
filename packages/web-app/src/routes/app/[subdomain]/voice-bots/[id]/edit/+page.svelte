<script lang="ts">
  import { browser } from '$app/environment';
  import { page } from '$app/stores';
  import { getJson } from '$lib/http';
  import VoiceBotForm from '../../VoiceBotForm.svelte';
  import type { voiceBotData } from '../../schema';

  let formData: voiceBotData = {
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
  };
  let lastFetchKey = '';

  async function fetchVoiceBot() {
    const result = await getJson<any>(
      `/api/v2/${$page.params.subdomain}/voice-bots/${$page.params.id}`,
    );
    formData = result.ok ? result.data : {};
  }

  $: if (browser) {
    const nextFetchKey = `${$page.params.subdomain}|${$page.params.id}`;
    if (nextFetchKey !== lastFetchKey) {
      lastFetchKey = nextFetchKey;
      fetchVoiceBot();
    }
  }
</script>

<h3 class="text-3xl font-bold dark:text-white">Voice Bots Edit</h3>

<div class="max-w-sm">
  <VoiceBotForm {formData} isUpdate={true} />
</div>
