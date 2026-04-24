<script lang="ts">
  import { browser } from '$app/environment';
  import { page } from '$app/stores';
  import { getJson } from '$lib/http';
  import NumberForm from '../../NumberForm.svelte';

  const defaultInboundFlow = JSON.stringify({
    start: '',
    nodes: {},
    outlets: {},
  });

  let sipTrunks: any[] = [];
  let isLoading = true;
  let number: any = {
    id: '',
    number: '',
    name: '',
    sipTrunkId: '',
    allowOutboundRegex: '',
    inboundFlowGraph: defaultInboundFlow,
  };
  let lastFetchKey = '';

  async function fetchData() {
    isLoading = true;
    const [sipTrunksResult, numbersResult] = await Promise.all([
      getJson<{ sipTrunks?: any[] }>(`/api/v2/${$page.params.subdomain}/sip-trunks`),
      getJson<{ numbers?: any[] }>(`/api/v2/${$page.params.subdomain}/numbers`),
    ]);

    sipTrunks = sipTrunksResult.ok ? (sipTrunksResult.data.sipTrunks ?? []) : [];
    const allNumbers = numbersResult.ok ? (numbersResult.data.numbers ?? []) : [];
    number = allNumbers.find((n: any) => n.id === $page.params.id) ?? {
      id: '',
      number: '',
      name: '',
      sipTrunkId: '',
      allowOutboundRegex: '',
      inboundFlowGraph: defaultInboundFlow,
    };
    isLoading = false;
  }

  $: if (browser) {
    const nextFetchKey = `${$page.params.subdomain}|${$page.params.id}`;
    if (nextFetchKey !== lastFetchKey) {
      lastFetchKey = nextFetchKey;
      fetchData();
    }
  }
</script>

<h3 class="text-3xl font-bold dark:text-white">Numbers Edit</h3>

<div class="mt-6 max-w-6xl">
  {#if !isLoading}
    <NumberForm formData={number} {sipTrunks} isUpdate={true} />
  {/if}
</div>
