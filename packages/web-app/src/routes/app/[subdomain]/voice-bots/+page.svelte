<script lang="ts">
  import { onMount } from 'svelte';
  import H3 from '$lib/components/html/H3.svelte';
  import ClipBoardCopyIcon from '$lib/components/Icons/ClipBoardCopyIcon.svelte';
  import { page } from '$app/stores';
  import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';
  import { deleteJson, getJson } from '$lib/http';

  export let data;

  interface voiceBotToBeDeletedType {
    id: string;
    name: string;
  }

  interface VoiceBot {
    id: string;
    name: string;
    apiKey: string;
  }

  let voiceBotToBeDeleted: voiceBotToBeDeletedType | null = null;

  let isDeletePopUp = false;
  let errorMessage = '';
  const subdomain = $page.params.subdomain;
  let voiceBots: VoiceBot[] = [];
  let loading = false;

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

<H3>Voice Bots</H3>

<div class="my-4">
  <a
    href={`${data.basePath}/voice-bots/create`}
    id="add-new-no-btn"
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
    message={`Are you sure you want to delete the ${voiceBotToBeDeleted?.name}?`}
    on:cancel={toggleDeletePopUp}
    on:confirm={handleSubmit}
  />
{/if}

<div class="relative overflow-x-auto shadow-md sm:rounded-lg">
  <table class="w-full text-sm text-left text-gray-500 dark:text-gray-400">
    <thead class="text-xs text-gray-700 uppercase bg-gray-50 dark:bg-gray-700 dark:text-gray-400">
      <tr>
        <th scope="col" class="px-6 py-3">Name</th>
        <th scope="col" class="px-6 py-3">Api Key</th>
        <th scope="col" class="px-6 py-3">Action</th>
      </tr>
    </thead>
    <tbody>
      {#if loading}
        <tr class="bg-white border-b dark:bg-gray-900 dark:border-gray-700">
          <td colspan="3" class="px-6 py-4">Loading...</td>
        </tr>
      {:else}
        {#each voiceBots as voiceBot}
          <tr
            class="bg-white border-b dark:bg-gray-900 dark:border-gray-700 hover:bg-gray-100 dark:hover:bg-gray-800 cursor-pointer"
          >
            <td class="px-6 py-4 font-medium text-gray-900 whitespace-nowrap dark:text-white">
              {voiceBot.name}
            </td>
            <td class="px-6 py-4 font-medium text-gray-900 whitespace-nowrap dark:text-white">
              <div class="flex">
                <input
                  type="password"
                  autocomplete="off"
                  readonly
                  class="rounded-none rounded-l-lg bg-gray-300 border text-gray-900 focus:ring-blue-500 focus:border-blue-500 block flex-1 min-w-0 w-full text-sm border-gray-300 p-2.5 dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500"
                  value={voiceBot.apiKey}
                />
                <button
                  on:click={() => navigator.clipboard.writeText(voiceBot.apiKey)}
                  class="dark:text-gray-400 dark:border-gray-600 border border-l-0 border-gray-300 rounded-r-md px-3 text-gray-900 bg-gray-200 hover:bg-gray-300 focus:ring-4 focus:outline-none focus:ring-blue-300 font-medium text-sm p-2.5 text-center inline-flex items-center mr-2 dark:bg-blue-600 dark:hover:bg-blue-700 dark:focus:ring-blue-800"
                >
                  <ClipBoardCopyIcon />
                </button>
              </div>
            </td>
            <td
              class="space-x-8 px-6 py-4 font-medium text-gray-900 whitespace-nowrap dark:text-white"
            >
              <a
                href={`${data.basePath}/voice-bots/${voiceBot.id}/edit`}
                class="font-medium text-blue-600 dark:text-blue-500 hover:underline"
              >
                Edit
              </a>
              <button
                type="button"
                on:click={toggleDeletePopUp}
                on:click={() => {
                  voiceBotToBeDeleted = voiceBot;
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
