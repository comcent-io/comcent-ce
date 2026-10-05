<script lang="ts">
  import { untrack } from 'svelte';
  import { page } from '$app/state';
  import { getJson } from '$lib/http';
  import ErrorMessage from '$lib/components/ErrorMessage.svelte';
  import PageHeader from '$lib/components/form/PageHeader.svelte';
  import NumberForm from '../NumberForm.svelte';

  type PageError = { message: string; formErrors: { message: string; path: string[] }[] };
  let error: PageError | null = $state(null);
  let sipTrunks: any[] = $state([]);
  let lastFetchKey = '';

  async function fetchSipTrunks() {
    const result = await getJson<{ sipTrunks?: any[] }>(
      `/api/v2/${page.params.subdomain}/sip-trunks`,
    );
    if (!result.ok) {
      error = { message: result.error, formErrors: [] };
      sipTrunks = [];
      return;
    }

    sipTrunks = result.data.sipTrunks ?? [];
    error = null;
  }

  // Refetch when the URL or the org changes. The fetch itself is untracked,
  // so the state it reads and writes does not re-run this.
  $effect(() => {
    const nextFetchKey = page.params.subdomain ?? '';
    if (nextFetchKey !== lastFetchKey) {
      lastFetchKey = nextFetchKey;
      untrack(() => fetchSipTrunks());
    }
  });
</script>

<PageHeader
  title="Create number"
  description="Add a phone number from one of your SIP trunks, and choose where its incoming calls go."
  backHref={`/app/${page.params.subdomain}/numbers`}
  backLabel="Numbers"
/>

<div class="max-w-6xl space-y-6">
  {#if error}
    <ErrorMessage {error} />
  {/if}
  <NumberForm {sipTrunks} />
</div>
