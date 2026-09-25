<script lang="ts">
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import { page } from '$app/stores';
  import { postJson } from '$lib/http';
  import { setSessionToken } from '$lib/session';

  let error = '';

  onMount(async () => {
    const result = await postJson<{ token: string }>('/api/v2/auth/verify-email', {
      token: $page.params.token,
    });

    if (!result.ok || !result.data.token) {
      error = result.ok ? '' : result.error;
      error ||= 'Verification link is invalid or expired.';
      return;
    }

    setSessionToken(result.data.token);
    await goto('/app', { invalidateAll: true });
  });
</script>

<section class="min-h-screen bg-gray-50 dark:bg-gray-900">
  <div class="mx-auto flex min-h-screen max-w-xl items-center px-6 py-10">
    <div
      class="w-full rounded-3xl border border-slate-200 bg-white p-8 shadow-xl dark:border-slate-700 dark:bg-slate-800"
    >
      <p class="text-sm uppercase tracking-[0.3em] text-cyan-600 dark:text-cyan-300">Comcent</p>
      {#if error}
        <h1 class="mt-4 text-3xl font-semibold text-slate-900 dark:text-white">
          Email verification failed.
        </h1>
        <p class="mt-4 text-sm text-slate-600 dark:text-slate-300">
          {error}
        </p>
        <a
          href="/login"
          class="mt-6 inline-block rounded-xl bg-slate-900 px-4 py-3 text-sm font-semibold text-white hover:bg-slate-700 dark:bg-cyan-500 dark:text-slate-950"
        >
          Back to sign in
        </a>
      {:else}
        <h1 class="mt-4 text-3xl font-semibold text-slate-900 dark:text-white">
          Verifying your email...
        </h1>
      {/if}
    </div>
  </div>
</section>
