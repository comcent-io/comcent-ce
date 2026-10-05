<script lang="ts">
  import { page } from '$app/state';
  import PageHeader from '$lib/components/form/PageHeader.svelte';
  import SipTrunkForm from '../SipTrunkForm.svelte';

  type PageError = { message: string; formErrors: { message: string; path: string[] }[] };
  let error: PageError | null = $state(null);
</script>

<PageHeader
  title="Add SIP trunk"
  description="A SIP trunk connects Comcent to your phone carrier, for the numbers you bring and the calls your team makes through it."
  backHref={`/app/${page.params.subdomain}/sip-trunks`}
  backLabel="SIP trunks"
/>

<!-- The form shows any error itself. -->
<SipTrunkForm bind:error />
