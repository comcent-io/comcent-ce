<script lang="ts">
  import ErrorMessage from '$lib/components/ErrorMessage.svelte';
  import SipTrunkForm from '../SipTrunkForm.svelte';

  type PageError = { message: string; formErrors: { message: string; path: string[] }[] };
  let error: PageError | null = null;
</script>

<h3 class="text-3xl font-bold dark:text-white">Create Sip Trunks</h3>

<div class="w-1/2">
  {#if error}
    <ErrorMessage {error} />
  {/if}
  <SipTrunkForm bind:error />
</div>
