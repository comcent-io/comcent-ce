<script lang="ts">
  import CloseIcon from '$lib/components/Icons/CloseIcon.svelte';

  // The × that removes one row of a list (a queue, an MCP server, a label).
  // `label` says what it removes, for screen readers and the tooltip.
  interface Props {
    label: string;
    onclick?: () => void;
  }

  let { label, onclick }: Props = $props();
</script>

<button
  type="button"
  {onclick}
  aria-label={label}
  title={label}
  class="inline-flex h-9 w-9 shrink-0 items-center justify-center rounded-lg text-gray-400 hover:bg-red-50 hover:text-red-600 focus:outline-none focus:ring-2 focus:ring-red-500 dark:hover:bg-gray-700 dark:hover:text-red-400"
>
  <CloseIcon />
</button>
