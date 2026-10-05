<script lang="ts">
  import { page } from '$app/state';
  import SideBarIcon, { type SideBarIconName } from './SideBarIcon.svelte';

  interface Props {
    href: string;
    title: string;
    icon: SideBarIconName;
    // Whether this is the page you are on. By default: any page under href.
    active?: boolean;
  }

  let { href, title, icon, active }: Props = $props();

  const isActive = $derived(
    active ?? (page.url.pathname === href || page.url.pathname.startsWith(`${href}/`)),
  );
</script>

<li>
  <a
    {href}
    aria-current={isActive ? 'page' : undefined}
    class="group flex items-center gap-3 rounded-xl px-3 py-2 text-sm font-medium {isActive
      ? 'bg-slate-100 text-slate-900 dark:bg-slate-700 dark:text-white'
      : 'text-slate-600 hover:bg-slate-100 hover:text-slate-900 dark:text-slate-300 dark:hover:bg-slate-700/60 dark:hover:text-white'}"
  >
    <SideBarIcon
      name={icon}
      class={isActive
        ? 'text-cyan-600 dark:text-cyan-300'
        : 'text-slate-400 group-hover:text-slate-600 dark:group-hover:text-slate-200'}
    />
    <span>{title}</span>
  </a>
</li>
