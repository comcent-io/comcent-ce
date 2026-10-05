<script lang="ts">
  import type { Snippet } from 'svelte';

  // A field on the account pages (sign-in style, outside an org): the label,
  // the control (children), and an error or a hint under it. The hint can
  // be plain text or a snippet when it needs markup.
  interface Props {
    for: string;
    label: string;
    hint?: string | Snippet;
    hintId?: string;
    error?: string;
    children?: Snippet;
  }

  let { for: id, label, hint, hintId, error, children }: Props = $props();
</script>

<div>
  <label for={id} class="mb-2 block text-sm font-medium text-slate-700 dark:text-slate-200">
    {label}
  </label>
  {@render children?.()}
  {#if error}
    <p class="mt-2 text-xs text-red-600 dark:text-red-400">{error}</p>
  {:else if hint}
    <p id={hintId} class="mt-2 text-xs text-slate-500 dark:text-slate-400">
      {#if typeof hint === 'string'}{hint}{:else}{@render hint()}{/if}
    </p>
  {/if}
</div>
