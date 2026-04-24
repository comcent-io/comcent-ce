<script lang="ts">
  import { createEventDispatcher } from 'svelte';
  import type { SelectedOutlet } from '../SelectedOutlet';

  const dispatch = createEventDispatcher();
  export let selectedOutlet: SelectedOutlet | null;

  export let nodeId: string;
  export let outletId = 'default';

  export let isDeletable = false;
  export let connected = false;

  function onOutLetClick(e) {
    e.stopPropagation();
    dispatch('outletSelected', { nodeId, outletId });
  }

  function onDeleteClick(e) {
    e.stopPropagation();
    dispatch('deleteOutlet', { nodeId, outletId });
  }

  function onKeyDown(e) {
    if (e.key === 'Enter') {
      onOutLetClick(e);
    }
  }
</script>

<div
  class="relative mt-2.5 w-full rounded-lg border border-emerald-300 bg-emerald-50/70 p-2.5 pr-24 transition-all duration-150 dark:border-emerald-800 dark:bg-slate-900/95 {$$restProps.class ||
    ''}"
  class:outlet-hover={!selectedOutlet}
  class:outlet-selected={selectedOutlet?.nodeId === nodeId && selectedOutlet?.outletId === outletId}
  id={`${nodeId}-${outletId}`}
  role="button"
  tabindex="0"
  on:click={onOutLetClick}
  on:keydown={onKeyDown}
>
  <div class="absolute right-0 top-[58%] translate-x-[40%] -translate-y-1/2">
    <button
      type="button"
      class="group flex items-center gap-2 rounded-full border px-2.5 py-1 shadow-sm transition-all duration-150"
      class:border-emerald-300={!selectedOutlet ||
        selectedOutlet?.nodeId !== nodeId ||
        selectedOutlet?.outletId !== outletId}
      class:bg-white={!selectedOutlet ||
        selectedOutlet?.nodeId !== nodeId ||
        selectedOutlet?.outletId !== outletId}
      class:text-emerald-700={!selectedOutlet ||
        selectedOutlet?.nodeId !== nodeId ||
        selectedOutlet?.outletId !== outletId}
      class:hover:border-emerald-400={!selectedOutlet ||
        selectedOutlet?.nodeId !== nodeId ||
        selectedOutlet?.outletId !== outletId}
      class:hover:bg-emerald-50={!selectedOutlet ||
        selectedOutlet?.nodeId !== nodeId ||
        selectedOutlet?.outletId !== outletId}
      class:border-emerald-500={selectedOutlet?.nodeId === nodeId &&
        selectedOutlet?.outletId === outletId}
      class:bg-emerald-600={selectedOutlet?.nodeId === nodeId &&
        selectedOutlet?.outletId === outletId}
      class:text-white={selectedOutlet?.nodeId === nodeId && selectedOutlet?.outletId === outletId}
      on:click={onOutLetClick}
      on:keydown={onKeyDown}
    >
      <span class="text-[10px] font-semibold uppercase tracking-wide">
        {#if selectedOutlet?.nodeId === nodeId && selectedOutlet?.outletId === outletId}
          Selected
        {:else if connected}
          Connected
        {:else}
          Route out
        {/if}
      </span>
      {#if connected}
        <button
          type="button"
          class="inline-flex h-4 w-4 items-center justify-center rounded-full border border-emerald-400 text-emerald-700 hover:bg-emerald-100 dark:border-emerald-600 dark:text-emerald-300 dark:hover:bg-slate-800"
          on:click={(e) => {
            e.stopPropagation();
            dispatch('disconnectOutlet', { nodeId, outletId });
          }}
        >
          <span class="text-[10px] leading-none">x</span>
        </button>
      {/if}
      <div
        id={`${nodeId}-${outletId}__outlet`}
        class="h-3.5 w-3.5 rounded-full border-2 border-emerald-500 bg-white shadow-sm ring-2 ring-white transition-transform duration-150 group-hover:scale-110 dark:ring-slate-900"
      ></div>
    </button>
  </div>
  <slot />
  {#if isDeletable}
    <button
      type="button"
      on:click|preventDefault={onDeleteClick}
      class="text-red-700 hover:bg-red-700 hover:text-white focus:ring-4 focus:outline-none focus:ring-blue-300 absolute top-0 rounded-full right-0 font-bold p-1 text-xs dark:text-red-300 dark:hover:bg-red-600"
      style="margin-top: 0.25rem; margin-right: 0.25rem;"
    >
      <svg
        xmlns="http://www.w3.org/2000/svg"
        fill="none"
        viewBox="0 0 24 24"
        stroke-width="1.5"
        stroke="currentColor"
        class="w-6 h-6"
      >
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          d="M9.75 9.75l4.5 4.5m0-4.5l-4.5 4.5M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
        />
      </svg>
      <span class="sr-only">Close Button</span>
    </button>
  {/if}
</div>

<style lang="postcss">
  .outlet-hover {
    @apply cursor-pointer hover:bg-emerald-50 hover:ring-2 hover:ring-emerald-300 dark:hover:bg-slate-800;
  }

  .outlet-selected {
    @apply cursor-pointer border-emerald-500 bg-emerald-500 text-white ring-2 ring-emerald-300 ring-offset-2 dark:ring-offset-slate-950;
  }
</style>
