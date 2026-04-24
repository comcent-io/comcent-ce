<script>
  import '../tailwind.css';
  import '../app.css';

  import NProgress from 'nprogress';
  import { navigating } from '$app/stores';

  import 'nprogress/nprogress.css';
  import { browser } from '$app/environment';
  import { onMount } from 'svelte';

  NProgress.configure({
    minimum: 0.16,
  });

  onMount(() => {
    if (browser) {
      navigating.subscribe((value) => {
        if (value) {
          NProgress.start();
        }
        if (!value) {
          NProgress.done();
        }
      });
    }
  });
</script>

<div class="bg-gray-50 dark:bg-gray-900" style="min-height: 100%;">
  <slot />
</div>
