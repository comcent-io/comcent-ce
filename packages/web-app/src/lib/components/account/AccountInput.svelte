<script lang="ts">
  import type { HTMLInputAttributes } from 'svelte/elements';

  // The text input of the account pages. Binds its value; every other
  // attribute passes through. `invalid` marks it red.
  interface Props extends HTMLInputAttributes {
    value?: HTMLInputAttributes['value'];
    invalid?: boolean;
  }

  let { value = $bindable(), invalid = false, class: extra = '', ...rest }: Props = $props();
</script>

<input
  {...rest}
  bind:value
  aria-invalid={invalid || undefined}
  class="block w-full rounded-xl border border-slate-300 bg-white px-4 py-3 text-sm text-slate-900 placeholder-slate-400 focus:border-cyan-500 focus:outline-none focus:ring-1 focus:ring-cyan-500 aria-[invalid=true]:border-red-400 dark:border-slate-600 dark:bg-slate-900 dark:text-white dark:aria-[invalid=true]:border-red-500 {extra}"
/>
