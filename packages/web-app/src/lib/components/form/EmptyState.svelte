<script lang="ts">
  import type { Snippet } from 'svelte';

  // What a list shows when it has nothing in it: what would be here, and
  // how to add the first one.
  interface Props {
    title: string;
    description?: string;
    action?: Snippet;
  }

  let { title, description, action }: Props = $props();
</script>

<div
  class="rounded-lg border-2 border-dashed border-gray-200 px-6 py-10 text-center dark:border-gray-700"
>
  <p class="text-base font-semibold text-gray-900 dark:text-white">{title}</p>
  {#if description}
    <p class="mx-auto mt-1 max-w-md text-sm text-gray-500 dark:text-gray-400">{description}</p>
  {/if}
  {#if action}
    <div class="mt-5 flex justify-center">{@render action()}</div>
  {/if}
</div>
