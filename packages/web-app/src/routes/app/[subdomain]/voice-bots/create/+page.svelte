<script>
  import { page } from '$app/state';
  import PageHeader from '$lib/components/form/PageHeader.svelte';
  import VoiceBotForm from '../VoiceBotForm.svelte';
</script>

<PageHeader
  title="Create voice bot"
  description="A voice bot answers calls on its own: it talks to callers, follows your instructions, and can hang up or hand the caller to a queue."
  backHref={`/app/${page.params.subdomain}/voice-bots`}
  backLabel="Voice bots"
/>

<div class="max-w-3xl">
  <VoiceBotForm isUpdate={false} />
</div>
