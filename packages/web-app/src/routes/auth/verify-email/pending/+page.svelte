<script lang="ts">
  import { onDestroy } from 'svelte';
  import { postJson } from '$lib/http';

  export let data;

  let remainingSeconds = 0;
  let countdownInterval: ReturnType<typeof setInterval> | null = null;
  let resendSuccess = '';
  let resendError = '';
  let isSubmitting = false;

  function clearCountdown() {
    if (countdownInterval) {
      clearInterval(countdownInterval);
      countdownInterval = null;
    }
  }

  function startCountdown(initialSeconds: number) {
    clearCountdown();
    remainingSeconds = initialSeconds;

    if (initialSeconds <= 0) {
      return;
    }

    const startedAt = Date.now();

    countdownInterval = setInterval(() => {
      const elapsedSeconds = Math.floor((Date.now() - startedAt) / 1000);
      remainingSeconds = Math.max(initialSeconds - elapsedSeconds, 0);

      if (remainingSeconds === 0) {
        clearCountdown();
      }
    }, 1000);
  }

  startCountdown(data.resendCooldownSeconds);

  async function resendVerification() {
    if (isSubmitting || remainingSeconds > 0) {
      return;
    }

    isSubmitting = true;
    resendSuccess = '';
    resendError = '';

    const result = await postJson<{
      message: string;
      retryAfterSeconds?: number;
      retry_after_seconds?: number;
    }>('/api/v2/auth/resend-verification', {
      email: data.email,
    });

    const retryAfterSeconds = result.ok
      ? (result.data.retryAfterSeconds ??
        result.data.retry_after_seconds ??
        data.resendCooldownSeconds)
      : ((result.data as { retryAfterSeconds?: number; retry_after_seconds?: number } | null)
          ?.retryAfterSeconds ??
        (result.data as { retryAfterSeconds?: number; retry_after_seconds?: number } | null)
          ?.retry_after_seconds ??
        data.resendCooldownSeconds);

    if (result.ok) {
      resendSuccess = result.data.message;
    } else {
      resendError = result.error || 'Unable to resend verification email.';
    }

    startCountdown(retryAfterSeconds);
    isSubmitting = false;
  }

  onDestroy(() => {
    clearCountdown();
  });
</script>

<section class="min-h-screen bg-gray-50 dark:bg-gray-900">
  <div class="mx-auto flex min-h-screen max-w-xl items-center px-6 py-10">
    <div
      class="w-full rounded-3xl border border-slate-200 bg-white p-8 shadow-xl dark:border-slate-700 dark:bg-slate-800"
    >
      <p class="text-sm uppercase tracking-[0.3em] text-cyan-600 dark:text-cyan-300">Comcent</p>
      <h1 class="mt-4 text-3xl font-semibold text-slate-900 dark:text-white">Check your email.</h1>
      <p class="mt-4 text-sm text-slate-600 dark:text-slate-300">
        We sent a verification link to <span class="font-medium text-slate-900 dark:text-white">
          {data.email}
        </span>
        . Open that email and verify your account before signing in.
      </p>

      {#if resendSuccess}
        <p class="mt-4 text-sm text-emerald-700 dark:text-emerald-400">{resendSuccess}</p>
      {/if}

      {#if resendError}
        <p class="mt-4 text-sm text-red-600 dark:text-red-400">{resendError}</p>
      {/if}

      <div class="mt-6">
        {#if remainingSeconds > 0}
          <p class="text-sm text-slate-500 dark:text-slate-400">
            You can request another email in {remainingSeconds}s.
          </p>
        {:else}
          <button
            type="button"
            on:click={resendVerification}
            disabled={isSubmitting}
            class="rounded-xl bg-slate-900 px-4 py-3 text-sm font-semibold text-white hover:bg-slate-700 disabled:cursor-not-allowed disabled:opacity-60 dark:bg-cyan-500 dark:text-slate-950"
          >
            {isSubmitting ? 'Sending...' : 'Resend verification email'}
          </button>
        {/if}
      </div>

      <a
        href="/login"
        class="mt-6 inline-block text-sm font-medium text-cyan-700 hover:text-cyan-900 dark:text-cyan-300 dark:hover:text-cyan-200"
      >
        Back to sign in
      </a>
    </div>
  </div>
</section>
