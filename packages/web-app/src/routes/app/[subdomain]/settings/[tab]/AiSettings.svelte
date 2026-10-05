<script lang="ts">
  import Button from '$lib/components/Button.svelte';
  import { page } from '$app/state';
  import { getJson, postJson } from '$lib/http';
  import toast from '$lib/toast';
  import { onMount } from 'svelte';
  import SkeletonLoadingList from '$lib/components/SkeletonLoadingList.svelte';
  import Card from '$lib/components/Card.svelte';
  import Field from '$lib/components/form/Field.svelte';
  import FormActions from '$lib/components/form/FormActions.svelte';
  import FormSection from '$lib/components/form/FormSection.svelte';
  import Toggle from '$lib/components/form/Toggle.svelte';
  import Hint from '$lib/components/form/Hint.svelte';
  import Input from '$lib/components/form/Input.svelte';
  import RemoveButton from '$lib/components/form/RemoveButton.svelte';
  import Select from '$lib/components/form/Select.svelte';
  import moment from 'moment-timezone';

  let aiSettings = $state({
    enableTranscription: false,
    enableSentimentAnalysis: false,
    enableSummary: false,
    enableLabels: false,
    enableDailySummary: false,
    dailySummaryTimeZone: 'UTC',
    dailySummaryTime: '09:00',
  });

  let labels = $state([{ id: 1, name: '', description: '' }]);
  let nextLabelId = 2;

  let loading = $state(false);
  let loaded = $state(false);

  // All available timezones for the dropdown
  const timezones = moment.tz.names();
  onMount(async () => {
    loading = true;
    const result = await getJson<any>(`/api/v2/${page.params.subdomain}/settings/ai-analysis`);
    if (!result.ok) {
      toast.error('Error occurred while fetching settings. Please try again later.');
      loading = false;
      return;
    }

    const data = result.data;
    aiSettings = data;

    // Load labels if they exist
    if (data.labels && data.labels.length > 0) {
      labels = data.labels.map((label: any, index: number) => ({
        id: index + 1,
        name: label.name || '',
        description: label.description || '',
      }));
      nextLabelId = labels.length + 1;
    }

    loaded = true;
    loading = false;
  });

  function onEnableTranscriptChanged() {
    if (!aiSettings.enableTranscription) {
      aiSettings.enableSentimentAnalysis = false;
      aiSettings.enableSummary = false;
      aiSettings.enableLabels = false;
    }
  }

  function onEnableLabelsChanged() {
    if (!aiSettings.enableLabels) {
      // Reset labels when disabled
      labels = [{ id: nextLabelId++, name: '', description: '' }];
    }
  }

  function addLabel() {
    labels = [...labels, { id: nextLabelId++, name: '', description: '' }];
  }

  function removeLabel(id: number) {
    if (labels.length > 1) {
      labels = labels.filter((label) => label.id !== id);
    } else {
      toast.error('At least one label field is required');
    }
  }

  let saveProgress = $state(false);
  async function onSave() {
    saveProgress = true;

    // Filter out empty labels
    const validLabels = labels
      .filter((label) => label.name.trim() !== '' || label.description.trim() !== '')
      .map(({ name, description }) => ({ name: name.trim(), description: description.trim() }));

    const result = await postJson(`/api/v2/${page.params.subdomain}/settings/ai-analysis`, {
      enableTranscription: aiSettings.enableTranscription,
      enableSentimentAnalysis: aiSettings.enableSentimentAnalysis,
      enableSummary: aiSettings.enableSummary,
      enableLabels: aiSettings.enableLabels,
      labels: aiSettings.enableLabels ? validLabels : [],
      enableDailySummary: aiSettings.enableDailySummary,
      dailySummaryTimeZone: aiSettings.dailySummaryTimeZone,
      dailySummaryTime: aiSettings.dailySummaryTime,
    });
    if (!result.ok) {
      toast.error('Error occurred while saving settings. Please try again later.');
      saveProgress = false;
      return;
    }

    toast.success('Updated successfully');
    saveProgress = false;
  }
</script>

