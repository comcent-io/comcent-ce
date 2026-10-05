<script lang="ts">
  import type { Snippet } from 'svelte';
  import type { HTMLAnchorAttributes, HTMLButtonAttributes } from 'svelte/elements';
  import { secondaryActionBase, secondaryActionSize, secondaryActionTone } from './classes';

  // A quiet action beside the main one: Cancel, Copy, "+ Add …", a row's
  // Edit; `tone="danger"` for a destructive one such as Delete. A link when
  // given `href`, otherwise a button (type "button" unless said otherwise).
  type Props = (HTMLAnchorAttributes & HTMLButtonAttributes) & {
    href?: string;
    size?: 'md' | 'sm';
    tone?: 'default' | 'danger';
    children?: Snippet;
  };

  let {
    href,
    size = 'md',
    tone = 'default',
    type = 'button',
    class: extra = '',
    children,
    ...rest
  }: Props = $props();

  let className = $derived(
    `${secondaryActionBase} ${secondaryActionSize[size]} ${secondaryActionTone[tone]} ${extra}`,
  );
</script>

{#if href}
  <a {...rest as HTMLAnchorAttributes} {href} class={className}>{@render children?.()}</a>
{:else}
  <button {...rest as HTMLButtonAttributes} {type} class={className}>
    {@render children?.()}
  </button>
{/if}
