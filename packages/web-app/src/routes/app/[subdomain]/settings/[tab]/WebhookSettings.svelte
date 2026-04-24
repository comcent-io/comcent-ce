<script lang="ts">
  import { onMount } from 'svelte';
  import { page } from '$app/stores';
  import { deleteJson, getJson, postJson, putJson } from '$lib/http';
  import SkeletonLoadingList from '$lib/components/SkeletonLoadingList.svelte';
  import toast from 'svelte-french-toast';
  import WebhookForm from './WebhookForm.svelte';
  import Dialog from '$lib/components/Dialog.svelte';
  import Button from '$lib/components/Button.svelte';

  type OrgWebhook = {
    id: string;
    name: string;
    webhookUrl: string;
    authToken: string;
    events: string[];
    callUpdate: boolean;
    presenceUpdate: boolean;
  };

  let showNewWebhookModal = false;

  let selectedWebhook: any;

  let showEditWebhookModal = false;

  let loadingWebhook = false;
  let webhooks: OrgWebhook[] = [];

  onMount(async () => {
    loadingWebhook = true;
    const result = await getJson<{ webhooks?: OrgWebhook[] }>(
      `/api/v2/${$page.params.subdomain}/settings/webhooks`,
    );
    if (result.ok) {
      webhooks = Array.isArray(result.data) ? result.data : (result.data.webhooks ?? []);
    } else {
      toast.error(result.error);
    }
    loadingWebhook = false;
  });

  function newFormData() {
    return {
      name: '',
      webhookUrl: '',
      callUpdate: false,
      presenceUpdate: false,
    };
  }

  let formData = newFormData();

  let creatingProgress = false;
  async function createWebhook() {
    creatingProgress = true;
    const result = await postJson<OrgWebhook>(
      `/api/v2/${$page.params.subdomain}/settings/webhooks`,
      formData,
    );
    if (!result.ok) {
      toast.error(result.error);
      creatingProgress = false;
      return;
    }

    webhooks = [...webhooks, result.data];
    formData = newFormData();
    showNewWebhookModal = false;
    creatingProgress = false;
  }

  async function deleteWebhook(webhook: OrgWebhook) {
    const result = await deleteJson(
      `/api/v2/${$page.params.subdomain}/settings/webhooks/${webhook.id}`,
    );
    if (!result.ok) {
      toast.error(result.error);
      return;
    }

    toast.success('Webhook deleted successfully');
    webhooks = webhooks.filter((wh) => wh.id !== webhook.id);
  }

  let updateProgress = false;
  async function onUpdateWebhook() {
    if (!selectedWebhook) return alert('No webhook selected');
    updateProgress = true;
    const result = await putJson<OrgWebhook>(
      `/api/v2/${$page.params.subdomain}/settings/webhooks/${selectedWebhook.id}`,
      selectedWebhook,
    );
    if (!result.ok) {
      toast.error(result.error);
      updateProgress = false;
      return;
    }

    webhooks = webhooks.map((wh) => (wh.id === selectedWebhook!.id ? result.data : wh));
    showEditWebhookModal = false;
    selectedWebhook = undefined;
    updateProgress = false;
  }
</script>

