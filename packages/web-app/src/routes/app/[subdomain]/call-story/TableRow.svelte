<script lang="ts">
  import { formatDuration, formatTableDateTime } from '$lib/format';
  import { partyName } from '$lib/party';
  import Pill from '$lib/components/Pill.svelte';
  import SecondaryButton from '$lib/components/form/SecondaryButton.svelte';
  import type { CallStoryFromServer } from '$lib/types/CallStoryFromServer.js';
  import CallDetails from './CallDetails.svelte';

  interface Props {
    callStory: CallStoryFromServer;
  }

  let { callStory }: Props = $props();

  let open = $state(false);
  let labels = $derived(callStory.labels ?? []);
</script>

<!-- The whole row opens the call; keyboard users have the View button. -->
<!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_noninteractive_element_interactions -->
<tr
  class="cursor-pointer border-b border-gray-200 bg-white last:border-0 hover:bg-gray-50 dark:border-gray-700 dark:bg-gray-800 dark:hover:bg-gray-700/50"
  onclick={() => (open = true)}
>
  <td class="whitespace-nowrap px-6 py-4 text-gray-900 dark:text-white">
    {formatTableDateTime(callStory.startAt)}
  </td>
  <td class="px-6 py-4">
    <Pill tone={callStory.direction === 'inbound' ? 'cyan' : 'blue'}>
      {callStory.direction === 'inbound' ? 'Inbound' : 'Outbound'}
    </Pill>
  </td>
  <td class="px-6 py-4 font-medium text-gray-900 dark:text-white">{partyName(callStory.caller)}</td>
  <td class="px-6 py-4">{partyName(callStory.callee)}</td>
  <td class="whitespace-nowrap px-6 py-4 tabular-nums">
    {formatDuration(callStory.startAt, callStory.endAt, '-')}
  </td>
  <td class="px-6 py-4">
    <div class="flex flex-wrap gap-1.5">
      {#each labels as label (label)}
        <Pill>{label}</Pill>
      {/each}
    </div>
  </td>
  <td class="px-6 py-4 text-right">
    <SecondaryButton
      size="sm"
      onclick={(e: MouseEvent) => {
        e.stopPropagation();
        open = true;
      }}
    >
      View
    </SecondaryButton>
  </td>
</tr>

{#if open}
  <CallDetails {callStory} onClose={() => (open = false)} />
{/if}
