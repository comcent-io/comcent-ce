<script lang="ts">
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import { getJson } from '$lib/http';
  import { getLastOrg } from '$lib/lastOrg';
  import { publicSipUserRootDomain } from '$lib/publicConfig';
  import AccountPage from '$lib/components/account/AccountPage.svelte';

  type OrgSummary = {
    id: string;
    name: string;
    subdomain: string;
  };

  type OrgInviteSummary = {
    id: string;
    email: string;
    org: OrgSummary;
  };

  let { data } = $props();

  // How many orgs one person can create or join.
  const MAX_ORGS = 10;

  let orgs: OrgSummary[] = $state([]);
  let invites: OrgInviteSummary[] = $state([]);
  let loading = $state(true);
  let failed = $state(false);
  // This page only lists: reopening the last used org is the /app entry
  // point's job, so the list can always be reached. It's marked here.
  let lastOrg: string | null = $state(null);

  let firstName = $derived((data.user?.name ?? '').trim().split(/\s+/)[0] ?? '');

  onMount(() => {
    lastOrg = getLastOrg();
    void loadOrgData();
  });

  async function loadOrgData() {
    loading = true;
    failed = false;
    const result = await getJson<{ orgs: OrgSummary[]; invites: OrgInviteSummary[] }>(
      '/api/v2/user/orgs',
    );
    if (!result.ok) {
      if (result.status === 401) {
        await goto('/login');
        return;
      }
      failed = true;
      loading = false;
      return;
    }

    // The last used org first, the rest as the server sorts them (by name).
    const all = result.data.orgs ?? [];
    orgs = [
      ...all.filter((org) => org.subdomain === lastOrg),
      ...all.filter((org) => org.subdomain !== lastOrg),
    ];
    invites = result.data.invites ?? [];
    loading = false;
  }

  const cardClass =
    'group rounded-2xl border border-slate-200 bg-white p-5 shadow-sm transition hover:border-cyan-500 hover:shadow-md dark:border-slate-700 dark:bg-slate-800';
  const primaryButtonClass =
    'inline-flex items-center justify-center rounded-xl bg-slate-900 px-5 py-3 text-sm font-semibold text-white hover:bg-slate-700 dark:bg-cyan-500 dark:text-slate-950 dark:hover:bg-cyan-400';
</script>

