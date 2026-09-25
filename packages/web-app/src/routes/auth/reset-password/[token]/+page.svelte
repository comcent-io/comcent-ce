<script lang="ts">
  import { goto } from '$app/navigation';
  import { page } from '$app/stores';
  import { postJson } from '$lib/http';
  import { setSessionToken } from '$lib/session';

  let password = '';
  let confirmPassword = '';
  let error = '';
  let isSubmitting = false;

  async function resetPassword() {
    error = '';
    if (password !== confirmPassword) {
      error = 'The two passwords do not match.';
      return;
    }

    isSubmitting = true;
    const result = await postJson<{ token: string }>('/api/v2/auth/reset-password', {
      token: $page.params.token,
      password,
    });
    if (!result.ok) {
      error = result.error || 'Unable to reset the password. Please try again.';
      isSubmitting = false;
      return;
    }

    setSessionToken(result.data.token);
    await goto('/app', { invalidateAll: true });
  }
</script>

<section class="min-h-screen bg-gray-50 dark:bg-gray-900">
  <div class="mx-auto flex min-h-screen max-w-xl items-center px-6 py-10">
    <div
      class="w-full rounded-3xl border border-slate-200 bg-white p-8 shadow-xl dark:border-slate-700 dark:bg-slate-800"
    >
      <p class="text-sm uppercase tracking-[0.3em] text-cyan-600 dark:text-cyan-300">Comcent</p>
      <h1 class="mt-4 text-3xl font-semibold text-slate-900 dark:text-white">
        Choose a new password.
      </h1>
      <p class="mt-4 text-sm text-slate-600 dark:text-slate-300">
        After this, you'll be signed out everywhere else.
      </p>

      <form method="POST" class="mt-6 space-y-4" on:submit|preventDefault={resetPassword}>
        <div>
          <label
            for="reset-password"
            class="mb-2 block text-sm font-medium text-slate-700 dark:text-slate-200"
          >
            New password (8+ characters)
          </label>
          <input
            id="reset-password"
            bind:value={password}
            name="password"
            type="password"
            required
            minlength="8"
            autocomplete="new-password"
            class="block w-full rounded-xl border border-slate-300 px-4 py-3 text-sm focus:border-cyan-500 focus:outline-none dark:border-slate-600 dark:bg-slate-900 dark:text-white"
          />
        </div>
        <div>
          <label
            for="reset-password-confirm"
            class="mb-2 block text-sm font-medium text-slate-700 dark:text-slate-200"
          >
            Confirm new password
          </label>
          <input
            id="reset-password-confirm"
            bind:value={confirmPassword}
            name="confirmPassword"
            type="password"
            required
            minlength="8"
            autocomplete="new-password"
            class="block w-full rounded-xl border border-slate-300 px-4 py-3 text-sm focus:border-cyan-500 focus:outline-none dark:border-slate-600 dark:bg-slate-900 dark:text-white"
          />
        </div>
        {#if error}
          <p class="text-sm text-red-600 dark:text-red-400">{error}</p>
          <a
            href="/auth/forgot-password"
            class="inline-block text-sm font-medium text-cyan-700 hover:text-cyan-900 dark:text-cyan-300 dark:hover:text-cyan-200"
          >
            Request a new link
          </a>
        {/if}
        <button
          type="submit"
          disabled={isSubmitting}
          class="w-full rounded-xl bg-slate-900 px-4 py-3 text-sm font-semibold text-white hover:bg-slate-700 disabled:cursor-not-allowed disabled:opacity-60 dark:bg-cyan-500 dark:text-slate-950"
        >
          {isSubmitting ? 'Saving...' : 'Set new password'}
        </button>
      </form>
    </div>
  </div>
</section>
