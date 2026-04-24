<script lang="ts">
  import { createEventDispatcher } from 'svelte';
  import type { SelectedOutlet } from '../SelectedOutlet';
  import type { FlowNode } from '../nodes/FlowNode';
  const dispatch = createEventDispatcher();

  export let selectedOutlet: SelectedOutlet | null;
  export let node: FlowNode;
  export let connected = false;
  export let connectable = false;

  function onDisconnectClick(e: MouseEvent) {
    e.stopPropagation();
    dispatch('disconnectInlet', { nodeId: node.data.id });
  }
</script>

<div
  class={`relative pl-10 transition-all duration-150 ${$$restProps.class ?? ''}`}
  class:inlet-hover={connectable}
  class:inlet-active={connectable}
>
  <div class="absolute left-0 top-1/2 -translate-x-[40%] -translate-y-1/2">
    <button
      type="button"
      data-inlet-node-id={node.data.id}
      class="group pointer-events-auto relative flex items-center gap-2 rounded-full border bg-white px-2.5 py-1 shadow-sm transition-all duration-150 dark:bg-slate-900"
      class:border-sky-300={!connected}
      class:hover:border-sky-400={connectable}
      class:hover:bg-sky-50={connectable}
      class:border-emerald-300={connected}
      class:text-emerald-700={connected}
      class:border-sky-700={!connected}
      on:click={() => dispatch('inletSelected', { nodeId: node.data.id })}
      on:keydown={(e) => {
        if (e.key === 'Enter') {
          dispatch('inletSelected', { nodeId: node.data.id });
        }
      }}
    >
      <div
        id={`${node.data.id}__inlet`}
        class="h-3.5 w-3.5 rounded-full border-2 bg-white shadow-sm ring-2 ring-white transition-transform duration-150 dark:ring-slate-900"
        class:border-sky-500={!connected}
        class:border-emerald-500={connected}
        class:group-hover:scale-110={connectable}
      ></div>
      <span
        class="text-[10px] font-semibold uppercase tracking-wide"
        class:text-sky-700={!connected}
        class:dark:text-sky-200={!connected}
      >
        {#if connected}
          Connected
        {:else if connectable}
          Connect here
        {:else}
          Target
        {/if}
      </span>
      {#if connected}
        <button
          type="button"
          class="inline-flex h-4 w-4 items-center justify-center rounded-full border border-emerald-400 text-emerald-700 hover:bg-emerald-100 dark:border-emerald-600 dark:text-emerald-300 dark:hover:bg-slate-800"
          on:click={onDisconnectClick}
        >
          <span class="text-[10px] leading-none">x</span>
        </button>
      {/if}
    </button>
  </div>
  <slot />
</div>

<style lang="postcss">
  .inlet-hover {
    @apply cursor-pointer hover:bg-sky-50 hover:ring-2 hover:ring-sky-300;
  }

  .inlet-active {
    @apply ring-2 ring-sky-300 ring-offset-2;
  }
</style>
