<script lang="ts">
  import { createEventDispatcher } from 'svelte';
  import type { FlowNode } from '../nodes/FlowNode';
  const dispatch = createEventDispatcher();
  export let node: FlowNode;
  export let title = '';

  export let tx = node?.data?.screen?.tx ?? 0;
  export let ty = node?.data?.screen?.ty ?? 0;

  let mouseDown = false;
  let mouseDownX = 0;
  let mouseDownY = 0;

  function handleMouseMove(e: MouseEvent) {
    if (mouseDown) {
      tx = e.clientX - mouseDownX;
      ty = e.clientY - mouseDownY;
    }
  }

  function handleMouseUp() {
    if (mouseDown) {
      mouseDown = false;
      dispatch('dragEnd', { node, tx, ty });
    }
  }

  function handleDragStart(e: MouseEvent) {
    e.preventDefault();
    mouseDown = true;
    mouseDownX = e.clientX - tx;
    mouseDownY = e.clientY - ty;
  }

  // Svelte action to handle document event listeners with auto-cleanup
  function documentListeners(node: HTMLElement) {
    document.addEventListener('mousemove', handleMouseMove);
    document.addEventListener('mouseup', handleMouseUp);

    return {
      destroy() {
        document.removeEventListener('mousemove', handleMouseMove);
        document.removeEventListener('mouseup', handleMouseUp);
      },
    };
  }
</script>

<div
  class="{$$restProps.class || ''} relative"
  id={$$restProps.id || node.data.id || ''}
  style="transform: translate({tx}px, {ty}px)"
  use:documentListeners
>
  <div
    class="flex cursor-grab items-center justify-between rounded-t-lg border-b border-slate-200 bg-slate-100 px-3 py-2 active:cursor-grabbing dark:border-slate-700 dark:bg-slate-800"
    on:mousedown={handleDragStart}
    role="button"
    tabindex="0"
  >
    <div class="min-w-0">
      <div class="flex items-center gap-2">
        <span class="flex gap-0.5" aria-hidden="true">
          <span class="h-1.5 w-1.5 rounded-full bg-slate-400"></span>
          <span class="h-1.5 w-1.5 rounded-full bg-slate-400"></span>
          <span class="h-1.5 w-1.5 rounded-full bg-slate-400"></span>
        </span>
        <span class="truncate text-sm font-semibold text-slate-800 dark:text-slate-100">
          {title || node?.data?.type || 'Flow block'}
        </span>
      </div>
      <p class="mt-0.5 text-[11px] text-slate-500 dark:text-slate-400">
        Drag this header to reposition
      </p>
    </div>
    <div class="ml-3 flex items-center gap-1.5" on:mousedown|stopPropagation>
      <slot name="headerActions" />
    </div>
  </div>
  <div class="rounded-b-lg">
    <slot />
  </div>
</div>
