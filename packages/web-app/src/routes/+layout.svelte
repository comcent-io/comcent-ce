<script lang="ts">
  import '../tailwind.css';
  import '../app.css';

  import NProgress from 'nprogress';
  import 'nprogress/nprogress.css';
  import type { Snippet } from 'svelte';
  import { navigating } from '$app/state';

  let { children }: { children?: Snippet } = $props();

  NProgress.configure({
    minimum: 0.16,
  });

  // The progress bar runs for as long as a navigation is in flight.
  $effect(() => {
    if (navigating.to) {
      NProgress.start();
    } else {
      NProgress.done();
    }
  });
</script>

<div class="bg-gray-50 dark:bg-gray-900" style="min-height: 100%;">
  {@render children?.()}
</div>
