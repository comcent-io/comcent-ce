<script lang="ts">
  import CloseIcon from '$lib/components/Icons/CloseIcon.svelte';
  import PlusIcon from '$lib/components/Icons/PlusIcon.svelte';
  import { page } from '$app/stores';
  import Spinner from '$lib/components/Icons/Spinner.svelte';
  import { onMount } from 'svelte';
  import type { voiceBotData } from './schema';

  export let isUpdate = false;
  let isLoading = false;
  let errorMessage = '';
  const subdomain = $page.params.subdomain;
  let availableQueues: Array<{ id: string; name: string }> = [];
  let isLoadingQueues = false;

  export let formData: voiceBotData = {
    id: '',
    name: '',
    instructions: '',
    notToDoInstructions: '',
    greetingInstructions: '',
    mcpServers: [],
    isHangup: false,
    isEnqueue: false,
    queues: [],
    pipeline: 'DEEPGRAM_AND_OPENAI',
  };

  onMount(async () => {
    await fetchQueues();
  });

  async function fetchQueues() {
    isLoadingQueues = true;
    try {
      const response = await fetch(`/api/v2/${subdomain}/queues`);
      if (!response.ok) throw new Error((await response.json()).error ?? response.statusText);
      const data = await response.json();
      availableQueues = data.queues || [];
    } catch (error: any) {
      console.error('Error fetching queues:', error);
      errorMessage = 'Failed to load queues. Please refresh the page.';
    } finally {
      isLoadingQueues = false;
    }
  }

  async function handleSubmit(event: any) {
    event.preventDefault();
    isLoading = true;
    errorMessage = '';
    try {
      if (isUpdate) {
        const response = await fetch(`/api/v2/${subdomain}/voice-bots/${formData.id}`, {
          method: 'PUT',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(formData),
        });
        if (!response.ok) throw new Error((await response.json()).error ?? response.statusText);
      } else {
        const response = await fetch(`/api/v2/${subdomain}/voice-bots`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(formData),
        });
        if (!response.ok) throw new Error((await response.json()).error ?? response.statusText);
      }
      window.location.href = `/app/${subdomain}/voice-bots`;
    } catch (error: any) {
      try {
        const errorJson = JSON.parse(error.message);
        errorMessage = errorJson[0].message;
      } catch {
        errorMessage = error.message;
      }
    } finally {
      isLoading = false;
    }
  }

  function addQueue() {
    formData.queues.push('');
    formData = formData;
  }

  function removeQueue(index: number) {
    formData.queues.splice(index, 1);
    formData = formData;
  }

  // Get available queues for a specific dropdown (excluding already selected queues in other dropdowns)
  function getAvailableQueuesForDropdown(
    currentIndex: number,
  ): Array<{ id: string; name: string }> {
    const selectedQueuesInOtherDropdowns = formData.queues
      .map((q, idx) => (idx !== currentIndex && q ? q : null))
      .filter((q): q is string => q !== null && q !== '');
    const currentQueue = formData.queues[currentIndex];
    return availableQueues.filter(
      (queue) =>
        !selectedQueuesInOtherDropdowns.includes(queue.name) || queue.name === currentQueue,
    );
  }

  $: remainingQueues = availableQueues.filter((queue) => !formData.queues.includes(queue.name));
  $: canAddMoreQueues = remainingQueues.length > 0;

  function addMcpServer() {
    formData.mcpServers.push({ url: '', token: '' });
    formData = formData;
  }

  function removeMcpServer(index: number) {
    formData.mcpServers.splice(index, 1);
    formData = formData;
  }
</script>

