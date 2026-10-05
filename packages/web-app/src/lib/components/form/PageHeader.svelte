<script lang="ts">
  import type { Snippet } from 'svelte';

  // The top of a page in the app: an optional way back, the title, one line
  // saying what the page is for, and actions on the right.
  interface Props {
    title: string;
    description?: string;
    backHref?: string;
    backLabel?: string;
    actions?: Snippet;
  }

  let { title, description, backHref, backLabel = 'Back', actions }: Props = $props();
</script>

<div class="mb-6 mt-4">
  {#if backHref}
    <a
      href={backHref}
      class="text-sm text-gray-500 hover:text-gray-900 dark:text-gray-400 dark:hover:text-white"
    >
      ← {backLabel}
    </a>
  {/if}
  <div class="mt-2 flex flex-wrap items-start justify-between gap-4">
    <div class="max-w-3xl">
      <h3 class="text-3xl font-bold text-gray-900 dark:text-white">{title}</h3>
      {#if description}
        <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">{description}</p>
      {/if}
    </div>
    {#if actions}
      <div class="flex shrink-0 items-center gap-3">{@render actions()}</div>
    {/if}
  </div>
</div>
