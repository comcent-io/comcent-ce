<script lang="ts">
  import { onMount } from 'svelte';
  import { page } from '$app/state';
  import { deleteJson, getJson, postJson, putJson } from '$lib/http';
  import SkeletonLoadingList from '$lib/components/SkeletonLoadingList.svelte';
  import toast from '$lib/toast';
  import WebhookForm from './WebhookForm.svelte';
  import Dialog from '$lib/components/Dialog.svelte';
  import Button from '$lib/components/Button.svelte';
  import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';
  import EmptyState from '$lib/components/form/EmptyState.svelte';
  import FormSection from '$lib/components/form/FormSection.svelte';

  // Which rows show their token in full.
  let revealed: Record<string, boolean> = $state({});

  const EVENT_LABELS: Record<string, string> = {
    CALL_UPDATE: 'Call update',
    PRESENCE_UPDATE: 'Presence update',
  };

  function eventLabel(event: string) {
    return EVENT_LABELS[event] ?? event;
  }

  function maskToken(token: string | undefined) {
    return token ? `${token.slice(0, 6)}${'•'.repeat(12)}` : '—';
  }

  async function copyToken(token: string) {
    try {
      await navigator.clipboard.writeText(token);
      toast.success('Auth token copied');
    } catch {
      toast.error('Could not copy the token. Use Show and copy it by hand.');
    }
  }

  type OrgWebhook = {
    id: string;
    name: string;
    webhookUrl: string;
    authToken: string;
    events: string[];
    callUpdate: boolean;
    presenceUpdate: boolean;
  };

  let showNewWebhookModal = $state(false);

  let selectedWebhook: any = $state();

  let showEditWebhookModal = $state(false);

  let loadingWebhook = $state(false);
  let webhooks: OrgWebhook[] = $state([]);

  onMount(async () => {
    loadingWebhook = true;
    const result = await getJson<{ webhooks?: OrgWebhook[] }>(
      `/api/v2/${page.params.subdomain}/settings/webhooks`,
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

  let formData = $state(newFormData());

  let creatingProgress = $state(false);
  async function createWebhook() {
    creatingProgress = true;
    const result = await postJson<OrgWebhook>(
      `/api/v2/${page.params.subdomain}/settings/webhooks`,
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

  // Deleting asks first: it can't be undone, and the receiver silently stops
  // getting calls.
  let webhookToDelete: OrgWebhook | null = $state(null);

  async function confirmDelete() {
    const webhook = webhookToDelete;
    webhookToDelete = null;
    if (webhook) await deleteWebhook(webhook);
  }

  async function deleteWebhook(webhook: OrgWebhook) {
    const result = await deleteJson(
      `/api/v2/${page.params.subdomain}/settings/webhooks/${webhook.id}`,
    );
    if (!result.ok) {
      toast.error(result.error);
      return;
    }

    toast.success('Webhook deleted successfully');
    webhooks = webhooks.filter((wh) => wh.id !== webhook.id);
  }

  let updateProgress = $state(false);
  async function onUpdateWebhook() {
    if (!selectedWebhook) return alert('No webhook selected');
    updateProgress = true;
    const result = await putJson<OrgWebhook>(
      `/api/v2/${page.params.subdomain}/settings/webhooks/${selectedWebhook.id}`,
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

<FormSection
  title="Webhooks"
  description="We POST JSON to your URL when the events you choose happen, so your own systems can react to calls."
  className="mt-4"
>
  {#snippet aside()}
    <Button type="button" onclick={() => (showNewWebhookModal = true)}>New Webhook</Button>
  {/snippet}

  <div
    class="rounded-lg bg-gray-50 p-4 text-sm leading-6 text-gray-600 dark:bg-gray-900 dark:text-gray-300"
  >
    <p>
      <span class="font-medium text-gray-900 dark:text-white">Call update event:</span>
      sent when a call ends and its call story is ready. The body is
      <code class="rounded bg-gray-200 px-1 text-xs dark:bg-gray-700">
        {`{"type": "NEW_CALL_STORY", "data": …}`}
      </code>
      where data is the call as a vCon (the IETF standard for a conversation).
    </p>
    <p>
      <span class="font-medium text-gray-900 dark:text-white">Presence update event:</span>
      sent when a member's presence changes, for example from available to on a call. The body is
      <code class="rounded bg-gray-200 px-1 text-xs dark:bg-gray-700">
        {`{"type": "PRESENCE_UPDATE", "data": …}`}
      </code>
      where data holds the member, the new presence and the one before it.
    </p>
    <p class="mt-2">
      Each request carries the webhook's auth token in the
      <code class="rounded bg-gray-200 px-1 text-xs dark:bg-gray-700">X-Api-Token</code>
      header. Check it before trusting the request.
    </p>
  </div>

  {#if loadingWebhook}
    <SkeletonLoadingList />
  {:else if webhooks.length === 0}
    <EmptyState
      title="No webhooks yet"
      description="Add one to receive every finished call in your own systems, such as a CRM or a data warehouse."
    >
      {#snippet action()}
        <Button type="button" onclick={() => (showNewWebhookModal = true)}>Add webhook</Button>
      {/snippet}
    </EmptyState>
  {:else}
    <div class="overflow-x-auto rounded-lg border border-gray-200 dark:border-gray-700">
      <table class="w-full text-left text-sm text-gray-600 dark:text-gray-300">
        <thead
          class="bg-gray-50 text-xs uppercase text-gray-500 dark:bg-gray-700 dark:text-gray-400"
        >
          <tr>
            <th scope="col" class="px-4 py-3">Webhook</th>
            <th scope="col" class="px-4 py-3">Events</th>
            <th scope="col" class="px-4 py-3">Auth token</th>
            <th scope="col" class="px-4 py-3"><span class="sr-only">Actions</span></th>
          </tr>
        </thead>
        <tbody class="divide-y divide-gray-200 dark:divide-gray-700">
          {#each webhooks as webhook (webhook.id)}
            <tr class="bg-white align-top dark:bg-gray-800">
              <th scope="row" class="px-4 py-3 font-normal">
                <span class="block font-medium text-gray-900 dark:text-white">{webhook.name}</span>
                <span class="block break-all text-xs text-gray-500 dark:text-gray-400">
                  {webhook.webhookUrl}
                </span>
              </th>

              <td class="px-4 py-3">
                <!-- The raw event names for screen readers (and the e2e
                     specs); the badges are the same, readable. -->
                <span class="sr-only">{webhook.events}</span>
                <span class="flex flex-wrap gap-1" aria-hidden="true">
                  {#each webhook.events ?? [] as event (event)}
                    <span
                      class="rounded-full px-2 py-0.5 text-xs font-medium {event === 'CALL_UPDATE'
                        ? 'bg-blue-50 text-blue-700 dark:bg-blue-950 dark:text-blue-300'
                        : 'bg-gray-100 text-gray-600 dark:bg-gray-700 dark:text-gray-300'}"
                    >
                      {eventLabel(event)}
                    </span>
                  {/each}
                </span>
              </td>

              <td class="px-4 py-3">
                <div class="flex items-center gap-2">
                  <code
                    class="max-w-[14rem] truncate rounded bg-gray-100 px-2 py-1 font-mono text-xs text-gray-700 dark:bg-gray-700 dark:text-gray-200"
                  >
                    {revealed[webhook.id] ? webhook.authToken : maskToken(webhook.authToken)}
                  </code>
                  <button
                    type="button"
                    class="text-xs font-medium text-blue-600 hover:underline dark:text-blue-500"
                    aria-label={revealed[webhook.id] ? 'Hide auth token' : 'Show auth token'}
                    onclick={() => (revealed[webhook.id] = !revealed[webhook.id])}
                  >
                    {revealed[webhook.id] ? 'Hide' : 'Show'}
                  </button>
                  <button
                    type="button"
                    class="text-xs font-medium text-blue-600 hover:underline dark:text-blue-500"
                    aria-label="Copy auth token"
                    onclick={() => copyToken(webhook.authToken)}
                  >
                    Copy
                  </button>
                </div>
              </td>

              <td class="whitespace-nowrap px-4 py-3 text-right">
                <button
                  type="button"
                  onclick={() => {
                    selectedWebhook = {
                      id: webhook.id,
                      name: webhook.name,
                      webhookUrl: webhook.webhookUrl,
                      callUpdate: webhook.events.includes('CALL_UPDATE'),
                      presenceUpdate: webhook.events.includes('PRESENCE_UPDATE'),
                    };
                    showEditWebhookModal = true;
                  }}
                  class="mr-4 font-medium text-blue-600 hover:underline dark:text-blue-500"
                >
                  Edit
                </button>
                <button
                  type="button"
                  class="font-medium text-red-600 hover:underline dark:text-red-500"
                  onclick={() => (webhookToDelete = webhook)}
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
</FormSection>

<Dialog
  title="New webhook"
  showDialog={showNewWebhookModal}
  onClose={() => {
    showNewWebhookModal = false;
  }}
>
  <WebhookForm {formData} onSubmit={createWebhook} isProgress={creatingProgress} />
</Dialog>

<Dialog
  title="Edit webhook"
  showDialog={showEditWebhookModal}
  onClose={() => {
    showEditWebhookModal = false;
  }}
>
  <WebhookForm
    formData={selectedWebhook}
    onSubmit={onUpdateWebhook}
    isProgress={updateProgress}
    buttonText="Save"
  />
</Dialog>

{#if webhookToDelete}
  <ConfirmDialog
    message={`Delete the webhook "${webhookToDelete.name}"? Nothing more is sent to ${webhookToDelete.webhookUrl}. This can't be undone.`}
    onCancel={() => (webhookToDelete = null)}
    onConfirm={confirmDelete}
  />
{/if}
