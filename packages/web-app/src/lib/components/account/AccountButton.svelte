<script lang="ts">
  import type { Snippet } from 'svelte';
  import type { HTMLButtonAttributes } from 'svelte/elements';
  import Spinner from '$lib/components/Icons/Spinner.svelte';

  // The main action of an account page, full width, with a spinner while
  // `progress`.
  interface Props extends HTMLButtonAttributes {
    progress?: boolean;
    children?: Snippet;
  }

  let { progress = false, type = 'submit', class: extra = '', children, ...rest }: Props = $props();
</script>

<button
  {...rest}
  {type}
  disabled={progress || rest.disabled}
  class="relative w-full rounded-xl bg-slate-900 px-4 py-3 text-sm font-semibold text-white hover:bg-slate-700 disabled:opacity-70 dark:bg-cyan-500 dark:text-slate-950 dark:hover:bg-cyan-400 {extra}"
>
  <span class={progress ? 'opacity-30' : ''}>{@render children?.()}</span>
  {#if progress}
    <span class="absolute left-1/2 top-1/2 -translate-x-1/2 -translate-y-1/2"><Spinner /></span>
  {/if}
</button>
