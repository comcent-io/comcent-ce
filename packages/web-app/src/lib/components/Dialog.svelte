<script lang="ts">
  import type { Snippet } from 'svelte';
  import CloseIcon from './Icons/CloseIcon.svelte';

  // A dialog over the page, in the same card look as the rest of the app: a
  // title, an optional line under it, and the content. Escape, the close
  // button and a click outside it all call onClose.
  let {
    showDialog = false,
    title = '',
    description = '',
    className = 'max-w-xl',
    onClose,
    children,
  }: {
    showDialog?: boolean;
    title?: string;
    description?: string;
    className?: string;
    onClose?: () => void;
    children?: Snippet;
  } = $props();

  const titleId = `dialog-title-${Math.random().toString(36).slice(2)}`;
</script>

<svelte:window
  onkeydown={(e) => {
    if (showDialog && e.key === 'Escape') onClose?.();
  }}
/>

{#if showDialog}
  <!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions -->
  <div
    class="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-slate-900/50 p-4 backdrop-blur-[2px] sm:items-center"
    onclick={(e) => {
      if (e.target === e.currentTarget) onClose?.();
    }}
  >
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby={titleId}
      class="relative flex max-h-[90vh] w-full flex-col rounded-xl border border-gray-200 bg-white shadow-xl dark:border-gray-700 dark:bg-gray-800 {className}"
    >
      <div
        class="flex items-start justify-between gap-4 border-b border-gray-200 px-6 py-4 dark:border-gray-700"
      >
        <div class="min-w-0">
          <h3 id={titleId} class="text-lg font-semibold text-gray-900 dark:text-white">
            {title}
          </h3>
          {#if description}
            <p class="mt-0.5 text-sm text-gray-500 dark:text-gray-400">{description}</p>
          {/if}
        </div>
        <button
          type="button"
          class="-me-2 inline-flex h-8 w-8 shrink-0 items-center justify-center rounded-lg text-gray-400 hover:bg-gray-100 hover:text-gray-900 dark:hover:bg-gray-700 dark:hover:text-white"
          onclick={() => onClose?.()}
        >
          <!-- Labelled "Close modal" for screen readers. -->
          <CloseIcon />
        </button>
      </div>
      <div class="space-y-4 overflow-auto px-6 py-5">
        {@render children?.()}
      </div>
    </div>
  </div>
{/if}
