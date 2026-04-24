<script lang="ts">
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import { getJson } from '$lib/http';

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

  let orgs: OrgSummary[] = [];
  let invites: OrgInviteSummary[] = [];
  let loading = false;

  onMount(() => {
    const storedSubdomain = localStorage.getItem('selectedSubdomain');
    if (storedSubdomain) {
      goto(`/app/${storedSubdomain}`, { invalidateAll: true });
    }

    void loadOrgData();
  });

  async function loadOrgData() {
    loading = true;
    const result = await getJson<{ orgs: OrgSummary[]; invites: OrgInviteSummary[] }>(
      '/api/v2/user/orgs',
    );
    if (!result.ok) {
      if (result.status === 401) {
        await goto('/login');
        return;
      }
      loading = false;
      return;
    }

    orgs = result.data.orgs ?? [];
    invites = result.data.invites ?? [];
    loading = false;
  }

  function handleOrgClick(subdomain: string) {
    localStorage.setItem('selectedSubdomain', subdomain);
  }
</script>

<div class="mx-auto max-w-4xl">
  <h3 class="text-3xl font-bold dark:text-white mb-5">Organizations</h3>

  {#if loading}
    <div
      class="p-4 mb-4 text-sm text-gray-800 rounded-lg bg-gray-50 dark:bg-gray-800 dark:text-gray-300"
    >
      Loading organizations...
    </div>
  {:else if !orgs.length}
    <div
      class="p-4 mb-4 text-sm text-yellow-800 rounded-lg bg-yellow-50 dark:bg-gray-800 dark:text-yellow-300"
      role="alert"
    >
      No organization found. Please create one.
    </div>
  {/if}

  {#each orgs as org}
    <a
      href={`/app/${org.subdomain}`}
      on:click={() => handleOrgClick(org.subdomain)}
      class="mb-5 block max-w-sm p-6 bg-white border border-gray-200 rounded-lg shadow hover:bg-gray-100 dark:bg-gray-800 dark:border-gray-700 dark:hover:bg-gray-700"
    >
      <h5 class="mb-2 text-2xl font-bold tracking-tight text-gray-900 dark:text-white">
        {org.name}
      </h5>
      <p class="font-normal text-gray-700 dark:text-gray-400">
        {org.subdomain}
      </p>
    </a>
  {/each}

  {#if orgs.length < 10}
    <a
      href="/org/create"
      class="text-white bg-blue-700 hover:bg-blue-800 focus:ring-4 focus:ring-blue-300 font-medium rounded-lg text-sm px-5 py-2.5 mr-2 mb-2 dark:bg-blue-600 dark:hover:bg-blue-700 focus:outline-none dark:focus:ring-blue-800"
    >
      Create Organization
    </a>
  {/if}

  {#if invites.length}
    <div class="mx-auto mt-8 max-w-4xl">
      <h3 class="text-3xl font-bold dark:text-white mb-5">Pending Invitations</h3>

      {#each invites as invite}
        <a
          href={`/invitation/${invite.id}`}
          class="mb-5 block max-w-sm p-6 bg-white border border-gray-200 rounded-lg shadow hover:bg-gray-100 dark:bg-gray-800 dark:border-gray-700 dark:hover:bg-gray-700"
        >
          <h5 class="mb-2 text-2xl font-bold tracking-tight text-gray-900 dark:text-white">
            {invite.org.name}
          </h5>
          <p class="font-normal text-gray-700 dark:text-gray-400">
            {invite.email}
          </p>
        </a>
      {/each}
    </div>
  {/if}

  <form method="POST" action="/logout" class="mt-5">
    <button
      type="submit"
      class="text-white bg-red-700 hover:bg-red-800 focus:ring-4 focus:ring-red-300 font-medium rounded-lg text-sm px-5 py-2.5 mr-2 mb-2 dark:bg-red-600 dark:hover:bg-red-700 focus:outline-none dark:focus:ring-red-800"
    >
      Logout
    </button>
  </form>
</div>
