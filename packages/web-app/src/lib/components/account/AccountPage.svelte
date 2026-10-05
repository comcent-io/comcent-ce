<script lang="ts">
  import type { Snippet } from 'svelte';
  import { logout } from '$lib/session';

  // The frame of the pages someone sees before they're in an org (the
  // organization list, an invitation): the Comcent mark, who is signed in,
  // and Logout, over a centred column.
  interface Props {
    email?: string | null;
    children?: Snippet;
  }

  let { email, children }: Props = $props();
</script>

<section class="min-h-screen px-4 py-10 sm:py-14">
  <div class="mx-auto max-w-3xl">
    <header class="flex items-center justify-between gap-4">
      <p class="text-sm uppercase tracking-[0.3em] text-cyan-600 dark:text-cyan-300">Comcent</p>
      <div class="flex items-center gap-3">
        {#if email}
          <span class="hidden text-sm text-slate-500 sm:inline dark:text-slate-400">{email}</span>
        {/if}
        <button
          type="button"
          onclick={logout}
          class="rounded-xl border border-slate-300 px-4 py-2 text-sm font-medium text-slate-700 hover:bg-white dark:border-slate-600 dark:text-slate-200 dark:hover:bg-slate-800"
        >
          Logout
        </button>
      </div>
    </header>

    {@render children?.()}
  </div>
</section>