{#snippet needsTranscription()}
  {#if !aiSettings.enableTranscription}
    <Hint>Needs transcription: turn it on above first.</Hint>
  {/if}
{/snippet}

{#if loading}
  <SkeletonLoadingList className="my-4" />
{:else if !loaded}
  <Card className="mt-4">
    <p class="text-sm text-gray-700 dark:text-gray-300">
      The AI settings couldn't be loaded. Refresh the page to try again.
    </p>
  </Card>
{:else}
  <form
    class="mt-4 max-w-4xl space-y-4"
    onsubmit={(event) => {
      event.preventDefault();
      onSave();
    }}
  >
    <FormSection
      title="Transcription and search"
      description="Each call is transcribed, and calls can be searched by what was said. Turn it off and calls are kept as recordings only."
    >
      {#snippet aside()}
        <Toggle
          id="enableTranscription"
          label="Enable Transcription & Search"
          bind:checked={aiSettings.enableTranscription}
          onchange={onEnableTranscriptChanged}
        />
      {/snippet}
    </FormSection>

    <FormSection
      title="Sentiment analysis"
      description="Says how each side of a call felt, from the transcript."
    >
      {#snippet aside()}
        <Toggle
          id="enableSentimentAnalysis"
          label="Enable Sentiment Analysis"
          bind:checked={aiSettings.enableSentimentAnalysis}
          disabled={!aiSettings.enableTranscription}
        />
      {/snippet}
      {@render needsTranscription()}
    </FormSection>

    <FormSection title="Summary" description="A short AI summary of each call.">
      {#snippet aside()}
        <Toggle
          id="enableSummary"
          label="Enable Summary"
          bind:checked={aiSettings.enableSummary}
          disabled={!aiSettings.enableTranscription}
        />
      {/snippet}
      {@render needsTranscription()}
    </FormSection>

    <FormSection
      title="Daily summary"
      description="Once a day, an AI summary of the previous 24 hours of calls, shown on the Daily Summary page."
    >
      {#snippet aside()}
        <Toggle
          id="enableDailySummary"
          label="Enable Daily Summary"
          bind:checked={aiSettings.enableDailySummary}
          disabled={!aiSettings.enableTranscription}
        />
      {/snippet}

      {#if aiSettings.enableDailySummary}
        <div class="grid gap-4 md:grid-cols-2">
          <Field for="timezone-select" label="Timezone">
            <Select id="timezone-select" bind:value={aiSettings.dailySummaryTimeZone}>
              {#each timezones as timezone (timezone)}
                <option value={timezone}>{timezone}</option>
              {/each}
            </Select>
          </Field>
          <Field
            for="time-input"
            label="Time"
            hint="The summary is made at this time each day, in the timezone on the left."
          >
            <Input id="time-input" type="time" bind:value={aiSettings.dailySummaryTime} />
          </Field>
        </div>
      {/if}
      {@render needsTranscription()}
    </FormSection>

    <FormSection
      title="Call labels"
      description="Each call is tagged with the labels below that fit it."
    >
      {#snippet aside()}
        <Toggle
          id="enableLabels"
          label="Enable Labels"
          bind:checked={aiSettings.enableLabels}
          onchange={onEnableLabelsChanged}
          disabled={!aiSettings.enableTranscription}
        />
      {/snippet}

      {#if aiSettings.enableLabels}
        <div class="space-y-3">
          <div
            class="hidden grid-cols-[12rem_minmax(0,1fr)_2.5rem] gap-3 text-xs font-medium text-gray-500 sm:grid dark:text-gray-400"
          >
            <span>Name</span>
            <span>What it means</span>
          </div>
          {#each labels as label, index (label.id)}
            <div class="grid gap-2 sm:grid-cols-[12rem_minmax(0,1fr)_2.5rem] sm:gap-3">
              <Input
                id="label-name-{label.id}"
                type="text"
                aria-label="Label {index + 1} name"
                bind:value={label.name}
                placeholder="Label Name"
              />
              <Input
                id="label-desc-{label.id}"
                type="text"
                aria-label="Label {index + 1} description"
                bind:value={label.description}
                placeholder="Brief description"
              />
              {#if labels.length > 1}
                <RemoveButton
                  label="Remove label {index + 1}"
                  onclick={() => removeLabel(label.id)}
                />
              {/if}
            </div>
          {/each}
        </div>
        <button
          type="button"
          onclick={addLabel}
          class="text-sm font-medium text-blue-600 hover:underline dark:text-blue-500"
          title="Add new label"
        >
          + Add label
        </button>
        <!-- Unformatted: wrapping puts a space before the colon. -->
        <!-- prettier-ignore -->
        <Hint>
          For example: <span class="font-medium">billing</span>, meaning questions about invoices or payments.
        </Hint>
      {/if}
      {@render needsTranscription()}
    </FormSection>

    <FormActions>
      <Button type="submit" progress={saveProgress}>Save</Button>
    </FormActions>
  </form>
{/if}
