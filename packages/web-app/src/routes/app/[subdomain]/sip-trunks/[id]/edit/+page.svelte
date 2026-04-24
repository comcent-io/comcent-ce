<script lang="ts">
  import { browser } from '$app/environment';
  import { page } from '$app/stores';
  import { getJson } from '$lib/http';
  import SipTrunkForm from '../../SipTrunkForm.svelte';
  import ErrorMessage from '$lib/components/ErrorMessage.svelte';

  let sipTrunk: any = {};
  type PageError = { message: string; formErrors: { message: string; path: string[] }[] };
  let error: PageError | null = null;
  let lastFetchKey = '';

  let showCredentialFields = false;
  async function fetchSipTrunk() {
    const result = await getJson<{ sipTrunks?: any[] }>(
      `/api/v2/${$page.params.subdomain}/sip-trunks`,
    );
    if (!result.ok) {
      error = { message: result.error, formErrors: [] };
      sipTrunk = null;
      return;
    }

    sipTrunk = (result.data.sipTrunks ?? []).find((st: any) => st.id === $page.params.id) ?? null;
    showCredentialFields = sipTrunk?.outboundUsername != null || sipTrunk?.outboundPassword != null;
    error = null;
  }

  $: if (browser) {
    const nextFetchKey = `${$page.params.subdomain}|${$page.params.id}`;
    if (nextFetchKey !== lastFetchKey) {
      lastFetchKey = nextFetchKey;
      fetchSipTrunk();
    }
  }
</script>

<h3 class="text-3xl font-bold dark:text-white">Sip Trunks Edit</h3>

<div class="w-1/2">
  {#if error}
    <ErrorMessage {error} />
  {/if}
  <SipTrunkForm formData={sipTrunk ?? {}} isUpdate={true} {showCredentialFields} bind:error />
</div>
