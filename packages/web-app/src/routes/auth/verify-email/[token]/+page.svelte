<script lang="ts">
  export let data;
</script>

<section class="min-h-screen bg-gray-50 dark:bg-gray-900">
  <div class="mx-auto flex min-h-screen max-w-xl items-center px-6 py-10">
    <div
      class="w-full rounded-3xl border border-slate-200 bg-white p-8 shadow-xl dark:border-slate-700 dark:bg-slate-800"
    >
      <p class="text-sm uppercase tracking-[0.3em] text-cyan-600 dark:text-cyan-300">Comcent</p>
      <h1 class="mt-4 text-3xl font-semibold text-slate-900 dark:text-white">
        Email verification failed.
      </h1>
      <p class="mt-4 text-sm text-slate-600 dark:text-slate-300">
        {data.error}
      </p>
      <a
        href="/login"
        class="mt-6 inline-block rounded-xl bg-slate-900 px-4 py-3 text-sm font-semibold text-white hover:bg-slate-700 dark:bg-cyan-500 dark:text-slate-950"
      >
        Back to sign in
      </a>
    </div>
  </div>
</section>
