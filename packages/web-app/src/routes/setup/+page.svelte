<script lang="ts">
  export let form;
  $: values = form?.values ?? {};
</script>

<section class="min-h-screen bg-gray-50 dark:bg-gray-900">
  <div class="mx-auto flex min-h-screen max-w-5xl items-center px-6 py-10">
    <div class="grid w-full gap-8 md:grid-cols-[1.2fr_0.8fr]">
      <div class="rounded-3xl bg-slate-900 p-10 text-white shadow-2xl">
        <p class="text-sm uppercase tracking-[0.3em] text-cyan-300">Comcent</p>
        <h1 class="mt-4 text-4xl font-semibold leading-tight">Claim this instance.</h1>
        <p class="mt-4 max-w-xl text-sm text-slate-300">
          This Comcent install has no super-admin yet. The first person to enter the setup token
          (printed in the server logs on startup) will become the super-admin and create the
          initial organization. After that, signup is invite-only.
        </p>
        <p class="mt-4 max-w-xl text-xs text-slate-400">
          Lost the token? On the server host, run
          <code class="rounded bg-slate-800 px-1.5 py-0.5">mix comcent.reset_setup_token</code>.
        </p>
      </div>

      <div
        class="rounded-3xl border border-slate-200 bg-white p-8 shadow-xl dark:border-slate-700 dark:bg-slate-800"
      >
        <form method="POST" action="?/claim" class="space-y-4">
          <div>
            <label
              for="setup-token"
              class="mb-2 block text-sm font-medium text-slate-700 dark:text-slate-200"
            >
              Setup token
            </label>
            <input
              id="setup-token"
              name="token"
              type="text"
              required
              autocomplete="off"
              class="block w-full rounded-xl border border-slate-300 px-4 py-3 font-mono text-sm focus:border-cyan-500 focus:outline-none dark:border-slate-600 dark:bg-slate-900 dark:text-white"
            />
          </div>

          <div>
            <label
              for="setup-name"
              class="mb-2 block text-sm font-medium text-slate-700 dark:text-slate-200"
            >
              Your full name
            </label>
            <input
              id="setup-name"
              name="name"
              type="text"
              required
              value={values.name ?? ''}
              class="block w-full rounded-xl border border-slate-300 px-4 py-3 text-sm focus:border-cyan-500 focus:outline-none dark:border-slate-600 dark:bg-slate-900 dark:text-white"
            />
          </div>

          <div>
            <label
              for="setup-email"
              class="mb-2 block text-sm font-medium text-slate-700 dark:text-slate-200"
            >
              Email address
            </label>
            <input
              id="setup-email"
              name="email"
              type="email"
              required
              value={values.email ?? ''}
              class="block w-full rounded-xl border border-slate-300 px-4 py-3 text-sm focus:border-cyan-500 focus:outline-none dark:border-slate-600 dark:bg-slate-900 dark:text-white"
            />
          </div>

          <div>
            <label
              for="setup-password"
              class="mb-2 block text-sm font-medium text-slate-700 dark:text-slate-200"
            >
              Password (8+ characters)
            </label>
            <input
              id="setup-password"
              name="password"
              type="password"
              required
              minlength="8"
              class="block w-full rounded-xl border border-slate-300 px-4 py-3 text-sm focus:border-cyan-500 focus:outline-none dark:border-slate-600 dark:bg-slate-900 dark:text-white"
            />
          </div>

          <div class="border-t border-slate-200 pt-4 dark:border-slate-700">
            <p class="mb-3 text-sm font-medium text-slate-600 dark:text-slate-300">
              Organization details
            </p>

            <div class="space-y-4">
              <div>
                <label
                  for="setup-org-name"
                  class="mb-2 block text-sm font-medium text-slate-700 dark:text-slate-200"
                >
                  Organization name
                </label>
                <input
                  id="setup-org-name"
                  name="orgName"
                  type="text"
                  required
                  value={values.orgName ?? ''}
                  class="block w-full rounded-xl border border-slate-300 px-4 py-3 text-sm focus:border-cyan-500 focus:outline-none dark:border-slate-600 dark:bg-slate-900 dark:text-white"
                />
              </div>

              <div>
                <label
                  for="setup-subdomain"
                  class="mb-2 block text-sm font-medium text-slate-700 dark:text-slate-200"
                >
                  Subdomain (used in URLs and SIP addresses)
                </label>
                <input
                  id="setup-subdomain"
                  name="subdomain"
                  type="text"
                  required
                  pattern="[a-z0-9][a-z0-9-]*"
                  value={values.subdomain ?? ''}
                  class="block w-full rounded-xl border border-slate-300 px-4 py-3 text-sm focus:border-cyan-500 focus:outline-none dark:border-slate-600 dark:bg-slate-900 dark:text-white"
                />
              </div>

              <div>
                <label
                  for="setup-sip-username"
                  class="mb-2 block text-sm font-medium text-slate-700 dark:text-slate-200"
                >
                  Your SIP username inside the org
                </label>
                <input
                  id="setup-sip-username"
                  name="sipUsername"
                  type="text"
                  required
                  value={values.sipUsername ?? ''}
                  class="block w-full rounded-xl border border-slate-300 px-4 py-3 text-sm focus:border-cyan-500 focus:outline-none dark:border-slate-600 dark:bg-slate-900 dark:text-white"
                />
              </div>
            </div>
          </div>

          {#if form?.error}
            <p class="text-sm text-red-600 dark:text-red-400">{form.error}</p>
          {/if}

          <button
            type="submit"
            class="w-full rounded-xl bg-slate-900 px-4 py-3 text-sm font-semibold text-white hover:bg-slate-700 dark:bg-cyan-500 dark:text-slate-950"
          >
            Claim instance
          </button>
        </form>
      </div>
    </div>
  </div>
</section>