{#snippet inviteCard(invite: OrgInviteSummary)}
  <a href={`/invitation/${invite.id}`} class={cardClass}>
    <p class="text-lg font-semibold text-slate-900 dark:text-white">{invite.org.name}</p>
    <p class="mt-1 text-sm text-slate-500 dark:text-slate-400">Invitation for {invite.email}</p>
    <p class="mt-4 text-sm font-medium text-cyan-700 group-hover:underline dark:text-cyan-300">
      View invitation →
    </p>
  </a>
{/snippet}

<AccountPage email={data.user?.email}>
  {#if loading}
    <div class="mt-10 space-y-4" aria-busy="true">
      <div class="h-8 w-64 animate-pulse rounded-lg bg-slate-200 dark:bg-slate-700"></div>
      <div class="grid gap-4 sm:grid-cols-2">
        <div class="h-32 animate-pulse rounded-2xl bg-slate-200 dark:bg-slate-700"></div>
        <div class="h-32 animate-pulse rounded-2xl bg-slate-200 dark:bg-slate-700"></div>
      </div>
    </div>
  {:else if failed}
    <div
      class="mt-10 rounded-2xl border border-red-200 bg-red-50 p-5 text-sm text-red-700 dark:border-red-900 dark:bg-red-950 dark:text-red-300"
      role="alert"
    >
      Your organizations couldn't be loaded.
      <button type="button" class="ml-1 font-semibold underline" onclick={loadOrgData}>
        Try again
      </button>
    </div>
  {:else if orgs.length === 0}
    <!-- Just signed up, or not in any org yet: say what this page is. -->
    <h1 class="mt-10 text-3xl font-semibold text-slate-900 dark:text-white">
      {#if invites.length}
        You've been invited to Comcent
      {:else}
        Welcome to Comcent{firstName ? `, ${firstName}` : ''}
      {/if}
    </h1>
    <!-- These three sentences are left unformatted: wrapping them puts a space
           between a highlighted word and the punctuation after it. -->
    <!-- prettier-ignore -->
    <p class="mt-3 max-w-2xl text-sm leading-6 text-slate-600 dark:text-slate-300">
        Everything in Comcent belongs to an <strong>organization</strong>: your company's workspace.
        Its phone numbers, team members, call recordings and voice bots live there,
        shared by everyone in it. To start, create one for your company or join your team's.
      </p>

    {#if invites.length}
      <h2 class="mt-8 text-sm font-semibold uppercase tracking-wider text-slate-400">
        Waiting for you
      </h2>
      <div class="mt-3 grid gap-4 sm:grid-cols-2">
        {#each invites as invite (invite.id)}
          {@render inviteCard(invite)}
        {/each}
      </div>
    {/if}

    <div class="mt-8 grid gap-4 sm:grid-cols-2">
      <div
        class="flex flex-col rounded-3xl border border-slate-200 bg-white p-6 shadow-xl dark:border-slate-700 dark:bg-slate-800"
      >
        <h2 class="text-lg font-semibold text-slate-900 dark:text-white">
          {invites.length ? 'Or set up your own company' : 'Set up your company'}
        </h2>
        <!-- prettier-ignore -->
        <p class="mt-2 flex-1 text-sm leading-6 text-slate-600 dark:text-slate-300">
            Create an organization and you're its admin. It gets its own address, like
            <span class="font-medium text-slate-900 dark:text-white">acme.{publicSipUserRootDomain}</span>,
            and you can invite your team to it.
          </p>
        <a href="/org/create" class="{primaryButtonClass} mt-5">Create Organization</a>
      </div>

      <!-- With an invitation above, joining is already on the page. -->
      {#if !invites.length}
        <div
          class="flex flex-col rounded-3xl border border-dashed border-slate-300 p-6 dark:border-slate-600"
        >
          <h2 class="text-lg font-semibold text-slate-900 dark:text-white">Joining your team?</h2>
          <!-- prettier-ignore -->
          <p class="mt-2 text-sm leading-6 text-slate-600 dark:text-slate-300">
              If your company already uses Comcent, don't create another organization. Ask one of its
              admins to invite
              <span class="font-medium text-slate-900 dark:text-white">{data.user?.email ?? 'your email'}</span>.
              The invitation shows up on this page.
            </p>
        </div>
      {/if}
    </div>

    <div class="mt-10">
      <h2 class="text-sm font-semibold uppercase tracking-wider text-slate-400">
        After you create one
      </h2>
      <ol class="mt-4 grid gap-3 sm:grid-cols-2">
        {#each ['Create your organization', 'Connect your own carrier and add a phone number', 'Invite your team and start taking calls'] as step, index (step)}
          <li class="flex items-start gap-3 text-sm text-slate-600 dark:text-slate-300">
            <span
              class="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-cyan-100 text-xs font-semibold text-cyan-800 dark:bg-cyan-900 dark:text-cyan-200"
            >
              {index + 1}
            </span>
            <span class="pt-0.5">{step}</span>
          </li>
        {/each}
      </ol>
    </div>
  {:else}
    <h1 class="mt-10 text-3xl font-semibold text-slate-900 dark:text-white">Your organizations</h1>
    <p class="mt-2 text-sm text-slate-500 dark:text-slate-400">
      Each organization is a separate workspace with its own numbers and team. Pick the one to work
      in.
    </p>

    <div class="mt-8 grid gap-4 sm:grid-cols-2">
      {#each orgs as org (org.id)}
        <a href={`/app/${org.subdomain}`} class={cardClass}>
          <div class="flex items-start justify-between gap-3">
            <p class="text-lg font-semibold text-slate-900 dark:text-white">{org.name}</p>
            {#if org.subdomain === lastOrg}
              <span
                class="shrink-0 rounded-full bg-cyan-50 px-2.5 py-0.5 text-xs font-medium text-cyan-800 dark:bg-cyan-950 dark:text-cyan-200"
              >
                Last used
              </span>
            {/if}
          </div>
          <p class="mt-1 text-sm text-slate-500 dark:text-slate-400">
            {org.subdomain}.{publicSipUserRootDomain}
          </p>
          <p
            class="mt-4 text-sm font-medium text-cyan-700 group-hover:underline dark:text-cyan-300"
          >
            Open →
          </p>
        </a>
      {/each}

      {#if orgs.length < MAX_ORGS}
        <a
          href="/org/create"
          class="flex min-h-32 flex-col items-center justify-center rounded-2xl border-2 border-dashed border-slate-300 p-5 text-center text-slate-600 transition hover:border-cyan-500 hover:text-slate-900 dark:border-slate-600 dark:text-slate-300 dark:hover:text-white"
        >
          <span class="text-2xl leading-none">+</span>
          <span class="mt-2 text-sm font-semibold">Create Organization</span>
          <span class="mt-1 text-xs text-slate-500 dark:text-slate-400">
            For another company or team
          </span>
        </a>
      {/if}
    </div>

    {#if invites.length}
      <h2 class="mt-12 text-lg font-semibold text-slate-900 dark:text-white">
        Pending invitations
      </h2>
      <div class="mt-4 grid gap-4 sm:grid-cols-2">
        {#each invites as invite (invite.id)}
          {@render inviteCard(invite)}
        {/each}
      </div>
    {/if}
  {/if}
</AccountPage>
