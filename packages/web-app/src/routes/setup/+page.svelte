<script lang="ts">
  import { goto } from '$app/navigation';
  import { postJson } from '$lib/http';
  import { setSessionToken } from '$lib/session';

  let token = $state('');
  let name = $state('');
  let email = $state('');
  let password = $state('');
  let orgName = $state('');
  let subdomain = $state('');
  let sipUsername = $state('');
  let error = $state('');

  async function claim() {
    error = '';

    const result = await postJson<{ token: string }>('/api/v2/auth/claim-setup', {
      token,
      name,
      email,
      password,
      org_name: orgName,
      subdomain,
      sip_username: sipUsername,
    });
    if (!result.ok) {
      error = result.error;
      return;
    }

    setSessionToken(result.data.token);
    await goto('/app', { invalidateAll: true });
  }
</script>

<section class="min-h-screen bg-gray-50 dark:bg-gray-900">
  <div class="mx-auto flex min-h-screen max-w-5xl items-center px-6 py-10">
    <div class="grid w-full gap-8 md:grid-cols-[1.2fr_0.8fr]">
      <div class="rounded-3xl bg-slate-900 p-10 text-white shadow-2xl">
        <p class="text-sm uppercase tracking-[0.3em] text-cyan-300">Comcent</p>
        <h1 class="mt-4 text-4xl font-semibold leading-tight">Claim this instance.</h1>
        <p class="mt-4 max-w-xl text-sm text-slate-300">
          This Comcent install has no super-admin yet. The first person to enter the setup token
          (printed in the server logs on startup) will become the super-admin and create the initial
          organization. After that, signup is invite-only.
        </p>
        <p class="mt-4 max-w-xl text-xs text-slate-400">
          Lost the token? On the server host, run
          <code class="rounded bg-slate-800 px-1.5 py-0.5">mix comcent.reset_setup_token</code>
          .
        </p>
      </div>

      <div
        class="rounded-3xl border border-slate-200 bg-white p-8 shadow-xl dark:border-slate-700 dark:bg-slate-800"
      >
        <form
          method="POST"
          class="space-y-4"
          onsubmit={(e) => {
            e.preventDefault();
            claim();
          }}
        >
          <div>
            <label
              for="setup-token"
              class="mb-2 block text-sm font-medium text-slate-700 dark:text-slate-200"
            >
              Setup token
            </label>
            <input
              id="setup-token"
              bind:value={token}
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
              bind:value={name}
              name="name"
              type="text"
              required
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
              bind:value={email}
              name="email"
              type="email"
              required
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
              bind:value={password}
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
                  bind:value={orgName}
                  name="orgName"
                  type="text"
                  required
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
                  bind:value={subdomain}
                  name="subdomain"
                  type="text"
                  required
                  pattern="[a-z0-9][a-z0-9-]*"
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
                  bind:value={sipUsername}
                  name="sipUsername"
                  type="text"
                  required
                  class="block w-full rounded-xl border border-slate-300 px-4 py-3 text-sm focus:border-cyan-500 focus:outline-none dark:border-slate-600 dark:bg-slate-900 dark:text-white"
                />
              </div>
            </div>
          </div>

          {#if error}
            <p class="text-sm text-red-600 dark:text-red-400">{error}</p>
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
