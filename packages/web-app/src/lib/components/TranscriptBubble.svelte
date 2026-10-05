<script lang="ts">
  import { formatTime } from '$lib/format';
  import PartyAvatar from './PartyAvatar.svelte';

  // One turn of a call transcript. A phone number is the customer, shown on
  // the left; members are shown on the right.
  interface Props {
    name?: string;
    message?: string;
    /** When the message began, in Unix seconds; 0 when unknown. */
    start?: number;
  }

  let { name = '', message = '', start = 0 }: Props = $props();

  let customer = $derived(name.startsWith('+'));
  let time = $derived(start ? formatTime(start * 1000) : '');
</script>

<div class="flex items-end gap-2.5 {customer ? 'flex-row' : 'flex-row-reverse'}">
  <PartyAvatar party={name} />
  <div
    class="max-w-[75%] rounded-2xl px-4 py-2.5 {customer
      ? 'rounded-bl-sm bg-slate-100 dark:bg-slate-700'
      : 'rounded-br-sm bg-cyan-50 dark:bg-cyan-950'}"
  >
    <div class="flex items-baseline gap-2 {customer ? '' : 'flex-row-reverse'}">
      <span class="text-xs font-semibold text-gray-900 dark:text-white">{name}</span>
      {#if time}
        <span class="text-xs text-gray-500 dark:text-gray-400">{time}</span>
      {/if}
    </div>
    <p class="mt-1 text-sm leading-relaxed text-gray-800 dark:text-gray-100">{message}</p>
  </div>
</div>
