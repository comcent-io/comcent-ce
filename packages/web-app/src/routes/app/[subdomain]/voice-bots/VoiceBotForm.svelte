<script lang="ts">
  import { page } from '$app/state';
  import { onMount } from 'svelte';
  import Button from '$lib/components/Button.svelte';
  import CheckboxRow from '$lib/components/form/CheckboxRow.svelte';
  import Field from '$lib/components/form/Field.svelte';
  import FormActions from '$lib/components/form/FormActions.svelte';
  import FormSection from '$lib/components/form/FormSection.svelte';
  import Input from '$lib/components/form/Input.svelte';
  import RemoveButton from '$lib/components/form/RemoveButton.svelte';
  import SecondaryButton from '$lib/components/form/SecondaryButton.svelte';
  import Select from '$lib/components/form/Select.svelte';
  import Textarea from '$lib/components/form/Textarea.svelte';
  import type { voiceBotData } from './schema';

  let isLoading = $state(false);
  let errorMessage = $state('');
  const subdomain = page.params.subdomain;
  let availableQueues: Array<{ id: string; name: string }> = $state([]);
  let isLoadingQueues = $state(false);

  interface Props {
    isUpdate?: boolean;
    formData?: voiceBotData;
  }

  let {
    isUpdate = false,
    formData = $bindable({
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
    }),
  }: Props = $props();

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

  let remainingQueues = $derived(
    availableQueues.filter((queue) => !formData.queues.includes(queue.name)),
  );
  let canAddMoreQueues = $derived(remainingQueues.length > 0);

  function addMcpServer() {
    formData.mcpServers.push({ url: '', token: '' });
    formData = formData;
  }

  function removeMcpServer(index: number) {
    formData.mcpServers.splice(index, 1);
    formData = formData;
  }
</script>

