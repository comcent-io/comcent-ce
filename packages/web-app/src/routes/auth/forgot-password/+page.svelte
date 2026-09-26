<script lang="ts">
  import { postJson } from '$lib/http';

  let email = $state('');
  let message = $state('');
  let error = $state('');
  let isSubmitting = $state(false);

  async function requestReset() {
    isSubmitting = true;
    message = '';
    error = '';

    const result = await postJson<{ message: string }>('/api/v2/auth/forgot-password', { email });
    if (result.ok) {
      message = result.data.message;
    } else {
      error = result.error || 'Unable to send the reset link. Please try again.';
    }

    isSubmitting = false;
  }
</script>

<section class="min-h-screen bg-gray-50 dark:bg-gray-900">
  <div class="mx-auto flex min-h-screen max-w-xl items-center px-6 py-10">
    <div
      class="w-full rounded-3xl border border-slate-200 bg-white p-8 shadow-xl dark:border-slate-700 dark:bg-slate-800"
    >
      <p class="text-sm uppercase tracking-[0.3em] text-cyan-600 dark:text-cyan-300">Comcent</p>
      <h1 class="mt-4 text-3xl font-semibold text-slate-900 dark:text-white">
        Reset your password.
      </h1>

      {#if message}
        <p class="mt-4 text-sm text-emerald-700 dark:text-emerald-400">{message}</p>
        <p class="mt-2 text-sm text-slate-600 dark:text-slate-300">
          The link works once and expires in 1 hour.
        </p>
      {:else}
        <p class="mt-4 text-sm text-slate-600 dark:text-slate-300">
          Enter the email you sign in with and we'll send you a link to choose a new password.
        </p>

        <form
          method="POST"
          class="mt-6 space-y-4"
          onsubmit={(e) => {
            e.preventDefault();
            requestReset();
          }}
        >
          <div>
            <label
              for="forgot-email"
              class="mb-2 block text-sm font-medium text-slate-700 dark:text-slate-200"
            >
              Email address
            </label>
            <input
              id="forgot-email"
              bind:value={email}
              name="email"
              type="email"
              required
              class="block w-full rounded-xl border border-slate-300 px-4 py-3 text-sm focus:border-cyan-500 focus:outline-none dark:border-slate-600 dark:bg-slate-900 dark:text-white"
            />
          </div>
          {#if error}
            <p class="text-sm text-red-600 dark:text-red-400">{error}</p>
          {/if}
          <button
            type="submit"
            disabled={isSubmitting}
            class="w-full rounded-xl bg-slate-900 px-4 py-3 text-sm font-semibold text-white hover:bg-slate-700 disabled:cursor-not-allowed disabled:opacity-60 dark:bg-cyan-500 dark:text-slate-950"
          >
            {isSubmitting ? 'Sending...' : 'Send reset link'}
          </button>
        </form>
      {/if}

      <a
        href="/login"
        class="mt-6 inline-block text-sm font-medium text-cyan-700 hover:text-cyan-900 dark:text-cyan-300 dark:hover:text-cyan-200"
      >
        Back to sign in
      </a>
    </div>
  </div>
</section>
