<script lang="ts">
  import { browser } from '$app/environment';
  import { page } from '$app/stores';
  import { getJson, postJson } from '$lib/http';
  import Pagination from '$lib/components/Pagination.svelte';
  import toast from 'svelte-french-toast';
  import Button from '$lib/components/Button.svelte';
  import CopyIcon from '$lib/components/Icons/CopyIcon.svelte';

  type Member = {
    user: { name: string; email: string; id: string };
    username: string;
    sipPassword: string;
    extensionNumber: string;
    role: string;
  };

  type PendingInvite = {
    id: string;
    email: string;
    role: string;
    status: string;
    createdAt: string;
    inviteEmailSentAt: string | null;
    inviteResendCount: number;
  };

  let showInviteForm = false;
  let activeView: 'members' | 'pending-invites' = 'members';

  export let data;
  let members: Member[] = [];
  let pendingInvites: PendingInvite[] = [];
  let currentPage = 1;
  let itemsPerPage = 10;
  let orgMemberCount = 0;
  let pendingInviteCount = 0;
  let totalPages = 0;
  let allowMemberInvite = false;
  let isLoading = false;
  let userEmail = '';
  let userRole = '';
  let inviteInProgress = false;
  let resendInProgressInviteId: string | null = null;
  let latestRequestId = 0;
  let lastFetchKey = '';

  async function fetchMembers() {
    const requestId = ++latestRequestId;
    isLoading = true;
    const searchParams = $page.url.searchParams;
    const requestedPage = parseInt(searchParams.get('page') || '1', 10);
    const requestedItemsPerPage = parseInt(searchParams.get('itemsPerPage') || '10', 10);

    const result = await getJson<{
      members?: Member[];
      pendingInvites?: PendingInvite[];
      currentPage?: number;
      itemsPerPage?: number;
      memberCount?: number;
      pendingInviteCount?: number;
      totalPages?: number;
      allowMemberInvite?: boolean;
    }>(
      `/api/v2/${$page.params.subdomain}/admin/members?page=${requestedPage}&itemsPerPage=${requestedItemsPerPage}`,
    );

    if (requestId !== latestRequestId) return;

    currentPage = requestedPage;
    itemsPerPage = requestedItemsPerPage;

    if (!result.ok) {
      members = [];
      pendingInvites = [];
      orgMemberCount = 0;
      pendingInviteCount = 0;
      totalPages = 0;
      allowMemberInvite = false;
      isLoading = false;
      toast.error(result.error || 'Failed to fetch members');
      return;
    }

    members = result.data.members ?? [];
    pendingInvites = result.data.pendingInvites ?? [];
    currentPage = result.data.currentPage ?? requestedPage;
    itemsPerPage = result.data.itemsPerPage ?? requestedItemsPerPage;
    orgMemberCount = result.data.memberCount ?? 0;
    pendingInviteCount = result.data.pendingInviteCount ?? 0;
    totalPages = result.data.totalPages ?? 0;
    allowMemberInvite = result.data.allowMemberInvite ?? false;
    isLoading = false;
  }

  $: if (browser) {
    const nextFetchKey = `${$page.url.search}|${$page.params.subdomain}`;
    if (nextFetchKey !== lastFetchKey) {
      lastFetchKey = nextFetchKey;
      fetchMembers();
    }
  }

  async function inviteUser() {
    inviteInProgress = true;
    const result = await postJson(`/api/v2/${$page.params.subdomain}/members/invite`, {
      email: userEmail,
      role: userRole,
    });
    if (!result.ok) {
      toast.error(result.error ?? 'Something went wrong while inviting the member');
    } else {
      userEmail = '';
      userRole = 'MEMBER';
      showInviteForm = false;
      activeView = 'pending-invites';
      await fetchMembers();
      toast.success('Invite Sent Successfully');
    }
    inviteInProgress = false;
  }

  async function resendInvite(inviteId: string) {
    resendInProgressInviteId = inviteId;
    const result = await postJson(`/api/v2/${$page.params.subdomain}/members/invite/${inviteId}/resend`, {});

    if (!result.ok) {
      toast.error(result.error ?? 'Unable to resend invite');
      resendInProgressInviteId = null;
      return;
    }

    await fetchMembers();
    toast.success('Invite resent successfully');
    resendInProgressInviteId = null;
  }

  function formatInviteSentAt(timestamp: string | null) {
    if (!timestamp) return 'Not sent';
    return new Date(timestamp).toLocaleString();
  }