{#if loadingWebhook}
  <SkeletonLoadingList className="my-4" />
{:else}
  <div class="relative overflow-x-auto shadow-md sm:rounded-lg mt-4">
    <div>
      <Button type="button" on:click={() => (showNewWebhookModal = true)}>New Webhook</Button>
    </div>

    <table class="w-full text-sm text-left text-gray-500 dark:text-gray-400 mb-20">
      <caption>Webhooks</caption>
      <thead class="text-xs text-gray-700 uppercase bg-gray-50 dark:bg-gray-700 dark:text-gray-400">
        <tr>
          <th scope="col" class="px-6 py-3">Name</th>
          <th scope="col" class="px-6 py-3">URL</th>
          <th scope="col" class="px-6 py-3">Auth Token</th>
          <th scope="col" class="px-6 py-3">Events</th>
          <th scope="col" class="px-6 py-3">
            <span class="sr-only">Edit</span>
          </th>
          <th scope="col" class="px-6 py-3">
            <span class="sr-only">Delete</span>
          </th>
        </tr>
      </thead>
      <tbody>
        {#each webhooks as webhook}
          <tr
            class="bg-white border-b dark:bg-gray-800 dark:border-gray-700 hover:bg-gray-50 dark:hover:bg-gray-600"
          >
            <th
              scope="row"
              class="px-6 py-4 font-medium text-gray-900 whitespace-nowrap dark:text-white"
            >
              {webhook.name}
            </th>

            <th
              scope="row"
              class="px-6 py-4 font-medium text-gray-900 whitespace-nowrap dark:text-white"
            >
              {webhook.webhookUrl}
            </th>

            <td class="px-6 py-4">
              <div class="flex">
                <input
                  type="password"
                  autocomplete="off"
                  readonly
                  class="rounded-none rounded-l-lg bg-gray-300 border text-gray-900 focus:ring-blue-500 focus:border-blue-500 block flex-1 min-w-0 w-full text-sm border-gray-300 p-2.5 dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500"
                  value={webhook.authToken}
                />
                <button
                  on:click={() => navigator.clipboard.writeText(webhook.authToken)}
                  class="dark:text-gray-400 dark:border-gray-600 border border-l-0 border-gray-300 rounded-r-md px-3 text-gray-900 bg-gray-200 hover:bg-gray-300 focus:ring-4 focus:outline-none focus:ring-blue-300 font-medium text-sm p-2.5 text-center inline-flex items-center mr-2 dark:bg-blue-600 dark:hover:bg-blue-700 dark:focus:ring-blue-800"
                >
                  <svg
                    class="w-6 h-6 text-gray-800 dark:text-white"
                    aria-hidden="true"
                    xmlns="http://www.w3.org/2000/svg"
                    fill="currentColor"
                    viewBox="0 0 18 20"
                  >
                    <path
                      d="M5 9V4.13a2.96 2.96 0 0 0-1.293.749L.879 7.707A2.96 2.96 0 0 0 .13 9H5Zm11.066-9H9.829a2.98 2.98 0 0 0-2.122.879L7 1.584A.987.987 0 0 0 6.766 2h4.3A3.972 3.972 0 0 1 15 6v10h1.066A1.97 1.97 0 0 0 18 14V2a1.97 1.97 0 0 0-1.934-2Z"
                    />
                    <path
                      d="M11.066 4H7v5a2 2 0 0 1-2 2H0v7a1.969 1.969 0 0 0 1.933 2h9.133A1.97 1.97 0 0 0 13 18V6a1.97 1.97 0 0 0-1.934-2Z"
                    />
                  </svg>
                </button>
              </div>
            </td>

            <th
              scope="row"
              class="px-6 py-4 font-medium text-gray-900 whitespace-nowrap dark:text-white"
            >
              {webhook.events}
            </th>

            <td class="px-6 py-4 text-right">
              <button
                type="button"
                on:click={() => {
                  selectedWebhook = {
                    id: webhook.id,
                    name: webhook.name,
                    webhookUrl: webhook.webhookUrl,
                    callUpdate: webhook.events.includes('CALL_UPDATE'),
                    presenceUpdate: webhook.events.includes('PRESENCE_UPDATE'),
                  };
                  showEditWebhookModal = true;
                }}
                class="font-medium text-green-600 dark:text-green-500 hover:underline mr-4"
              >
                Edit
              </button>
            </td>

            <td class="px-6 py-4 text-right">
              <button
                type="submit"
                class="font-medium text-blue-600 dark:text-blue-500 hover:underline"
                on:click={() => deleteWebhook(webhook)}
              >
                Delete
              </button>
            </td>
          </tr>
        {/each}
      </tbody>
    </table>
  </div>
{/if}

<Dialog
  title="New Webhook"
  showDialog={showNewWebhookModal}
  on:close={() => {
    showNewWebhookModal = false;
  }}
>
  <div class="px-6 py-6 lg:px-8">
    <WebhookForm {formData} on:submit={createWebhook} isProgress={creatingProgress} />
  </div>
</Dialog>

<Dialog
  title="Update Webhook"
  showDialog={showEditWebhookModal}
  on:close={() => {
    showEditWebhookModal = false;
  }}
>
  <div class="px-6 py-6 lg:px-8">
    <WebhookForm
      formData={selectedWebhook}
      on:submit={onUpdateWebhook}
      isProgress={updateProgress}
    />
  </div>
</Dialog>
