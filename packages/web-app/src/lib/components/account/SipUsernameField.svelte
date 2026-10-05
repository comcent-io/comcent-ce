<script lang="ts">
  import { publicSipUserRootDomain } from '$lib/publicConfig';
  import AccountField from './AccountField.svelte';
  import AccountInput from './AccountInput.svelte';

  // The username someone gets in an org (creating it, or joining by
  // invitation), with the SIP address it makes shown under it.
  interface Props {
    value?: string;
    subdomain?: string;
    error?: string;
    oninput?: () => void;
  }

  let { value = $bindable(''), subdomain = '', error, oninput }: Props = $props();
</script>

<AccountField for="sipUsername" label="SIP username" {error}>
  <AccountInput
    type="text"
    id="sipUsername"
    name="sipUsername"
    placeholder="your.name"
    autocomplete="off"
    autocapitalize="off"
    spellcheck="false"
    bind:value
    {oninput}
    invalid={!!error}
    required
  />
  {#snippet hint()}
    You sign in to phones and the dialer as
    <span class="font-medium text-slate-700 dark:text-slate-200">
      {value.trim() || 'your.name'}@{subdomain || 'acme'}.{publicSipUserRootDomain}
    </span>
  {/snippet}
</AccountField>
