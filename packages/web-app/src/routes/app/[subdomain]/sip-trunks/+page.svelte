<script lang="ts">
  import { onMount } from 'svelte';
  import { page } from '$app/state';
  import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';
  import ErrorMessage from '$lib/components/ErrorMessage.svelte';
  import Button from '$lib/components/Button.svelte';
  import Pill from '$lib/components/Pill.svelte';
  import Table from '$lib/components/Table.svelte';
  import EmptyState from '$lib/components/form/EmptyState.svelte';
  import PageHeader from '$lib/components/form/PageHeader.svelte';
  import SecondaryButton from '$lib/components/form/SecondaryButton.svelte';
  import { deleteJson, getJson } from '$lib/http';
  import { goto } from '$app/navigation';
  import toast from '$lib/toast';

  let { data } = $props();

  interface sipTrunkToBeDeletedType {
    id: string;
    name: string;
  }

  interface SipTrunk {
    id: string;
    name: string;
    // Set when a provider connection (e.g. Twilio) created this trunk. Such a
    // trunk mirrors a real one in the customer's provider account, so it is
    // removed by disconnecting the connection, not from here. Note the casing:
    // the API camelCases keys on the way out.
    providerConnectionId?: string | null;
  }

  let sipTrunkToBeDeleted: sipTrunkToBeDeletedType | null = $state(null);

  let isDeletePopUp = $state(false);
  let errorMessage = $state('');
  const subdomain = page.params.subdomain;
  let sipTrunks: SipTrunk[] = $state([]);
  let loading = $state(false);

  async function loadSipTrunks() {
    loading = true;
    const result = await getJson<{ sipTrunks?: SipTrunk[] }>(`/api/v2/${subdomain}/sip-trunks`);
    if (result.ok) {
      sipTrunks = result.data.sipTrunks ?? [];
    } else {
      errorMessage = result.error;
    }
    loading = false;
  }

  onMount(() => {
    void loadSipTrunks();
  });

  function toggleDeletePopUp() {
    isDeletePopUp = !isDeletePopUp;
  }

  async function handleSubmit() {
    errorMessage = '';
    isDeletePopUp = false;
    const result = await deleteJson(`/api/v2/${subdomain}/sip-trunks/${sipTrunkToBeDeleted?.id}`);
    if (!result.ok) {
      errorMessage = result.error;
      return;
    }

    sipTrunks = sipTrunks.filter((trunk) => trunk.id !== sipTrunkToBeDeleted!.id);
    goto(`/app/${subdomain}/sip-trunks`, { invalidateAll: true });
    toast.success(`${sipTrunkToBeDeleted?.name} trunk deleted successfully`);
  }
</script>

<PageHeader
  title="SIP Trunks"
  description="The connections to your phone carriers that carry your calls in and out. Add one for each carrier account you use."
>
  {#snippet actions()}
    <Button href={`${data.basePath}/sip-trunks/create`}>Create</Button>
  {/snippet}
</PageHeader>

{#if errorMessage}
  <ErrorMessage error={{ message: errorMessage, formErrors: [] }} />
{/if}

{#if isDeletePopUp}
  <ConfirmDialog
    message={`Are you sure you want to delete the ${sipTrunkToBeDeleted?.name}?`}
    onCancel={toggleDeletePopUp}
    onConfirm={handleSubmit}
  />
{/if}

<Table
  columns={['Name', { label: 'Actions', srOnly: true }]}
  {loading}
  isEmpty={sipTrunks.length === 0}
>
  {#snippet empty()}
    <EmptyState
      title="No SIP trunks yet"
      description="A SIP trunk links Comcent to your phone carrier. Click Create above to add your first one, or connect a Twilio account from Numbers."
    />
  {/snippet}
  {#each sipTrunks as trunk (trunk.id)}
    <tr>
      <td class="font-medium text-gray-900 dark:text-white">
        <div class="flex flex-wrap items-center gap-2">
          {trunk.name}
          {#if trunk.providerConnectionId}
            <!-- A trunk mirrored from a Twilio account is removed by
                 disconnecting that account, so it has no Delete here. -->
            <a
              href={`${data.basePath}/numbers/connections/${trunk.providerConnectionId}`}
              title="This trunk is managed by a Twilio connection. Disconnect the connection to remove it."
            >
              <Pill tone="cyan">Managed by Twilio</Pill>
            </a>
          {/if}
        </div>
      </td>
      <td>
        <div class="flex items-center justify-end gap-4">
          <SecondaryButton size="sm" href={`${data.basePath}/sip-trunks/${trunk.id}/edit`}>
            Edit
          </SecondaryButton>
          {#if !trunk.providerConnectionId}
            <SecondaryButton
              size="sm"
              tone="danger"
              onclick={() => {
                toggleDeletePopUp();
                sipTrunkToBeDeleted = trunk;
              }}
            >
              Delete
            </SecondaryButton>
          {/if}
        </div>
      </td>
    </tr>
  {/each}
</Table>