</script>

<h3 class="text-3xl font-bold dark:text-white">Members</h3>

<div class="m-5">
  {#if !showInviteForm}
    <div class="flex items-start">
      <div class="relative group">
        <button
          on:click={() => (showInviteForm = true)}
          disabled={!allowMemberInvite}
          class={`text-white ${
            !allowMemberInvite ? 'bg-gray-400 cursor-not-allowed' : 'bg-blue-700 hover:bg-blue-800'
          } focus:ring-4 focus:ring-blue-300 font-medium rounded-lg text-sm px-7 py-3 mr-2 mb-2 transition-colors duration-150 ease-in-out`}
        >
          Invite
        </button>
        {#if !allowMemberInvite}
          <div
            class="absolute bottom-0 whitespace-nowrap min-w-max left-0 flex-col items-start hidden mb-6 group-hover:flex"
          >
            <span
              class="relative z-10 p-2 text-s leading-none text-white whitespace-no-wrap bg-black shadow-lg rounded-md"
            >
              Change the max member configuration
            </span>
            <div class="w-3 h-3 -mt-2 ml-10 rotate-45 bg-black"></div>
          </div>
        {/if}
      </div>
    </div>
  {:else}
    <form method="POST" on:submit|preventDefault={inviteUser}>
      <label for="email" class="mb-2 text-sm font-medium text-gray-900 dark:text-white">
        Email
      </label>
      <input
        type="email"
        id="email"
        name="email"
        bind:value={userEmail}
        class="shadow-sm bg-gray-50 border border-gray-300 text-gray-900 text-sm rounded-lg focus:ring-blue-500 focus:border-blue-500 inline-block p-2.5 dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500 dark:shadow-sm-light"
        placeholder="name@flowbite.com"
        required
      />
      <label for="role" class="mb-2 text-sm font-medium text-gray-900 dark:text-white">Role</label>
      <select
        id="role"
        name="role"
        bind:value={userRole}
        required
        class="bg-gray-50 border border-gray-300 text-gray-900 text-sm rounded-lg focus:ring-blue-500 focus:border-blue-500 inline-block p-2.5 dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500"
      >
        <option value="ADMIN">ADMIN</option>
        <option value="MEMBER">MEMBER</option>
      </select>
      <Button type="submit" progress={inviteInProgress}>Send Invite</Button>
    </form>
  {/if}
</div>

<div class="mb-4 border-b border-gray-200 dark:border-gray-700">
  <ul class="-mb-px flex flex-wrap text-sm font-medium text-center">
    <li class="me-2">
      <button
        class={`inline-block rounded-t-lg border-b-2 px-4 py-2 ${
          activeView === 'members'
            ? 'border-blue-600 text-blue-600 dark:border-blue-500 dark:text-blue-500'
            : 'border-transparent text-gray-500 hover:border-gray-300 hover:text-gray-600 dark:text-gray-400 dark:hover:text-gray-300'
        }`}
        on:click={() => (activeView = 'members')}
        type="button"
      >
        Members ({orgMemberCount})
      </button>
    </li>
    <li class="me-2">
      <button
        class={`inline-block rounded-t-lg border-b-2 px-4 py-2 ${
          activeView === 'pending-invites'
            ? 'border-blue-600 text-blue-600 dark:border-blue-500 dark:text-blue-500'
            : 'border-transparent text-gray-500 hover:border-gray-300 hover:text-gray-600 dark:text-gray-400 dark:hover:text-gray-300'
        }`}
        on:click={() => (activeView = 'pending-invites')}
        type="button"
      >
        Pending Invites ({pendingInviteCount})
      </button>
    </li>
  </ul>
</div>

{#if activeView === 'members'}
  <div class="relative overflow-x-auto shadow-md sm:rounded-lg">
    <table class="w-full text-sm text-left text-gray-500 dark:text-gray-400">
      <thead class="text-xs text-gray-700 uppercase bg-gray-50 dark:bg-gray-700 dark:text-gray-400">
        <tr>
          <th scope="col" class="px-6 py-3">Name</th>
          <th scope="col" class="px-6 py-3">Email</th>
          <th scope="col" class="px-6 py-3">Sip Username</th>
          <th scope="col" class="px-6 py-3">Sip Password</th>
          <th scope="col" class="px-6 py-3">Extension</th>
          <th scope="col" class="px-6 py-3">Role</th>
          <th scope="col" class="px-6 py-3">Action</th>
        </tr>
      </thead>
      <tbody>
        {#if isLoading}
          <tr class="bg-white border-b dark:bg-gray-900 dark:border-gray-700">
            <td class="px-6 py-4" colspan="7">Loading...</td>
          </tr>
        {:else}
          {#each members as member}
            <tr class="bg-white border-b dark:bg-gray-900 dark:border-gray-700">
              <th
                scope="row"
                class="px-6 py-4 font-medium text-gray-900 whitespace-nowrap dark:text-white"
              >
                {member.user.name}
              </th>
              <td class="px-6 py-4">
                {member.user.email}
              </td>
              <td class="px-6 py-4">
                {member.username}
              </td>
              <td class="px-6 py-4">
                <div class="flex">
                  <input
                    type="password"
                    autocomplete="off"
                    readonly
                    class="rounded-none rounded-l-lg bg-gray-300 border text-gray-900 focus:ring-blue-500 focus:border-blue-500 block flex-1 min-w-0 w-full text-sm border-gray-300 p-2.5 dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500"
                    value={member.sipPassword}
                  />
                  <button
                    on:click={() => navigator.clipboard.writeText(member.sipPassword)}
                    class="dark:text-gray-400 dark:border-gray-600 border border-l-0 border-gray-300 rounded-r-md px-3 text-gray-900 bg-gray-200 hover:bg-gray-300 focus:ring-4 focus:outline-none focus:ring-blue-300 font-medium text-sm p-2.5 text-center inline-flex items-center mr-2 dark:bg-blue-600 dark:hover:bg-blue-700 dark:focus:ring-blue-800"
                  >
                    <CopyIcon />
                  </button>
                </div>
              </td>
              <td class="px-6 py-4">
                {member.extensionNumber}
              </td>
              <td class="px-6 py-4">
                {member.role}
              </td>
              <td class="px-6 py-4">
                <a
                  class="text-blue-600 dark:text-blue-500 hover:underline"
                  href="/app/{$page.params.subdomain}/members/{member.user.id}/edit"
                >
                  Edit
                </a>
              </td>
            </tr>
          {/each}
        {/if}
      </tbody>
    </table>
  </div>

  <Pagination
    baseUrl={`${data.basePath}/members`}
    {totalPages}
    {currentPage}
    {itemsPerPage}
    totalCount={orgMemberCount}
  />
{:else}
  <div class="relative overflow-x-auto shadow-md sm:rounded-lg">
    <table class="w-full text-sm text-left text-gray-500 dark:text-gray-400">
      <thead class="text-xs text-gray-700 uppercase bg-gray-50 dark:bg-gray-700 dark:text-gray-400">
        <tr>
          <th scope="col" class="px-6 py-3">Email</th>
          <th scope="col" class="px-6 py-3">Role</th>
          <th scope="col" class="px-6 py-3">Status</th>
          <th scope="col" class="px-6 py-3">Last Sent</th>
          <th scope="col" class="px-6 py-3">Resends</th>
          <th scope="col" class="px-6 py-3">Action</th>
        </tr>
      </thead>
      <tbody>
        {#if isLoading}
          <tr class="bg-white border-b dark:bg-gray-900 dark:border-gray-700">
            <td class="px-6 py-4" colspan="6">Loading...</td>
          </tr>
        {:else if !pendingInvites.length}
          <tr class="bg-white border-b dark:bg-gray-900 dark:border-gray-700">
            <td class="px-6 py-4" colspan="6">No pending invites.</td>
          </tr>
        {:else}
          {#each pendingInvites as invite}
            <tr class="bg-white border-b dark:bg-gray-900 dark:border-gray-700">
              <td class="px-6 py-4">{invite.email}</td>
              <td class="px-6 py-4">{invite.role}</td>
              <td class="px-6 py-4">{invite.status}</td>
              <td class="px-6 py-4">{formatInviteSentAt(invite.inviteEmailSentAt)}</td>
              <td class="px-6 py-4">{invite.inviteResendCount}</td>
              <td class="px-6 py-4">
                <button
                  class="text-blue-600 dark:text-blue-500 hover:underline disabled:text-gray-400 disabled:no-underline"
                  disabled={resendInProgressInviteId === invite.id}
                  on:click={() => resendInvite(invite.id)}
                  type="button"
                >
                  {resendInProgressInviteId === invite.id ? 'Resending...' : 'Resend'}
                </button>
              </td>
            </tr>
          {/each}
        {/if}
      </tbody>
    </table>
  </div>
{/if}
