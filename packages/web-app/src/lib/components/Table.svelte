<script lang="ts">
  import type { Snippet } from 'svelte';
  import Spinner from './Icons/Spinner.svelte';

  // The app's list table, in a card: a header row from `columns`, and the
  // rows as children (plain <tr><td>: cell padding, row borders and hover
  // come from here). While `loading` it shows a spinner; when `isEmpty` it
  // shows `empty` (usually an EmptyState) instead of the rows.
  type Column = string | { label: string; srOnly?: boolean; align?: 'left' | 'right' };

  interface Props {
    columns: Column[];
    loading?: boolean;
    isEmpty?: boolean;
    empty?: Snippet;
    children?: Snippet;
  }

  let { columns, loading = false, isEmpty = false, empty, children }: Props = $props();

  const asColumn = (c: Column) => (typeof c === 'string' ? { label: c } : c);
</script>

<div
  class="overflow-x-auto rounded-lg border border-gray-200 bg-white shadow dark:border-gray-700 dark:bg-gray-800"
>
  <table
    class="w-full text-left text-sm text-gray-500 dark:text-gray-400 [&_tbody_td]:px-6 [&_tbody_td]:py-4 [&_tbody_th]:px-6 [&_tbody_th]:py-4 [&_tbody_tr:last-child]:border-0 [&_tbody_tr]:border-b [&_tbody_tr]:border-gray-200 dark:[&_tbody_tr]:border-gray-700"
  >
    <thead
      class="border-b border-gray-200 bg-gray-50 text-xs uppercase text-gray-700 dark:border-gray-700 dark:bg-gray-700 dark:text-gray-400"
    >
      <tr>
        {#each columns.map(asColumn) as column, i (i)}
          <th scope="col" class="px-6 py-3 {column.align === 'right' ? 'text-right' : ''}">
            {#if column.srOnly}<span class="sr-only">{column.label}</span>{:else}{column.label}{/if}
          </th>
        {/each}
      </tr>
    </thead>
    <tbody>
      {#if loading}
        <tr>
          <td colspan={columns.length} class="py-10">
            <div class="flex justify-center"><Spinner /></div>
          </td>
        </tr>
      {:else if isEmpty && empty}
        <tr>
          <td colspan={columns.length} class="p-6">{@render empty()}</td>
        </tr>
      {:else}
        {@render children?.()}
      {/if}
    </tbody>
  </table>
</div>
