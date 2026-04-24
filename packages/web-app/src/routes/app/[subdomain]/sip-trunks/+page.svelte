<script lang="ts">
  import { onMount } from 'svelte';
  import { page } from '$app/stores';
  import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';
  import { deleteJson, getJson } from '$lib/http';
  import { goto } from '$app/navigation';
  import toast from 'svelte-french-toast';

  export let data;

  interface sipTrunkToBeDeletedType {
    id: string;
    name: string;
  }

  interface SipTrunk {
    id: string;
    name: string;
  }

  let sipTrunkToBeDeleted: sipTrunkToBeDeletedType | null = null;

  let isDeletePopUp = false;
  let errorMessage = '';
  const subdomain = $page.params.subdomain;
  let sipTrunks: SipTrunk[] = [];
  let loading = false;

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

<h3 class="text-3xl font-bold dark:text-white">Sip Trunks</h3>

<div class="my-4">
  <a
    href={`${data.basePath}/sip-trunks/create`}
    class="text-white bg-blue-700 hover:bg-blue-800 focus:ring-4 focus:ring-blue-300 font-medium rounded-lg text-sm px-5 py-2.5 mr-2 mb-2 dark:bg-blue-600 dark:hover:bg-blue-700 focus:outline-none dark:focus:ring-blue-800"
  >
    Create
  </a>
</div>

{#if errorMessage}
  <div class="text-red-500 mb-4">
    {errorMessage}
  </div>
{/if}

{#if isDeletePopUp}
  <ConfirmDialog
    message={`Are you sure you want to delete the ${sipTrunkToBeDeleted?.name}?`}
    on:cancel={toggleDeletePopUp}
    on:confirm={handleSubmit}
  />
{/if}

<div class="relative overflow-x-auto shadow-md sm:rounded-lg">
  <table class="w-full text-sm text-left text-gray-500 dark:text-gray-400">
    <thead class="text-xs text-gray-700 uppercase bg-gray-50 dark:bg-gray-700 dark:text-gray-400">
      <tr>
        <th scope="col" class="px-6 py-3">Name</th>
        <th scope="col" class="px-6 py-3">Action</th>
      </tr>
    </thead>
    <tbody>
      {#if loading}
        <tr class="bg-white border-b dark:bg-gray-900 dark:border-gray-700">
          <td colspan="2" class="px-6 py-4">Loading...</td>
        </tr>
      {:else}
        {#each sipTrunks as trunk}
          <tr class="bg-white border-b dark:bg-gray-900 dark:border-gray-700">
            <td class="px-6 py-4 font-medium text-gray-900 whitespace-nowrap dark:text-white">
              {trunk.name}
            </td>

            <td
              class="space-x-8 px-6 py-4 font-medium text-gray-900 whitespace-nowrap dark:text-white"
            >
              <a
                href={`${data.basePath}/sip-trunks/${trunk.id}/edit`}
                class="font-medium text-blue-600 dark:text-blue-500 hover:underline"
              >
                Edit
              </a>
              <button
                type="button"
                on:click={() => {
                  toggleDeletePopUp();
                  sipTrunkToBeDeleted = trunk;
                }}
                class="font-medium text-red-600 dark:text-red-500 hover:underline"
              >
                Delete
              </button>
            </td>
          </tr>
        {/each}
      {/if}
    </tbody>
  </table>
</div>
