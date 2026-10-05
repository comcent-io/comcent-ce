<script lang="ts">
  import type { Snippet } from 'svelte';
  import SideBarIcon, { type SideBarIconName } from './SideBarIcon.svelte';

  // A menu item that opens to show more under it, e.g. Switch Organization.
  interface Props {
    title: string;
    icon: SideBarIconName;
    open?: boolean;
    children?: Snippet;
  }

  let { title, icon, open = $bindable(false), children }: Props = $props();
</script>

<li>
  <button
    type="button"
    aria-expanded={open}
    class="group flex w-full items-center gap-3 rounded-xl px-3 py-2 text-sm font-medium text-slate-600 hover:bg-slate-100 hover:text-slate-900 dark:text-slate-300 dark:hover:bg-slate-700/60 dark:hover:text-white"
    onclick={() => (open = !open)}
  >
    <SideBarIcon
      name={icon}
      class="text-slate-400 group-hover:text-slate-600 dark:group-hover:text-slate-200"
    />
    <span>{title}</span>
    <SideBarIcon
      name="chevronDown"
      class="ml-auto scale-75 text-slate-400 transition-transform {open ? '' : '-rotate-90'}"
    />
  </button>
  {#if open}
    {@render children?.()}
  {/if}
</li>
