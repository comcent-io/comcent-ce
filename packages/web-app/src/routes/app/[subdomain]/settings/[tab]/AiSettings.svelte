<script lang="ts">
  import Button from '$lib/components/Button.svelte';
  import { page } from '$app/stores';
  import { getJson, postJson } from '$lib/http';
  import toast from 'svelte-french-toast';
  import { onMount } from 'svelte';
  import SkeletonLoadingList from '$lib/components/SkeletonLoadingList.svelte';
  import H3 from '$lib/components/html/H3.svelte';
  import moment from 'moment-timezone';

  let aiSettings = {
    enableTranscription: false,
    enableSentimentAnalysis: false,
    enableSummary: false,
    enableLabels: false,
    enableDailySummary: false,
    dailySummaryTimeZone: 'UTC',
    dailySummaryTime: '09:00',
  };

  let labels = [{ id: 1, name: '', description: '' }];
  let nextLabelId = 2;

  let loading = false;
  let loaded = false;

  // All available timezones for the dropdown
  const timezones = moment.tz.names();
  onMount(async () => {
    loading = true;
    const result = await getJson<any>(`/api/v2/${$page.params.subdomain}/settings/ai-analysis`);
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

    console.log('response', data);
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

  let saveProgress = false;
  async function onSave() {
    saveProgress = true;

    // Filter out empty labels
    const validLabels = labels
      .filter((label) => label.name.trim() !== '' || label.description.trim() !== '')
      .map(({ name, description }) => ({ name: name.trim(), description: description.trim() }));

    const result = await postJson(`/api/v2/${$page.params.subdomain}/settings/ai-analysis`, {
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

{#if loading}
  <SkeletonLoadingList className="my-4" />
{:else if !loaded}
  <H3 className="mt-4">Some thing went wrong</H3>
{:else}
  <div class="my-4">
    <ul
      class="block p-6 bg-white border border-gray-200 rounded-lg shadow dark:bg-gray-800 dark:border-gray-700"
    >
      <li>
        <label class="inline-flex items-center mb-5 cursor-pointer">
          <input
            type="checkbox"
            class="sr-only peer"
            bind:checked={aiSettings.enableTranscription}
            on:change={onEnableTranscriptChanged}
          />
          <div
            class="relative w-11 h-6 bg-gray-200 peer-focus:outline-none peer-focus:ring-4 peer-focus:ring-blue-300 dark:peer-focus:ring-blue-800 rounded-full peer dark:bg-gray-700 peer-checked:after:translate-x-full rtl:peer-checked:after:-translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:start-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:w-5 after:h-5 after:transition-all dark:border-gray-600 peer-checked:bg-blue-600"
          ></div>
          <span class="ms-3 text-sm font-medium text-gray-900 dark:text-gray-300">
            Enable Transcription & Search
          </span>
        </label>
      </li>
      <li>
        <ul
          class="block p-6 bg-white border border-gray-200 rounded-lg shadow dark:bg-gray-800 dark:border-gray-700"
        >
          <li>
            <label class="inline-flex items-center mb-5 cursor-pointer">
              <input
                name="enableSentimentAnalysis"
                type="checkbox"
                bind:checked={aiSettings.enableSentimentAnalysis}
                class="sr-only peer"
                disabled={!aiSettings.enableTranscription}
              />
              <div
                class="relative w-11 h-6 bg-gray-200 peer-focus:outline-none peer-focus:ring-4 peer-focus:ring-blue-300 dark:peer-focus:ring-blue-800 rounded-full peer dark:bg-gray-700 peer-checked:after:translate-x-full rtl:peer-checked:after:-translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:start-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:w-5 after:h-5 after:transition-all dark:border-gray-600 peer-checked:bg-blue-600"
              ></div>
              <span class="ms-3 text-sm font-medium text-gray-900 dark:text-gray-300">
                Enable Sentiment Analysis
              </span>
            </label>
          </li>

          <li>
            <label class="inline-flex items-center mb-5 cursor-pointer">
              <input
                name="enableSummary"
                type="checkbox"
                bind:checked={aiSettings.enableSummary}
                class="sr-only peer"
                disabled={!aiSettings.enableTranscription}
              />
              <div
                class="relative w-11 h-6 bg-gray-200 peer-focus:outline-none peer-focus:ring-4 peer-focus:ring-blue-300 dark:peer-focus:ring-blue-800 rounded-full peer dark:bg-gray-700 peer-checked:after:translate-x-full rtl:peer-checked:after:-translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:start-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:w-5 after:h-5 after:transition-all dark:border-gray-600 peer-checked:bg-blue-600"
              ></div>
              <span class="ms-3 text-sm font-medium text-gray-900 dark:text-gray-300">
                Enable Summary
              </span>
            </label>
          </li>

          <li class="mt-2">
            <label class="inline-flex items-center mb-5 cursor-pointer">
              <input
                name="enableDailySummary"
                type="checkbox"
                bind:checked={aiSettings.enableDailySummary}
                class="sr-only peer"
                disabled={!aiSettings.enableTranscription}
              />
              <div
                class="relative w-11 h-6 bg-gray-200 peer-focus:outline-none peer-focus:ring-4 peer-focus:ring-blue-300 dark:peer-focus:ring-blue-800 rounded-full peer dark:bg-gray-700 peer-checked:after:translate-x-full rtl:peer-checked:after:-translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:start-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:w-5 after:h-5 after:transition-all dark:border-gray-600 peer-checked:bg-blue-600"
              ></div>
              <span class="ms-3 text-sm font-medium text-gray-900 dark:text-gray-300">
                Enable Daily Summary
              </span>
            </label>
          </li>

          {#if aiSettings.enableDailySummary}
            <li class="ml-6 mt-4">
              <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div>
                  <label
                    for="timezone-select"
                    class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2"
                  >
                    Timezone
                  </label>
                  <select
                    id="timezone-select"
                    bind:value={aiSettings.dailySummaryTimeZone}
                    class="w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-blue-500 focus:border-blue-500 dark:bg-gray-700 dark:border-gray-600 dark:text-white"
                  >
                    {#each timezones as timezone}
                      <option value={timezone}>{timezone}</option>
                    {/each}
                  </select>
                </div>
                <div>
                  <label
                    for="time-input"
                    class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2"
                  >
                    Time
                  </label>
                  <input
                    id="time-input"
                    type="time"
                    bind:value={aiSettings.dailySummaryTime}
                    class="w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-blue-500 focus:border-blue-500 dark:bg-gray-700 dark:border-gray-600 dark:text-white"
                  />
                </div>
              </div>
            </li>
          {/if}

          <li class="mt-4">
            <label class="inline-flex items-center mb-5 cursor-pointer">
              <input
                name="enableLabels"
                type="checkbox"
                bind:checked={aiSettings.enableLabels}
                on:change={onEnableLabelsChanged}
                class="sr-only peer"
                disabled={!aiSettings.enableTranscription}
              />
              <div
                class="relative w-11 h-6 bg-gray-200 peer-focus:outline-none peer-focus:ring-4 peer-focus:ring-blue-300 dark:peer-focus:ring-blue-800 rounded-full peer dark:bg-gray-700 peer-checked:after:translate-x-full rtl:peer-checked:after:-translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:start-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:w-5 after:h-5 after:transition-all dark:border-gray-600 peer-checked:bg-blue-600"
              ></div>
              <span class="ms-3 text-sm font-medium text-gray-900 dark:text-gray-300">
                Enable Labels
              </span>
            </label>

            {#if aiSettings.enableLabels}
              <div class="mt-4 ml-6 space-y-3 transition-all duration-300">
                <div class="mb-3">
                  <p class="text-sm text-gray-600 dark:text-gray-400">
                    Define custom labels to categorize and organize your data
                  </p>
                </div>

                {#each labels as label, index (label.id)}
                  <div
                    class="flex items-center gap-3 p-3 bg-gray-50 dark:bg-gray-700 rounded-lg border border-gray-200 dark:border-gray-600 transition-all duration-200"
                  >
                    <div class="w-48">
                      <input
                        id="label-name-{label.id}"
                        type="text"
                        bind:value={label.name}
                        placeholder="Label Name"
                        class="w-full px-3 py-2 text-sm border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent dark:bg-gray-600 dark:border-gray-500 dark:text-white dark:placeholder-gray-400"
                      />
                    </div>

                    <div class="flex-1">
                      <input
                        id="label-desc-{label.id}"
                        type="text"
                        bind:value={label.description}
                        placeholder="Brief description"
                        class="w-full px-3 py-2 text-sm border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent dark:bg-gray-600 dark:border-gray-500 dark:text-white dark:placeholder-gray-400"
                      />
                    </div>

                    <div class="flex gap-2">
                      {#if index === labels.length - 1}
                        <button
                          type="button"
                          on:click={addLabel}
                          class="flex items-center justify-center w-10 h-10 text-white bg-blue-600 hover:bg-blue-700 rounded-lg transition-colors duration-200 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 dark:focus:ring-offset-gray-800"
                          title="Add new label"
                        >
                          <svg
                            class="w-5 h-5"
                            fill="none"
                            stroke="currentColor"
                            viewBox="0 0 24 24"
                          >
                            <path
                              stroke-linecap="round"
                              stroke-linejoin="round"
                              stroke-width="2"
                              d="M12 4v16m8-8H4"
                            />
                          </svg>
                        </button>
                      {/if}

                      {#if labels.length > 1}
                        <button
                          type="button"
                          on:click={() => removeLabel(label.id)}
                          class="flex items-center justify-center w-10 h-10 text-white bg-red-600 hover:bg-red-700 rounded-lg transition-colors duration-200 focus:outline-none focus:ring-2 focus:ring-red-500 focus:ring-offset-2 dark:focus:ring-offset-gray-800"
                          title="Remove this label"
                        >
                          <svg
                            class="w-5 h-5"
                            fill="none"
                            stroke="currentColor"
                            viewBox="0 0 24 24"
                          >
                            <path
                              stroke-linecap="round"
                              stroke-linejoin="round"
                              stroke-width="2"
                              d="M6 18L18 6M6 6l12 12"
                            />
                          </svg>
                        </button>
                      {/if}
                    </div>
                  </div>
                {/each}
              </div>
            {/if}
          </li>
        </ul>
      </li>
      <li>
        <Button on:click={onSave} progress={saveProgress} className="mt-4">Save</Button>
      </li>
    </ul>
  </div>
{/if}
