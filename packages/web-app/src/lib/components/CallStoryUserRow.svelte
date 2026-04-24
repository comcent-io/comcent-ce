<script lang="ts">
  import _ from 'lodash';
  import Span from '$lib/components/Span.svelte';
  import CallPlayer from '$lib/components/CallPlayer.svelte';

  export let userName;
  export let spans;
</script>

<div class="text-gray-500 dark:text-gray-400 break-words">{userName}</div>
<div class="isolate">
  <div class="relative flex items-center" style="height: 30px">
    {#each _.sortBy( spans.filter((s) => s.type !== 'RECORDING'), 'relativeStartAt', ) as span}
      <Span {span} />
    {/each}
  </div>

  {#each spans.filter((s) => s.type === 'RECORDING' && s.metadata?.direction === 'both') as callSpan}
    <CallPlayer {callSpan} />
  {/each}
</div>
