<script lang="ts">
  import { onDestroy, onMount } from 'svelte';

  let displayTime = '0:00';
  let timer: any;
  export let startTime: Date;
  onMount(() => {
    timer = setInterval(() => {
      const now = new Date().getTime();
      const distance = now - startTime.getTime();
      const minutes = Math.floor((distance % (1000 * 60 * 60)) / (1000 * 60));
      const seconds = Math.floor((distance % (1000 * 60)) / 1000);
      displayTime = `${minutes}:${seconds < 10 ? '0' : ''}${seconds}`;
    }, 1000);
  });

  onDestroy(() => {
    clearInterval(timer);
  });
</script>

<span class="text-gray-500 dark:text-gray-400 {$$restProps.class}">
  {displayTime}
</span>
