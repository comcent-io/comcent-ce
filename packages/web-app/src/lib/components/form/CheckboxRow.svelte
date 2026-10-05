<script lang="ts">
  import type { Snippet } from 'svelte';
  import Checkbox from './Checkbox.svelte';

  // A choice in a list: the box first, then its name and what it does.
  // Children render under it while it is checked (e.g. a queue picker).
  interface Props {
    id: string;
    label: string;
    description?: string;
    checked?: boolean;
    disabled?: boolean;
    badge?: string;
    children?: Snippet;
  }

  let {
    id,
    label,
    description,
    checked = $bindable(false),
    disabled = false,
    badge,
    children,
  }: Props = $props();
</script>

<div
  class="rounded-lg border border-gray-200 p-3 dark:border-gray-700 {disabled ? 'opacity-60' : ''}"
>
  <label for={id} class="flex items-start gap-3 {disabled ? '' : 'cursor-pointer'}">
    <Checkbox {id} class="mt-0.5" bind:checked {disabled} />
    <span>
      <span class="text-sm font-medium text-gray-900 dark:text-white">{label}</span>
      {#if badge}
        <span
          class="ml-2 rounded-full bg-gray-100 px-2 py-0.5 text-xs text-gray-600 dark:bg-gray-700 dark:text-gray-300"
        >
          {badge}
        </span>
      {/if}
      {#if description}
        <span class="mt-0.5 block text-xs text-gray-500 dark:text-gray-400">{description}</span>
      {/if}
    </span>
  </label>
  {#if checked && children}
    <div class="mt-3 pl-7">{@render children()}</div>
  {/if}
</div>
