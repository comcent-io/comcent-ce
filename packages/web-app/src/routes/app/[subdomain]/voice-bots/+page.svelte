<script lang="ts">
  import { onMount } from 'svelte';
  import ClipBoardCopyIcon from '$lib/components/Icons/ClipBoardCopyIcon.svelte';
  import { page } from '$app/state';
  import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';
  import ErrorMessage from '$lib/components/ErrorMessage.svelte';
  import Button from '$lib/components/Button.svelte';
  import Table from '$lib/components/Table.svelte';
  import EmptyState from '$lib/components/form/EmptyState.svelte';
  import Input from '$lib/components/form/Input.svelte';
  import PageHeader from '$lib/components/form/PageHeader.svelte';
  import SecondaryButton from '$lib/components/form/SecondaryButton.svelte';
  import { deleteJson, getJson } from '$lib/http';

  let { data } = $props();

  interface voiceBotToBeDeletedType {
    id: string;
    name: string;
  }

  interface VoiceBot {
    id: string;
    name: string;
    apiKey: string;
  }

  let voiceBotToBeDeleted: voiceBotToBeDeletedType | null = $state(null);

  let isDeletePopUp = $state(false);
  let errorMessage = $state('');
  const subdomain = page.params.subdomain;
  let voiceBots: VoiceBot[] = $state([]);
  let loading = $state(false);

  async function loadVoiceBots() {
    loading = true;
    const result = await getJson<{ voiceBots?: VoiceBot[] }>(`/api/v2/${subdomain}/voice-bots`);
    if (result.ok) {
      voiceBots = result.data.voiceBots ?? [];
    } else {
      errorMessage = result.error;
    }
    loading = false;
  }

  onMount(() => {
    void loadVoiceBots();
  });

  function toggleDeletePopUp() {
    isDeletePopUp = !isDeletePopUp;
  }

  async function handleSubmit() {
    errorMessage = '';
    isDeletePopUp = false;
    const result = await deleteJson(`/api/v2/${subdomain}/voice-bots/${voiceBotToBeDeleted?.id}`);
    if (!result.ok) {
      errorMessage = result.error;
      return;
    }

    voiceBots = voiceBots.filter((voiceBot) => voiceBot.id !== voiceBotToBeDeleted!.id);
  }
</script>

<PageHeader
  title="Voice Bots"
  description="AI agents that answer calls, talk to callers in natural speech and can hand a call to a queue. Each bot has its own instructions and API key."
>
  {#snippet actions()}
    <Button href={`${data.basePath}/voice-bots/create`} id="add-new-no-btn">Create</Button>
  {/snippet}
</PageHeader>

{#if errorMessage}
  <ErrorMessage error={{ message: errorMessage, formErrors: [] }} />
{/if}

{#if isDeletePopUp}
  <ConfirmDialog
    message={`Are you sure you want to delete the ${voiceBotToBeDeleted?.name}?`}
    onCancel={toggleDeletePopUp}
    onConfirm={handleSubmit}
  />
{/if}

<Table
  columns={['Name', 'API key', { label: 'Actions', srOnly: true }]}
  {loading}
  isEmpty={voiceBots.length === 0}
>
  {#snippet empty()}
    <EmptyState
      title="No voice bots yet"
      description="A voice bot answers calls for you, following the instructions you give it. Click Create above to set up your first one."
    />
  {/snippet}
  {#each voiceBots as voiceBot (voiceBot.id)}
    <tr>
      <td class="whitespace-nowrap font-medium text-gray-900 dark:text-white">{voiceBot.name}</td>
      <td>
        <!-- The key stays hidden on screen; Copy puts it on the clipboard. -->
        <div class="flex max-w-sm items-center gap-2">
          <Input
            type="password"
            autocomplete="off"
            readonly
            value={voiceBot.apiKey}
            aria-label={`API key for ${voiceBot.name}`}
          />
          <SecondaryButton
            size="sm"
            title="Copy API key"
            aria-label={`Copy API key for ${voiceBot.name}`}
            onclick={() => navigator.clipboard.writeText(voiceBot.apiKey)}
          >
            <ClipBoardCopyIcon />
          </SecondaryButton>
        </div>
      </td>
      <td>
        <div class="flex items-center justify-end gap-4">
          <SecondaryButton size="sm" href={`${data.basePath}/voice-bots/${voiceBot.id}/edit`}>
            Edit
          </SecondaryButton>
          <SecondaryButton
            size="sm"
            tone="danger"
            onclick={() => {
              voiceBotToBeDeleted = voiceBot;
              toggleDeletePopUp();
            }}
          >
            Delete
          </SecondaryButton>
        </div>
      </td>
    </tr>
  {/each}
</Table>
