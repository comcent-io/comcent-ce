<script lang="ts">
  import type { Snippet } from 'svelte';
  import Card from '$lib/components/Card.svelte';

  // One card of a form or settings page: a title, one line saying what the
  // section is for, an optional control in the header (e.g. a toggle), and
  // its fields.
  interface Props {
    title: string;
    description?: string;
    aside?: Snippet;
    children?: Snippet;
    className?: string;
  }

  let { title, description, aside, children, className = '' }: Props = $props();
</script>

<Card {className}>
  <div class="flex items-start justify-between gap-4">
    <div>
      <h4 class="text-lg font-semibold text-gray-900 dark:text-white">{title}</h4>
      {#if description}
        <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">{description}</p>
      {/if}
    </div>
    {#if aside}
      <div class="shrink-0">{@render aside()}</div>
    {/if}
  </div>
  {#if children}
    <!-- empty:hidden: no gap when all the content is conditional and off. -->
    <div class="mt-5 space-y-5 empty:hidden">{@render children()}</div>
  {/if}
</Card>