<form method="POST" class="space-y-6" onsubmit={handleSubmit}>
  {#if errorMessage}
    <div
      class="rounded-lg border border-red-200 bg-red-50 p-4 text-sm text-red-700 dark:border-red-900 dark:bg-gray-800 dark:text-red-400"
      role="alert"
    >
      {errorMessage}
    </div>
  {/if}

  <FormSection
    title="Name"
    description="How the bot shows in your voice bot list, on numbers and in call history."
  >
    <div>
      <label for="name" class="sr-only">Name</label>
      <Input
        type="text"
        id="name"
        name="name"
        bind:value={formData.name}
        placeholder="Voice Bot Name"
        required
      />
    </div>
  </FormSection>

  <FormSection
    title="Instructions"
    description="Brief the bot the way you would brief a new colleague on the phones. It follows these on every call."
  >
    <Field
      for="instructions"
      label="What it should do"
      hint="Its job, what it knows about your business, and how to handle a typical call."
    >
      <Textarea
        id="instructions"
        name="instructions"
        bind:value={formData.instructions}
        rows={6}
        placeholder="Write your instructions here"
        required
      />
    </Field>

    <Field
      for="notToDoInstructions"
      label="What it must not do"
      hint="Topics to refuse, promises it can't make, and when to give up and hang up."
    >
      <Textarea
        id="notToDoInstructions"
        name="notToDoInstructions"
        bind:value={formData.notToDoInstructions}
        rows={4}
        placeholder="If conversation is not related to voice-bot name, then reply that you can't respond. If unrelated question is asked more than three times then hang up."
        required
      />
    </Field>

    <Field
      for="greetingInstructions"
      label="How it greets callers"
      hint="The first thing callers hear, e.g. your company's name and that the call is recorded."
    >
      <Textarea
        id="greetingInstructions"
        name="greetingInstructions"
        bind:value={formData.greetingInstructions}
        rows={3}
        placeholder="Greet with appropriate greeting for EST timezone and explicitly mention that you are on recorded line"
        required
      />
    </Field>
  </FormSection>

  <FormSection title="Voice pipeline" description="How the bot listens and speaks.">
    <Field for="pipeline" label="Pipeline">
      <Select id="pipeline" name="pipeline" bind:value={formData.pipeline} required>
        <option value="DEEPGRAM_AND_OPENAI">Deepgram and OpenAI</option>
        <option value="REALTIME_API">Realtime API</option>
      </Select>
    </Field>
  </FormSection>

  <FormSection title="Actions" description="What the bot may do on a call besides talking.">
    <div class="space-y-3">
      <CheckboxRow
        id="hangupFunction"
        label="Hang up"
        description="End the call when the conversation is over."
        bind:checked={formData.isHangup}
      />
      <CheckboxRow
        id="enqueueFunction"
        label="Transfer to a queue"
        description="Hand the caller to one of these queues when they need a person."
        bind:checked={formData.isEnqueue}
      >
        {#if isLoadingQueues}
          <p class="text-sm text-gray-500 dark:text-gray-400">Loading queues…</p>
        {:else if availableQueues.length === 0}
          <p class="text-sm text-yellow-700 dark:text-yellow-400">
            No queues yet. Create a queue first, then come back to pick it here.
          </p>
        {:else}
          <div class="space-y-2">
            {#each formData.queues as _queue, index}
              <div class="flex items-center gap-2">
                <label for="queueName" class="sr-only">Queue</label>
                <Select
                  id="queueName"
                  name="queueName"
                  bind:value={formData.queues[index]}
                  class="sm:max-w-xs"
                  required
                >
                  <option value="">Select a queue</option>
                  {#each getAvailableQueuesForDropdown(index) as availableQueue}
                    <option value={availableQueue.name}>{availableQueue.name}</option>
                  {/each}
                </Select>
                <RemoveButton label="Remove queue" onclick={() => removeQueue(index)} />
              </div>
            {/each}
            {#if formData.queues.length === 0}
              <p class="text-xs text-gray-500 dark:text-gray-400">
                Pick at least one queue the bot can transfer to.
              </p>
            {/if}
            {#if canAddMoreQueues}
              <SecondaryButton size="sm" onclick={addQueue}>
                <span aria-hidden="true" class="mr-1">+</span>
                Add Queue
              </SecondaryButton>
            {/if}
          </div>
        {/if}
      </CheckboxRow>
    </div>
  </FormSection>

  <FormSection
    title="MCP servers"
    description="Tools the bot can use during a call, such as looking up an order, served from your own MCP (Model Context Protocol) servers."
  >
    <div class="space-y-3">
      {#each formData.mcpServers as mcpServer, index}
        <div
          class="flex items-start gap-2 rounded-lg border border-gray-200 p-3 dark:border-gray-700"
        >
          <div class="grid flex-1 gap-2 sm:grid-cols-2">
            <div>
              <label for="mcpServerUrl" class="sr-only">MCP server URL</label>
              <Input
                type="text"
                id="mcpServerUrl"
                name="mcpServerUrl"
                bind:value={mcpServer.url}
                placeholder="MCP Server URL"
              />
            </div>
            <div>
              <label for="mcpServerToken" class="sr-only">Authorization token</label>
              <Input
                type="text"
                id="mcpServerToken"
                name="mcpServerToken"
                bind:value={mcpServer.token}
                placeholder="Authorization Token"
              />
            </div>
          </div>
          <RemoveButton label="Remove MCP server" onclick={() => removeMcpServer(index)} />
        </div>
      {:else}
        <p class="text-sm text-gray-500 dark:text-gray-400">None added.</p>
      {/each}
      <SecondaryButton size="sm" onclick={addMcpServer}>
        <span aria-hidden="true" class="mr-1">+</span>
        Add MCP Server
      </SecondaryButton>
    </div>
  </FormSection>

  <FormActions cancelHref={`/app/${subdomain}/voice-bots`}>
    <Button type="submit" progress={isLoading}>{isUpdate ? 'Update' : 'Create'}</Button>
  </FormActions>
</form>
