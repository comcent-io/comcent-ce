<script lang="ts">
  import type { HTMLTextareaAttributes } from 'svelte/elements';
  import { textareaClass } from './classes';

  // The app's multi-line input. Binds its value; other attributes pass
  // through.
  interface Props extends HTMLTextareaAttributes {
    value?: HTMLTextareaAttributes['value'];
    invalid?: boolean;
  }

  let { value = $bindable(), invalid = false, class: extra = '', ...rest }: Props = $props();
</script>

<textarea
  {...rest}
  bind:value
  aria-invalid={invalid || rest['aria-invalid'] || undefined}
  class="{textareaClass} {extra}"
></textarea>
