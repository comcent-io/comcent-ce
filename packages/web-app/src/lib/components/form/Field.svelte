<script lang="ts">
  import type { Snippet } from 'svelte';
  import Hint from './Hint.svelte';
  import Label from './Label.svelte';

  // A label above its control, with a hint or an error below. The control
  // (Input, Textarea, Select ...) is the child; give it the same `id` as
  // `for` here.
  interface Props {
    for: string;
    label: string;
    hint?: string;
    error?: string;
    optional?: boolean;
    children?: Snippet;
  }

  let { for: id, label, hint, error, optional = false, children }: Props = $props();
</script>

<div>
  <Label for={id}>
    {label}
    {#if optional}
      <span class="font-normal text-gray-500 dark:text-gray-400">(optional)</span>
    {/if}
  </Label>
  {@render children?.()}
  {#if error}
    <Hint error>{error}</Hint>
  {:else if hint}
    <Hint>{hint}</Hint>
  {/if}
</div>
