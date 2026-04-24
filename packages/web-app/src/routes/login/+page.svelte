<script lang="ts">
  export let data;
  export let form;

  let mode: 'login' | 'register' = 'login';

  $: if (form?.registerError) {
    mode = 'register';
  } else if (form?.loginError) {
    mode = 'login';
  }
</script>

<section class="min-h-screen bg-gray-50 dark:bg-gray-900">
  <div class="mx-auto flex min-h-screen max-w-5xl items-center px-6 py-10">
    <div class="grid w-full gap-8 md:grid-cols-[1.2fr_0.8fr]">
      <div class="rounded-3xl bg-slate-900 p-10 text-white shadow-2xl">
        <p class="text-sm uppercase tracking-[0.3em] text-cyan-300">Comcent</p>
        <h1 class="mt-4 text-4xl font-semibold leading-tight">Sign in to Comcent.</h1>
        <p class="mt-4 max-w-xl text-sm text-slate-300">
          Use your email and password or continue with any sign-in provider enabled by your
          workspace.
        </p>
      </div>

      <div
        class="rounded-3xl border border-slate-200 bg-white p-8 shadow-xl dark:border-slate-700 dark:bg-slate-800"
      >
        <div class="mb-6 flex gap-2 rounded-2xl bg-slate-100 p-1 dark:bg-slate-900">
          <button
            type="button"
            class={`flex-1 rounded-xl px-4 py-2 text-sm font-medium ${
              mode === 'login'
                ? 'bg-white text-slate-900 shadow dark:bg-slate-700 dark:text-white'
                : 'text-slate-500 dark:text-slate-300'
            }`}
            on:click={() => (mode = 'login')}
          >
            Sign in
          </button>
          <button
            type="button"
            class={`flex-1 rounded-xl px-4 py-2 text-sm font-medium ${
              mode === 'register'
                ? 'bg-white text-slate-900 shadow dark:bg-slate-700 dark:text-white'
                : 'text-slate-500 dark:text-slate-300'
            }`}
            on:click={() => (mode = 'register')}
          >
            Create account
          </button>
        </div>

        {#if mode === 'login'}
          <form method="POST" action="?/login" class="space-y-4">
            <div>
              <label
                for="login-email"
                class="mb-2 block text-sm font-medium text-slate-700 dark:text-slate-200"
              >
                Email address
              </label>
              <input
                id="login-email"
                name="email"
                type="email"
                required
                class="block w-full rounded-xl border border-slate-300 px-4 py-3 text-sm focus:border-cyan-500 focus:outline-none dark:border-slate-600 dark:bg-slate-900 dark:text-white"
              />
            </div>
            <div>
              <label
                for="login-password"
                class="mb-2 block text-sm font-medium text-slate-700 dark:text-slate-200"
              >
                Password
              </label>
              <input
                id="login-password"
                name="password"
                type="password"
                required
                class="block w-full rounded-xl border border-slate-300 px-4 py-3 text-sm focus:border-cyan-500 focus:outline-none dark:border-slate-600 dark:bg-slate-900 dark:text-white"
              />
            </div>
            {#if form?.loginError}
              <p class="text-sm text-red-600 dark:text-red-400">{form.loginError}</p>
            {/if}
            <button
              type="submit"
              class="w-full rounded-xl bg-slate-900 px-4 py-3 text-sm font-semibold text-white hover:bg-slate-700 dark:bg-cyan-500 dark:text-slate-950"
            >
              Continue
            </button>
          </form>
        {:else if data.authConfig.passwordEnabled}
          <form method="POST" action="?/register" class="space-y-4">
            <div>
              <label
                for="register-name"
                class="mb-2 block text-sm font-medium text-slate-700 dark:text-slate-200"
              >
                Full name
              </label>
              <input
                id="register-name"
                name="name"
                type="text"
                required
                class="block w-full rounded-xl border border-slate-300 px-4 py-3 text-sm focus:border-cyan-500 focus:outline-none dark:border-slate-600 dark:bg-slate-900 dark:text-white"
              />
            </div>
            <div>
              <label
                for="register-email"
                class="mb-2 block text-sm font-medium text-slate-700 dark:text-slate-200"
              >
                Email address
              </label>
              <input
                id="register-email"
                name="email"
                type="email"
                required
                class="block w-full rounded-xl border border-slate-300 px-4 py-3 text-sm focus:border-cyan-500 focus:outline-none dark:border-slate-600 dark:bg-slate-900 dark:text-white"
              />
            </div>
            <div>
              <label
                for="register-password"
                class="mb-2 block text-sm font-medium text-slate-700 dark:text-slate-200"
              >
                Password
              </label>
              <input
                id="register-password"
                name="password"
                type="password"
                required
                class="block w-full rounded-xl border border-slate-300 px-4 py-3 text-sm focus:border-cyan-500 focus:outline-none dark:border-slate-600 dark:bg-slate-900 dark:text-white"
              />
            </div>
            {#if form?.registerError}
              <p class="text-sm text-red-600 dark:text-red-400">{form.registerError}</p>
            {/if}
            <button
              type="submit"
              class="w-full rounded-xl bg-slate-900 px-4 py-3 text-sm font-semibold text-white hover:bg-slate-700 dark:bg-cyan-500 dark:text-slate-950"
            >
              Create account
            </button>
          </form>
        {/if}

        {#if data.authConfig.oauthProviders.length > 0}
          <div class="my-6 flex items-center gap-3">
            <div class="h-px flex-1 bg-slate-200 dark:bg-slate-700"></div>
            <span class="text-xs font-semibold uppercase tracking-[0.3em] text-slate-400">or</span>
            <div class="h-px flex-1 bg-slate-200 dark:bg-slate-700"></div>
          </div>

          <div class="space-y-3">
            {#each data.authConfig.oauthProviders as provider}
              <a
                href={`/auth/oauth/${provider.id}`}
                class="block rounded-xl border border-slate-300 px-4 py-3 text-center text-sm font-medium text-slate-700 hover:border-slate-500 hover:text-slate-950 dark:border-slate-600 dark:text-slate-200 dark:hover:border-slate-400 dark:hover:text-white"
              >
                Continue with {provider.label}
              </a>
            {/each}
          </div>
        {/if}
      </div>
    </div>
  </div>
</section>
