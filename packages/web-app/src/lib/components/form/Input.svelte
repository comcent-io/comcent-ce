<script lang="ts">
  import type { HTMLInputAttributes } from 'svelte/elements';
  import { inputClass } from './classes';

  // The app's text input: any type but checkbox (see Checkbox). Binds its
  // value; every other attribute passes through. `invalid` marks it red and
  // tells assistive tech. `class` adds to the look, e.g. a width.
  interface Props extends HTMLInputAttributes {
    value?: HTMLInputAttributes['value'];
    invalid?: boolean;
  }

  let { value = $bindable(), invalid = false, class: extra = '', ...rest }: Props = $props();
</script>

<input
  {...rest}
  bind:value
  aria-invalid={invalid || rest['aria-invalid'] || undefined}
  class="{inputClass} {extra}"
/>
