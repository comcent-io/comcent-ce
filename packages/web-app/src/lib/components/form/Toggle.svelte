<script lang="ts">
  // An on/off switch with its label (and an optional description) beside it.
  // It is a real checkbox underneath, so labels, forms and tests treat it as
  // one.
  interface Props {
    id: string;
    label: string;
    description?: string;
    checked?: boolean;
    disabled?: boolean;
    onchange?: (checked: boolean) => void;
  }

  let {
    id,
    label,
    description,
    checked = $bindable(false),
    disabled = false,
    onchange,
  }: Props = $props();
</script>

<label for={id} class="flex cursor-pointer items-start gap-3">
  <span class="relative mt-0.5 inline-flex shrink-0">
    <input
      {id}
      type="checkbox"
      class="peer sr-only"
      bind:checked
      {disabled}
      onchange={() => onchange?.(checked)}
    />
    <span
      class="h-5 w-9 rounded-full bg-gray-300 transition peer-checked:bg-blue-600 peer-focus-visible:ring-2 peer-focus-visible:ring-blue-500 peer-focus-visible:ring-offset-2 peer-disabled:opacity-50 dark:bg-gray-600"
    ></span>
    <span
      class="absolute left-0.5 top-0.5 h-4 w-4 rounded-full bg-white shadow transition peer-checked:translate-x-4"
    ></span>
  </span>
  <span>
    <span class="block text-sm font-medium text-gray-900 dark:text-white">{label}</span>
    {#if description}
      <span class="mt-0.5 block text-xs text-gray-500 dark:text-gray-400">{description}</span>
    {/if}
  </span>
</label>