<form method="POST" on:submit={handleSubmit}>
  <div class="mb-6">
    {#if errorMessage}
      <div class="text-red-500 mb-4">
        {errorMessage}
      </div>
    {/if}
    <label for="name" class="block mb-2 text-base font-medium text-gray-900 dark:text-white">
      Name
    </label>
    <input
      type="text"
      id="name"
      name="name"
      bind:value={formData.name}
      class="bg-gray-50 border border-gray-300 text-gray-900 text-sm rounded-lg focus:ring-blue-500 focus:border-blue-500 block w-full p-2.5 dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500"
      placeholder="Voice Bot Name"
      required
    />
  </div>

  <div class="mb-6">
    <label
      for="instructions"
      class="block mb-2 text-base font-medium text-gray-900 dark:text-white"
    >
      Tell the VoiceBot what to do
    </label>
    <textarea
      id="instructions"
      name="instructions"
      bind:value={formData.instructions}
      rows="4"
      class="block p-2.5 w-full text-sm text-gray-900 bg-gray-50 rounded-lg border border-gray-300 focus:ring-blue-500 focus:border-blue-500 dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500"
      placeholder="Write your instructions here"
      required
    ></textarea>
  </div>

  <div class="mb-6">
    <label
      for="notToDoInstructions"
      class="block mb-2 text-base font-medium text-gray-900 dark:text-white"
    >
      Tell the VoiceBot what not to do
    </label>
    <textarea
      id="notToDoInstructions"
      name="notToDoInstructions"
      bind:value={formData.notToDoInstructions}
      rows="4"
      class="block p-2.5 w-full text-sm text-gray-900 bg-gray-50 rounded-lg border border-gray-300 focus:ring-blue-500 focus:border-blue-500 dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500"
      placeholder="If conversation is not related to voice-bot name, then reply that you can't respond. If unrelated question is asked more than three times then hang up."
      required
    ></textarea>
  </div>

  <div class="mb-6">
    <label
      for="greetingInstructions"
      class="block mb-2 text-base font-medium text-gray-900 dark:text-white"
    >
      Tell the VoiceBot how to greet the customers
    </label>
    <textarea
      id="greetingInstructions"
      name="greetingInstructions"
      bind:value={formData.greetingInstructions}
      rows="4"
      class="block p-2.5 w-full text-sm text-gray-900 bg-gray-50 rounded-lg border border-gray-300 focus:ring-blue-500 focus:border-blue-500 dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500"
      placeholder="Greet with appropriate greeting for EST timezone and explicitly mention that you are on recorded line"
      required
    ></textarea>
  </div>

  <div class="mb-6">
    <label for="pipeline" class="block mb-2 text-base font-medium text-gray-900 dark:text-white">
      Pipeline
    </label>
    <select
      id="pipeline"
      name="pipeline"
      bind:value={formData.pipeline}
      class="bg-gray-50 border border-gray-300 text-gray-900 text-sm rounded-lg focus:ring-blue-500 focus:border-blue-500 block w-full p-2.5 dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500"
      required
    >
      <option value="DEEPGRAM_AND_OPENAI">Deepgram and OpenAI</option>
      <option value="REALTIME_API">Realtime API</option>
    </select>
  </div>

  <div class="mb-6">
    <div class="block mb-2 text-base font-medium text-gray-900 dark:text-white">MCP Servers</div>
    {#each formData.mcpServers as mcpServer, index}
      <div class="mb-3 space-y-2">
        <div class="flex items-center space-x-1">
          <input
            type="text"
            id="mcpServerUrl"
            name="mcpServerUrl"
            bind:value={mcpServer.url}
            class="bg-gray-50 border border-gray-300 text-gray-900 text-sm rounded-lg focus:ring-blue-500 focus:border-blue-500 block w-full p-2.5 dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500"
            placeholder="MCP Server URL"
          />
          <button
            type="button"
            on:click={() => removeMcpServer(index)}
            class="text-gray-400 bg-transparent rounded-lg text-sm w-8 h-8 ml-auto inline-flex justify-center items-center"
          >
            <CloseIcon />
          </button>
        </div>
        <input
          type="text"
          id="mcpServerToken"
          name="mcpServerToken"
          bind:value={mcpServer.token}
          class="bg-gray-50 border border-gray-300 text-gray-900 text-sm rounded-lg focus:ring-blue-500 focus:border-blue-500 block w-full p-2.5 dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500"
          placeholder="Authorization Token"
        />
      </div>
    {/each}
    <button
      type="button"
      on:click={addMcpServer}
      class="text-white bg-blue-700 hover:bg-blue-800 focus:ring-4 focus:ring-blue-300 font-medium rounded-lg text-sm py-2 mr-2 px-2 dark:bg-blue-600 dark:hover:bg-blue-700 focus:outline-none dark:focus:ring-blue-800"
    >
      <div class="flex items-center">
        <PlusIcon /> Add MCP Server
      </div>
    </button>
  </div>

  <fieldset>
    <legend class="block mb-2 text-lg font-medium text-gray-900 dark:text-white">Functions</legend>

    <!-- <fieldset>
      <legend class="block mb-2 text-base font-medium text-gray-900 dark:text-white">
        In-built Functions
      </legend> -->

    <div class="mb-6">
      <label for="hangupFunction" class="flex items-center mb-4">
        <input
          type="checkbox"
          id="hangupFunction"
          name="hangupFunction"
          class="mr-2"
          bind:checked={formData.isHangup}
        />
        <span class="text-base font-medium text-gray-900 dark:text-white">
          hangup (Description: used to hang up the call)
        </span>
      </label>

      <label for="enqueueFunction" class="flex items-center mb-2">
        <input
          type="checkbox"
          id="enqueueFunction"
          name="enqueueFunction"
          bind:checked={formData.isEnqueue}
          class="mr-2"
        />
        <span class="text-base font-medium text-gray-900 dark:text-white">
          enqueue (Description: used to transfer to queue specified in params)
        </span>
      </label>
      {#if formData.isEnqueue}
        {#if isLoadingQueues}
          <div class="mb-3 text-sm text-gray-500 dark:text-gray-400">Loading queues...</div>
        {:else if availableQueues.length === 0}
          <div class="mb-3 text-sm text-yellow-500 dark:text-yellow-400">
            No queues available. Please create a queue first.
          </div>
        {:else}
          {#each formData.queues as queue, index}
            <div class="flex items-center space-x-1">
              <select
                id="queueName"
                name="queueName"
                bind:value={queue}
                class="bg-gray-50 mb-3 border border-gray-300 text-gray-900 text-xs rounded-lg focus:ring-blue-500 focus:border-blue-500 block w-1/3 p-2.5 dark:bg-gray-700 dark:border-gray-600 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500"
                required
              >
                <option value="">Select a queue</option>
                {#each getAvailableQueuesForDropdown(index) as availableQueue}
                  <option value={availableQueue.name}>{availableQueue.name}</option>
                {/each}
              </select>
              <button
                type="button"
                on:click={() => removeQueue(index)}
                class="text-gray-400 bg-transparent rounded-lg text-sm w-8 h-8 ml-auto inline-flex justify-center items-center"
              >
                <CloseIcon />
              </button>
            </div>
          {/each}
          {#if canAddMoreQueues}
            <button
              type="button"
              on:click={addQueue}
              class="text-white bg-blue-700 hover:bg-blue-800 focus:ring-4 focus:ring-blue-300 font-medium rounded-lg text-sm py-2 mr-2 px-2 mb-3 dark:bg-blue-600 dark:hover:bg-blue-700 focus:outline-none dark:focus:ring-blue-800"
            >
              <div class="flex items-center">
                <PlusIcon /> Add Queue
              </div>
            </button>
          {/if}
        {/if}
      {/if}
    </div>
    <!-- </fieldset> -->
  </fieldset>
  <button
    type="submit"
    disabled={isLoading}
    class="text-white bg-blue-700 hover:bg-blue-800 focus:ring-4 focus:outline-none focus:ring-blue-300 font-medium rounded-lg text-sm w-full sm:w-auto px-5 py-2.5 text-center dark:bg-blue-600 dark:hover:bg-blue-700 dark:focus:ring-blue-800"
  >
    {#if isLoading}
      <Spinner />
    {:else}
      {`${isUpdate ? 'Update' : 'Create'}`}
    {/if}
  </button>
</form>
