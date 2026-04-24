<script lang="ts">
  import { browser } from '$app/environment';
  import { page } from '$app/stores';
  import { getJson } from '$lib/http';
  import ErrorMessage from '$lib/components/ErrorMessage.svelte';
  import NumberForm from '../NumberForm.svelte';

  type PageError = { message: string; formErrors: { message: string; path: string[] }[] };
  let error: PageError | null = null;
  let sipTrunks: any[] = [];
  let lastFetchKey = '';

  async function fetchSipTrunks() {
    const result = await getJson<{ sipTrunks?: any[] }>(
      `/api/v2/${$page.params.subdomain}/sip-trunks`,
    );
    if (!result.ok) {
      error = { message: result.error, formErrors: [] };
      sipTrunks = [];
      return;
    }

    sipTrunks = result.data.sipTrunks ?? [];
    error = null;
  }

  $: if (browser) {
    const nextFetchKey = $page.params.subdomain;
    if (nextFetchKey !== lastFetchKey) {
      lastFetchKey = nextFetchKey;
      fetchSipTrunks();
    }
  }
</script>

<h3 class="text-3xl font-bold dark:text-white">Create Number</h3>

<div class="mt-6 max-w-6xl">
  {#if error}
    <ErrorMessage {error} />
  {/if}
  <NumberForm {sipTrunks} />
</div>
