<script lang="ts">
  import type { Snippet } from 'svelte';
  import { labelClass } from './classes';

  // A field's name. A <label> when it names a control (`for`); as a heading
  // over something that isn't one, pass `tag` (e.g. "legend", "p").
  interface Props {
    for?: string;
    tag?: 'label' | 'legend' | 'p' | 'span';
    class?: string;
    children?: Snippet;
  }

  let { for: htmlFor, tag = 'label', class: extra = '', children }: Props = $props();
</script>

<svelte:element this={tag} for={tag === 'label' ? htmlFor : undefined} class="{labelClass} {extra}">
  {@render children?.()}
</svelte:element>
