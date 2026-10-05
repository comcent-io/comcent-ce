<script lang="ts">
  import type { Snippet } from 'svelte';
  import type { HTMLSelectAttributes } from 'svelte/elements';
  import { inputClass } from './classes';

  // The app's select. The options are its children. Binds its value; other
  // attributes pass through.
  interface Props extends HTMLSelectAttributes {
    value?: HTMLSelectAttributes['value'];
    invalid?: boolean;
    children?: Snippet;
  }

  let {
    value = $bindable(),
    invalid = false,
    class: extra = '',
    children,
    ...rest
  }: Props = $props();
</script>

<select
  {...rest}
  bind:value
  aria-invalid={invalid || rest['aria-invalid'] || undefined}
  class="{inputClass} {extra}"
>
  {@render children?.()}
</select>
