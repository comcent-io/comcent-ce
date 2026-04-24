<script lang="ts">
  import { browser } from '$app/environment';
  import { page } from '$app/stores';
  import { getJson, postJson, putJson } from '$lib/http';
  import ErrorMessage from '$lib/components/ErrorMessage.svelte';
  import ClipBoardCopyIcon from '$lib/components/Icons/ClipBoardCopyIcon.svelte';
  import type { Roles } from '../../roleSchema';

  type PageError = { message: string; formErrors: { message: string; path: string[] }[] };
  let member: any = null;
  let role: Roles = 'MEMBER';
  let error: PageError | null = null;
  let isLoading = false;
  let lastFetchKey = '';

  async function fetchMember() {
    const result = await getJson<any>(
      `/api/v2/${$page.params.subdomain}/admin/members/${$page.params.id}`,
    );
    if (!result.ok) {
      error = { message: result.error, formErrors: [] };
      member = null;
      return;
    }

    member = result.data;
    role = result.data.role;
    error = null;
  }

  async function regeneratePassword() {
    isLoading = true;
    const result = await postJson<any>(
      `/api/v2/${$page.params.subdomain}/admin/members/${$page.params.id}/regenerate-password`,
      {},
    );

    if (!result.ok) {
      error = { message: result.error, formErrors: [] };
      isLoading = false;
      return;
    }

    await fetchMember();
    error = null;
    isLoading = false;
  }

  async function updateRole() {
    isLoading = true;
    const result = await putJson<any>(
      `/api/v2/${$page.params.subdomain}/admin/members/${$page.params.id}/role`,
      { role },
    );

    if (!result.ok) {
      error = { message: result.error, formErrors: [] };
      isLoading = false;
      return;
    }

    member = { ...member, role };
    error = null;
    isLoading = false;
  }

  $: if (browser) {
    const nextFetchKey = `${$page.params.subdomain}|${$page.params.id}`;
    if (nextFetchKey !== lastFetchKey) {
      lastFetchKey = nextFetchKey;
      fetchMember();
    }
  }
</script>

<h3 class="text-3xl font-bold dark:text-white">Edit Member</h3>

<div class="m-5">
  {#if error}
    <ErrorMessage {error} />
  {/if}
  {#if member}
    <div
      class="max-w-sm p-6 bg-white border border-gray-200 rounded-lg shadow dark:bg-gray-800 dark:border-gray-700 mt-4 mb-2"
    >
      <h5 class="mb-2 text-xl font-bold tracking-tight text-gray-900 dark:text-white">
        {member.user.name} ({member.role})
      </h5>
      <p class="mb-3 font-normal text-gray-700 dark:text-gray-400">
        Email: {member.user.email}
      </p>
      <p class="mb-3 font-normal text-gray-700 dark:text-gray-400 dark:bg-gray-800">
        Sip username: {member.username}
      </p>
      <div class="flex">
        <input
          type="password"
          autocomplete="off"
          class="rounded-none rounded-l-lg bg-gray-300 border text-gray-900 focus:ring-blue-500 focus:border-blue-500 block flex-1 min-w-0 w-2 text-sm border-gray-300 p-2.5 dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500"
          value={member.sipPassword}
        />
        <button
          on:click={() => navigator.clipboard.writeText(member.sipPassword)}
          class="dark:text-gray-400 dark:border-gray-600 border border-l-0 border-gray-300 rounded-r-md px-3 text-gray-900 bg-gray-200 hover:bg-gray-300 focus:ring-4 focus:outline-none focus:ring-blue-300 font-medium text-sm p-2.5 text-center inline-flex items-center mr-2 dark:bg-blue-600 dark:hover:bg-blue-700 dark:focus:ring-blue-800"
        >
          <ClipBoardCopyIcon />
        </button>
      </div>
    </div>
    <form on:submit|preventDefault={regeneratePassword}>
      <button
        type="submit"
        disabled={isLoading}
        class="dark:text-white mt-4 dark:border-gray-600 border border-l-0 border-gray-300 px-3 text-gray-900 bg-gray-200 hover:bg-gray-300 focus:ring-4 focus:outline-none focus:ring-blue-300 font-medium text-sm p-2.5 text-center inline-flex items-center mr-2 dark:bg-blue-600 dark:hover:bg-blue-700 dark:focus:ring-blue-800 rounded-md"
      >
        Regenerate password
      </button>
    </form>
  {/if}
</div>
{#if member}
  <form on:submit|preventDefault={updateRole}>
    <label for="role" class="mb-2 text-sm font-medium text-gray-900 dark:text-white">
      Edit Role
    </label>
    <select
      id="role"
      name="role"
      bind:value={role}
      class="bg-gray-50 border border-gray-300 text-gray-900 text-sm rounded-lg focus:ring-blue-500 focus:border-blue-500 inline-block p-2.5 dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500"
    >
      <option value="ADMIN">ADMIN</option>
      <option value="MEMBER">MEMBER</option>
    </select>
    <button
      type="submit"
      disabled={isLoading}
      class="text-white bg-blue-700 hover:bg-blue-800 focus:ring-4 focus:outline-none focus:ring-blue-300 font-medium rounded-lg text-sm px-5 py-2.5 text-center dark:bg-blue-600 dark:hover:bg-blue-700 dark:focus:ring-blue-800"
    >
      Update
    </button>
  </form>
{/if}
