<script lang="ts">
  import { page } from '$app/stores';
  import { onMount } from 'svelte';
  import type { DailySummary, SentimentCounts } from './components/types';
  import DailySummaryList from './components/DailySummaryList.svelte';
  import DailySummaryDetail from './components/DailySummaryDetail.svelte';

  let dailySummaries: DailySummary[] = [];
  let selectedDate: string | null = null;
  let loading = false;
  let loadingDetails = false;
  let executiveSummary: string = '';
  let sentimentCounts: SentimentCounts | null = null;
  let totalPromisesCreated: number = 0;
  let totalPromisesClosed: number = 0;

  const subdomain = $page.params.subdomain;

  async function fetchDailySummaries() {
    loading = true;
    try {
      const response = await fetch(`/api/v2/${subdomain}/daily-summaries`);
      if (!response.ok) throw new Error((await response.json()).error ?? response.statusText);
      const data = await response.json();
      dailySummaries = data.dailySummaries || [];
    } catch (error: any) {
      console.error('Error fetching daily summaries:', error);
    } finally {
      loading = false;
    }
  }

  async function fetchSummaryDetails(date: string) {
    loadingDetails = true;
    selectedDate = date;
    executiveSummary = '';
    sentimentCounts = null;
    totalPromisesCreated = 0;
    totalPromisesClosed = 0;

    try {
      // Format date as YYYY-MM-DD
      const dateStr = date.split('T')[0];

      // Fetch daily summary
      const summaryResponse = await fetch(`/api/v2/${subdomain}/daily-summaries`);
      if (!summaryResponse.ok)
        throw new Error((await summaryResponse.json()).error ?? summaryResponse.statusText);
      const summaryData = await summaryResponse.json();
      const summary = summaryData.dailySummaries?.find(
        (s: DailySummary) => s.date.split('T')[0] === dateStr,
      );
      if (summary) {
        executiveSummary = summary.executiveSummary || '';
        totalPromisesCreated = summary.totalPromisesCreated || 0;
        totalPromisesClosed = summary.totalPromisesClosed || 0;
      }

      // Fetch sentiment counts
      try {
        const sentimentResponse = await fetch(
          `/api/v2/${subdomain}/daily-summaries/sentiment-counts?date=${dateStr}`,
        );
        if (!sentimentResponse.ok)
          throw new Error((await sentimentResponse.json()).error ?? sentimentResponse.statusText);
        const sentimentData = await sentimentResponse.json();
        sentimentCounts = sentimentData.sentimentCounts;
      } catch (error) {
        console.error('Error fetching sentiment counts:', error);
        sentimentCounts = { positive: 0, negative: 0, neutral: 0 };
      }
    } catch (error: any) {
      console.error('Error fetching summary details:', error);
    } finally {
      loadingDetails = false;
    }
  }

  function handleBack() {
    selectedDate = null;
  }

  onMount(() => {
    fetchDailySummaries();
  });
</script>

<div class="p-6 dark:bg-gray-900">
  {#if !selectedDate}
    <DailySummaryList {dailySummaries} {loading} onSelectSummary={fetchSummaryDetails} />
  {:else}
    <DailySummaryDetail
      {selectedDate}
      {loadingDetails}
      {executiveSummary}
      {sentimentCounts}
      {totalPromisesCreated}
      {totalPromisesClosed}
      onBack={handleBack}
    />
  {/if}
</div>
