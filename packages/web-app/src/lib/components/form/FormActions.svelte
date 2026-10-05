<script lang="ts">
  import type { Snippet } from 'svelte';
  import SecondaryButton from './SecondaryButton.svelte';

  // The end of a form: the primary action (children, usually a submit
  // Button) and an optional Cancel link back.
  interface Props {
    cancelHref?: string;
    cancelLabel?: string;
    children?: Snippet;
  }

  let { cancelHref, cancelLabel = 'Cancel', children }: Props = $props();
</script>

<div class="flex flex-wrap items-center gap-3">
  {@render children?.()}
  {#if cancelHref}
    <SecondaryButton href={cancelHref}>{cancelLabel}</SecondaryButton>
  {/if}
</div>
