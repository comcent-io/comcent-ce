<script lang="ts">
  import type { Snippet } from 'svelte';
  import type { HTMLAnchorAttributes, HTMLButtonAttributes } from 'svelte/elements';
  import { secondaryActionClass, secondaryActionSmallClass } from './classes';

  // A quiet action beside the main one: Cancel, Copy, "+ Add …". A link when
  // given `href`, otherwise a button (type "button" unless said otherwise).
  type Props = (HTMLAnchorAttributes & HTMLButtonAttributes) & {
    href?: string;
    size?: 'md' | 'sm';
    children?: Snippet;
  };

  let {
    href,
    size = 'md',
    type = 'button',
    class: extra = '',
    children,
    ...rest
  }: Props = $props();

  let className = $derived(
    `${size === 'sm' ? secondaryActionSmallClass : secondaryActionClass} ${extra}`,
  );
</script>

{#if href}
  <a {...rest as HTMLAnchorAttributes} {href} class={className}>{@render children?.()}</a>
{:else}
  <button {...rest as HTMLButtonAttributes} {type} class={className}>
    {@render children?.()}
  </button>
{/if}
