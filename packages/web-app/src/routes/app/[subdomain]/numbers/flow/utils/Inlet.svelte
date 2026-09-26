<script lang="ts">
  import type { Snippet } from 'svelte';
  import type { SelectedInlet } from '../SelectedInlet';
  import type { FlowNode } from '../nodes/FlowNode.svelte';

  interface Props {
    node: FlowNode;
    connected?: boolean;
    connectable?: boolean;
    class?: string;
    onInletSelected?: (inlet: SelectedInlet) => void;
    onDisconnectInlet?: (inlet: SelectedInlet) => void;
    children?: Snippet;
  }

  let {
    node,
    connected = false,
    connectable = false,
    class: className = '',
    onInletSelected,
    onDisconnectInlet,
    children,
  }: Props = $props();

  function onDisconnectClick(e: MouseEvent) {
    e.stopPropagation();
    onDisconnectInlet?.({ nodeId: node.data.id });
  }
</script>

<div
  class={`relative pl-10 transition-all duration-150 ${className}`}
  class:inlet-hover={connectable}
  class:inlet-active={connectable}
>
  <div class="absolute left-0 top-1/2 -translate-x-[40%] -translate-y-1/2">
    <!-- A div, not a <button>: it holds the disconnect <button>, and HTML
         does not allow a button inside a button. -->
    <div
      role="button"
      tabindex="0"
      data-inlet-node-id={node.data.id}
      class="group pointer-events-auto relative flex items-center gap-2 rounded-full border bg-white px-2.5 py-1 shadow-sm transition-all duration-150 dark:bg-slate-900"
      class:border-sky-300={!connected}
      class:hover:border-sky-400={connectable}
      class:hover:bg-sky-50={connectable}
      class:border-emerald-300={connected}
      class:text-emerald-700={connected}
      class:border-sky-700={!connected}
      onclick={() => onInletSelected?.({ nodeId: node.data.id })}
      onkeydown={(e) => {
        if (e.key === 'Enter') {
          onInletSelected?.({ nodeId: node.data.id });
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
          onclick={onDisconnectClick}
        >
          <span class="text-[10px] leading-none">x</span>
        </button>
      {/if}
    </div>
  </div>
  {@render children?.()}
</div>

<style lang="postcss">
  .inlet-hover {
    @apply cursor-pointer hover:bg-sky-50 hover:ring-2 hover:ring-sky-300;
  }

  .inlet-active {
    @apply ring-2 ring-sky-300 ring-offset-2;
  }
</style>
