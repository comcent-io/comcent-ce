<script lang="ts">
  export let href: string;
  export let title: string;
  export let icon: any;
</script>

<li>
  <a
    {href}
    class="flex items-center p-2 text-base font-medium text-gray-900 rounded-lg dark:text-white hover:bg-gray-100 dark:hover:bg-gray-700 group"
  >
    <svelte:component this={icon} />
    <span class="ml-3">{title}</span>
  </a>
</li>
