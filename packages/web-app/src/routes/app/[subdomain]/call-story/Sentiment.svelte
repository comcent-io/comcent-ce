<script lang="ts">
  import { onMount } from 'svelte';
  import { page } from '$app/state';
  import Pill, { type PillTone } from '$lib/components/Pill.svelte';
  import EmptyState from '$lib/components/form/EmptyState.svelte';
  import Spinner from '$lib/components/Icons/Spinner.svelte';
  import PartyAvatar from '$lib/components/PartyAvatar.svelte';
  import { isPhoneParty, partyName } from '$lib/party';

  interface Props {
    callStoryId: string;
  }

  let { callStoryId }: Props = $props();

  type SentimentType = 'positive' | 'neutral' | 'negative';

  const looks: Record<SentimentType, { emoji: string; label: string; tone: PillTone }> = {
    positive: { emoji: '😊', label: 'Positive', tone: 'green' },
    neutral: { emoji: '😐', label: 'Neutral', tone: 'gray' },
    negative: { emoji: '😞', label: 'Negative', tone: 'red' },
  };

  let sentimentData: { sentiment: Record<string, SentimentType> } | null = $state(null);

  async function fetchSentiment(callStoryId: string) {
    const response = await fetch(
      `/api/v2/${page.params.subdomain}/call-story/${callStoryId}/sentiment`,
    );
    if (!response.ok) throw new Error((await response.json()).error ?? response.statusText);
    return response.json();
  }

  onMount(async () => {
    sentimentData = await fetchSentiment(callStoryId);
  });
</script>

{#if !sentimentData}
  <div class="flex justify-center py-10"><Spinner /></div>
{:else if Object.keys(sentimentData.sentiment).length === 0}
  <EmptyState title="No sentiment" description="This call has no sentiment analysis." />
{:else}
  <p class="text-sm text-gray-500 dark:text-gray-400">How each person on the call came across.</p>
  <ul
    class="divide-y divide-gray-200 rounded-lg border border-gray-200 dark:divide-gray-700 dark:border-gray-700"
  >
    {#each Object.entries(sentimentData.sentiment) as [party, sentiment] (party)}
      {@const look = looks[sentiment]}
      <li class="flex items-center gap-3 px-4 py-3">
        <PartyAvatar {party} />
        <div class="min-w-0 flex-1">
          <p class="truncate text-sm font-medium text-gray-900 dark:text-white">
            {partyName(party)}
          </p>
          <p class="text-xs text-gray-500 dark:text-gray-400">
            {isPhoneParty(party) ? 'Customer' : 'Agent'}
          </p>
        </div>
        {#if look}
          <Pill tone={look.tone}>
            <span aria-hidden="true">{look.emoji}</span>
            {look.label}
          </Pill>
        {:else}
          <Pill>Not analysed</Pill>
        {/if}
      </li>
    {/each}
  </ul>
{/if}
