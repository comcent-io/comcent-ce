<script lang="ts">
  import type { Snippet } from 'svelte';

  // A failure to show above an account page's form.
  let { children }: { children?: Snippet } = $props();
</script>

<div
  class="rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700 dark:border-red-900 dark:bg-red-950 dark:text-red-300"
  role="alert"
>
  {@render children?.()}
</div>
