<script lang="ts">
  // Tabs that switch what is shown in place (e.g. inside a dialog), in the
  // same underline style as the Settings page's tabs.
  interface Tab {
    id: string;
    label: string;
  }

  interface Props {
    tabs: Tab[];
    current: string;
    onSelect: (id: string) => void;
  }

  let { tabs, current, onSelect }: Props = $props();
</script>

<div
  class="border-b border-gray-200 text-sm font-medium text-gray-500 dark:border-gray-700 dark:text-gray-400"
>
  <ul class="-mb-px flex flex-wrap" role="tablist">
    {#each tabs as tab (tab.id)}
      <li class="me-2">
        <button
          type="button"
          role="tab"
          aria-selected={current === tab.id}
          onclick={() => onSelect(tab.id)}
          class="inline-block rounded-t-lg border-b-2 px-4 py-3 {current === tab.id
            ? 'border-blue-600 text-blue-600 dark:border-blue-500 dark:text-blue-500'
            : 'border-transparent hover:border-gray-300 hover:text-gray-600 dark:hover:text-gray-300'}"
        >
          {tab.label}
        </button>
      </li>
    {/each}
  </ul>
</div>
