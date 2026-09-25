<script lang="ts">
  interface Props {
    href: string;
    title: string;
    icon: any;
  }

  let { href, title, icon }: Props = $props();

  const SvelteComponent = $derived(icon);
</script>

<li>
  <a
    {href}
    class="flex items-center p-2 text-base font-medium text-gray-900 rounded-lg dark:text-white hover:bg-gray-100 dark:hover:bg-gray-700 group"
  >
    <SvelteComponent />
    <span class="ml-3">{title}</span>
  </a>
</li>
