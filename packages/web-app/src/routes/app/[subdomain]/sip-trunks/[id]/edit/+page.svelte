<script lang="ts">
  import { untrack } from 'svelte';
  import { page } from '$app/state';
  import { getJson } from '$lib/http';
  import SipTrunkForm from '../../SipTrunkForm.svelte';
  import PageHeader from '$lib/components/form/PageHeader.svelte';
  import SkeletonLoadingList from '$lib/components/SkeletonLoadingList.svelte';

  let sipTrunk: any = $state({});
  type PageError = { message: string; formErrors: { message: string; path: string[] }[] };
  let error: PageError | null = $state(null);
  let lastFetchKey = '';
  // The form is rendered only once the trunk has loaded. Rendering it empty
  // and assigning the fetched trunk afterwards overwrites whatever was typed
  // in the meantime, so an edit made before the response arrived was silently
  // saved with the old value.
  let isLoading = $state(true);

  let showCredentialFields = $state(false);
  async function fetchSipTrunk() {
    isLoading = true;
    const result = await getJson<{ sipTrunks?: any[] }>(
      `/api/v2/${page.params.subdomain}/sip-trunks`,
    );
    if (!result.ok) {
      error = { message: result.error, formErrors: [] };
      sipTrunk = null;
      isLoading = false;
      return;
    }

    sipTrunk = (result.data.sipTrunks ?? []).find((st: any) => st.id === page.params.id) ?? null;
    showCredentialFields = sipTrunk?.outboundUsername != null || sipTrunk?.outboundPassword != null;
    error = null;
    isLoading = false;
  }

  // Refetch when the URL or the org changes. The fetch itself is untracked,
  // so the state it reads and writes does not re-run this.
  $effect(() => {
    const nextFetchKey = `${page.params.subdomain}|${page.params.id}`;
    if (nextFetchKey !== lastFetchKey) {
      lastFetchKey = nextFetchKey;
      untrack(() => fetchSipTrunk());
    }
  });
</script>

<PageHeader
  title="Edit SIP trunk"
  description="A SIP trunk connects Comcent to your phone carrier, for the numbers you bring and the calls your team makes through it."
  backHref={`/app/${page.params.subdomain}/sip-trunks`}
  backLabel="SIP trunks"
/>

<!-- The form shows any error itself, including one loading the trunk. -->
{#if isLoading}
  <SkeletonLoadingList />
{:else}
  <SipTrunkForm formData={sipTrunk ?? {}} isUpdate={true} {showCredentialFields} bind:error />
{/if}
