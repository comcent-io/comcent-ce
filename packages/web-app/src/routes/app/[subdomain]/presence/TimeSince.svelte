<script lang="ts">
  import { onDestroy, onMount } from 'svelte';
  import moment from 'moment-timezone';

  export let startAt: Date;

  let timer: any = null;
  let renderedText = '';

  onMount(() => {
    timer = setInterval(() => {
      if (startAt) {
        renderedText = moment(startAt).fromNow();
      } else {
        renderedText = '';
      }
    }, 1000);
  });

  onDestroy(() => {
    if (timer) {
      clearInterval(timer);
    }
  });
</script>

{#if renderedText}
  <span class="text-gray-500 dark:text-gray-400">
    since {renderedText}
  </span>
{/if}
