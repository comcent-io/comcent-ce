<script lang="ts">
  import type { HTMLInputAttributes } from 'svelte/elements';
  import { checkboxClass } from './classes';

  // The app's checkbox box on its own (its label is up to the caller; see
  // CheckboxRow for a box with a title and description). Binds `checked`.
  interface Props extends Omit<HTMLInputAttributes, 'type'> {
    checked?: boolean;
  }

  let { checked = $bindable(false), class: extra = '', ...rest }: Props = $props();
</script>

<input {...rest} type="checkbox" bind:checked class="{checkboxClass} {extra}" />
