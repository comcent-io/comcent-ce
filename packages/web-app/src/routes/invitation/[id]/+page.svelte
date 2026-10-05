<script lang="ts">
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import { page } from '$app/state';
  import { getJson, postJson } from '$lib/http';
  import { logout } from '$lib/session';
  import AccountAlert from '$lib/components/account/AccountAlert.svelte';
  import AccountButton from '$lib/components/account/AccountButton.svelte';
  import AccountPage from '$lib/components/account/AccountPage.svelte';
  import SipUsernameField from '$lib/components/account/SipUsernameField.svelte';
  import { invitationFormData } from '../schema';

  type InvitationData = {
    id: string;
    email: string;
    role: 'ADMIN' | 'MEMBER' | string;
    org: { id: string; name: string; subdomain: string };
  };

  let { data } = $props();

  let invitation = $state<InvitationData | null>(null);
  // Not found for this user: accepted, withdrawn, or sent to another address.
  let unavailable = $state(false);
  let loadError = $state('');
  let loading = $state(true);

  let username = $state('');
  let usernameError = $state('');
  let acceptError = $state('');
  let saving = $state(false);

  onMount(() => {
    void loadInvitation();
  });

  async function loadInvitation() {
    loading = true;
    const result = await getJson<{ invitation: InvitationData; suggestedUsername: string }>(
      `/api/v2/user/invitations/${page.params.id}`,
    );
    loading = false;

    if (!result.ok) {
      if (result.status === 401) {
        await goto('/login');
      } else if (result.status === 404) {
        unavailable = true;
      } else {
        loadError = result.error;
      }
      return;
    }

    invitation = result.data.invitation;
    username = result.data.suggestedUsername || '';
  }

  async function acceptInvitation(event: SubmitEvent) {
    event.preventDefault();
    if (!invitation || saving) return;

    acceptError = '';
    const parsed = invitationFormData.safeParse({ username: username.trim() });
    if (!parsed.success) {
      usernameError = parsed.error.issues[0].message;
      return;
    }

    saving = true;
    const result = await postJson(`/api/v2/user/invitations/${page.params.id}/accept`, {
      username: parsed.data.username,
    });

    if (!result.ok) {
      saving = false;
      if (result.status === 401) {
        await goto('/login');
        return;
      }
      // "Username … already taken for this org" and the like belong under
      // the field; anything else above the form.
      if (result.error.startsWith('Username')) usernameError = result.error;
      else acceptError = result.error;
      return;
    }

    // Into the org just joined (its layout remembers it as the last used).
    await goto(`/app/${invitation.org.subdomain}`, { invalidateAll: true });
  }

  let roleText = $derived(invitation?.role === 'ADMIN' ? 'an admin' : 'a member');
</script>

<AccountPage email={data.user?.email}>
  {#if loading}
    <div class="mt-10 space-y-4" aria-busy="true">
      <div class="h-8 w-72 animate-pulse rounded-lg bg-slate-200 dark:bg-slate-700"></div>
      <div class="h-56 max-w-xl animate-pulse rounded-3xl bg-slate-200 dark:bg-slate-700"></div>
    </div>
  {:else if unavailable}
    <h1 class="mt-10 text-3xl font-semibold text-slate-900 dark:text-white">
      This invitation can't be used
    </h1>
    <p class="mt-3 max-w-xl text-sm leading-6 text-slate-600 dark:text-slate-300">
      It may already have been accepted, or the organization withdrew it.
    </p>
    <!-- Unformatted: wrapping puts a space before the full stop. -->
    <!-- prettier-ignore -->
    <p class="mt-2 max-w-xl text-sm leading-6 text-slate-600 dark:text-slate-300">
      Or it was sent to another address: only the invited address can open it, and you're signed in as <span class="font-medium text-slate-900 dark:text-white">{data.user?.email ?? 'another account'}</span>.
    </p>
    <div class="mt-8 flex flex-wrap gap-3">
      <a
        href="/org"
        class="inline-flex items-center justify-center rounded-xl bg-slate-900 px-5 py-3 text-sm font-semibold text-white hover:bg-slate-700 dark:bg-cyan-500 dark:text-slate-950 dark:hover:bg-cyan-400"
      >
        Your organizations
      </a>
      <button
        type="button"
        onclick={logout}
        class="inline-flex items-center justify-center rounded-xl border border-slate-300 px-5 py-3 text-sm font-medium text-slate-700 hover:bg-white dark:border-slate-600 dark:text-slate-200 dark:hover:bg-slate-800"
      >
        Sign in with another account
      </button>
    </div>
  {:else if loadError}
    <div class="mt-10 max-w-xl">
      <AccountAlert>
        The invitation couldn't be loaded: {loadError}
        <button type="button" class="ml-1 font-semibold underline" onclick={loadInvitation}>
          Try again
        </button>
      </AccountAlert>
    </div>
  {:else if invitation}
    <p class="mt-10 text-sm font-semibold uppercase tracking-wider text-slate-400">Invitation</p>
    <h1 class="mt-2 text-3xl font-semibold text-slate-900 dark:text-white">
      Join {invitation.org.name} on Comcent
    </h1>
    <p class="mt-3 max-w-xl text-sm leading-6 text-slate-600 dark:text-slate-300">
      You're invited as {roleText}. You'll take and make calls with the rest of the team{invitation.role ===
      'ADMIN'
        ? ', and manage its numbers and members'
        : ''}.
    </p>

    <form
      method="POST"
      novalidate
      onsubmit={acceptInvitation}
      class="mt-8 max-w-xl space-y-6 rounded-3xl border border-slate-200 bg-white p-6 shadow-xl sm:p-8 dark:border-slate-700 dark:bg-slate-800"
    >
      {#if acceptError}
        <AccountAlert>{acceptError}</AccountAlert>
      {/if}

      <SipUsernameField
        bind:value={username}
        subdomain={invitation.org.subdomain}
        error={usernameError}
        oninput={() => (usernameError = '')}
      />

      <div class="space-y-3">
        <AccountButton progress={saving}>Join {invitation.org.name}</AccountButton>
        <a
          href="/org"
          class="block text-center text-sm text-slate-500 hover:text-slate-900 dark:text-slate-400 dark:hover:text-white"
        >
          Not now
        </a>
      </div>
    </form>
  {/if}
</AccountPage>
