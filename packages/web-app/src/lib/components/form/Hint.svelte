<script lang="ts">
  import type { Snippet } from 'svelte';
  import { errorClass, hintClass } from './classes';

  // The small line under a field: a hint, or (with `error`) what's wrong.
  interface Props {
    id?: string;
    error?: boolean;
    class?: string;
    children?: Snippet;
  }

  let { id, error = false, class: extra = '', children }: Props = $props();
</script>

<p {id} class="{error ? errorClass : hintClass} {extra}">{@render children?.()}</p>
