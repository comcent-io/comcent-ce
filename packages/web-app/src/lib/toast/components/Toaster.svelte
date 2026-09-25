<script lang="ts">
  import type { ToasterProps } from '../core/types';
  import useToaster from '../core/use-toaster';
  import ToastWrapper from './ToastWrapper.svelte';

  let {
    reverseOrder = false,
    position = 'top-center',
    toastOptions = undefined,
    gutter = 8,
    containerStyle = undefined,
    containerClassName = undefined,
  }: ToasterProps = $props();

  // Read once: the toaster is mounted once, with fixed options.
  // svelte-ignore state_referenced_locally
  const { toasts, handlers } = useToaster(toastOptions);

  let _toasts = $derived(
    $toasts.map((toast) => ({
      ...toast,
      position: toast.position || position,
      offset: handlers.calculateOffset(toast, $toasts, {
        reverseOrder,
        gutter,
        defaultPosition: position,
      }),
    })),
  );
</script>

<div
  class="toaster {containerClassName || ''}"
  style={containerStyle}
  onmouseenter={handlers.startPause}
  onmouseleave={handlers.endPause}
  role="alert"
>
  {#each _toasts as toast (toast.id)}
    <ToastWrapper {toast} setHeight={(height) => handlers.updateHeight(toast.id, height)} />
  {/each}
</div>

<style>
  .toaster {
    --default-offset: 16px;

    position: fixed;
    z-index: 9999;
    top: var(--default-offset);
    left: var(--default-offset);
    right: var(--default-offset);
    bottom: var(--default-offset);
    pointer-events: none;
  }
</style>
