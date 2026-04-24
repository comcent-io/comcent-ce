<script lang="ts">
  import Button from '$lib/components/Button.svelte';
  import { onMount } from 'svelte';
  import { page } from '$app/stores';
  import { deleteJson, getJson, postJson } from '$lib/http';
  import Dialog from '$lib/components/Dialog.svelte';
  import SkeletonLoadingList from '$lib/components/SkeletonLoadingList.svelte';
  import toast from 'svelte-french-toast';
  import CopyIcon from '$lib/components/Icons/CopyIcon.svelte';

  let loading = false;
  let apiKeys: { apiKey: string; name: string }[] = [];

  onMount(async () => {
    loading = true;
    const result = await getJson<{ apiKeys?: { apiKey: string; name: string }[] }>(
      `/api/v2/${$page.params.subdomain}/settings/api-keys`,
    );
    if (result.ok) {
      apiKeys = Array.isArray(result.data) ? result.data : (result.data.apiKeys ?? []);
    } else {
      toast.error(result.error);
    }
    loading = false;
  });

  function newApiKeyForm() {
    return {
      name: '',
    };
  }

  let formData = newApiKeyForm();

  let showNewKeyModal = false;

  let createLoading = false;
  async function onCreateApiKey() {
    createLoading = true;
    const result = await postJson<{ apiKey: string; name: string }>(
      `/api/v2/${$page.params.subdomain}/settings/api-keys`,
      formData,
    );
    if (!result.ok) {
      toast.error(result.error);
      createLoading = false;
      return;
    }

    apiKeys = [...apiKeys, result.data];
    showNewKeyModal = false;
    toast.success('API Key created successfully');
    createLoading = false;
  }

  let onDeleteProgress = false;
  async function onDeleteApiKey(apiKey: { apiKey: string }) {
    onDeleteProgress = true;
    const key = apiKey.apiKey;
    const result = await deleteJson(`/api/v2/${$page.params.subdomain}/settings/api-keys/${key}`);
    if (!result.ok) {
      toast.error(result.error);
      onDeleteProgress = false;
      return;
    }

    apiKeys = apiKeys.filter((k) => k.apiKey !== key);
    toast.success('API Key deleted successfully');
    onDeleteProgress = false;
  }
</script>

{#if loading}
  <SkeletonLoadingList className="my-4" />
{:else}
  <div class="relative overflow-x-auto shadow-md sm:rounded-lg mt-4">
    <div>
      <Button type="button" on:click={() => (showNewKeyModal = true)}>New Key</Button>
    </div>
    <table class="w-full text-sm text-left text-gray-500 dark:text-gray-400">
      <caption>API Keys</caption>
      <thead class="text-xs text-gray-700 uppercase bg-gray-50 dark:bg-gray-700 dark:text-gray-400">
        <tr>
          <th scope="col" class="px-6 py-3">Name</th>
          <th scope="col" class="px-6 py-3">Key</th>
          <th scope="col" class="px-6 py-3">
            <span class="sr-only">Edit</span>
            <span class="sr-only">Delete</span>
          </th>
        </tr>
      </thead>
      <tbody>
        {#each apiKeys as apiKey}
          <tr
            class="bg-white border-b dark:bg-gray-800 dark:border-gray-700 hover:bg-gray-50 dark:hover:bg-gray-600"
          >
            <th
              scope="row"
              class="px-6 py-4 font-medium text-gray-900 whitespace-nowrap dark:text-white"
            >
              {apiKey.name}
            </th>
            <td class="px-6 py-4">
              <div class="flex">
                <input
                  type="password"
                  autocomplete="off"
                  readonly
                  class="rounded-none rounded-l-lg bg-gray-300 border text-gray-900 focus:ring-blue-500 focus:border-blue-500 block flex-1 min-w-0 w-full text-sm border-gray-300 p-2.5 dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500"
                  value={apiKey.apiKey}
                />
                <button
                  on:click={() => navigator.clipboard.writeText(apiKey.apiKey)}
                  class="dark:text-gray-400 dark:border-gray-600 border border-l-0 border-gray-300 rounded-r-md px-3 text-gray-900 bg-gray-200 hover:bg-gray-300 focus:ring-4 focus:outline-none focus:ring-blue-300 font-medium text-sm p-2.5 text-center inline-flex items-center mr-2 dark:bg-blue-600 dark:hover:bg-blue-700 dark:focus:ring-blue-800"
                >
                  <CopyIcon />
                </button>
              </div>
            </td>
            <td class="px-6 py-4 text-right">
              <Button
                type="submit"
                progress={onDeleteProgress}
                color="danger"
                className="px-2.5"
                on:click={() => onDeleteApiKey(apiKey)}
              >
                Delete
              </Button>
            </td>
          </tr>
        {/each}
      </tbody>
    </table>
  </div>
{/if}

<Dialog title="New Api Key" showDialog={showNewKeyModal} on:close={() => (showNewKeyModal = false)}>
  <div class="px-6 py-6 lg:px-8">
    <form class="space-y-6">
      <div>
        <label for="name" class="block mb-2 text-sm font-medium text-gray-900 dark:text-white">
          Name
        </label>
        <input
          type="text"
          name="name"
          class="bg-gray-50 border border-gray-300 text-gray-900 text-sm rounded-lg focus:ring-blue-500 focus:border-blue-500 block w-full p-2.5 dark:bg-gray-600 dark:border-gray-500 dark:placeholder-gray-400 dark:text-white"
          placeholder="Friendly name"
          required
          bind:value={formData.name}
        />
      </div>
      <Button type="submit" progress={createLoading} on:click={onCreateApiKey}>Create</Button>
    </form>
  </div>
</Dialog>
