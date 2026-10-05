<script lang="ts">
  import { untrack } from 'svelte';
  import { page } from '$app/state';
  import { getJson, postJson } from '$lib/http';
  import Pagination from '$lib/components/Pagination.svelte';
  import toast from '$lib/toast';
  import { formatDateTime, formatEnum } from '$lib/format';
  import Button from '$lib/components/Button.svelte';
  import CopyIcon from '$lib/components/Icons/CopyIcon.svelte';
  import Dialog from '$lib/components/Dialog.svelte';
  import Pill from '$lib/components/Pill.svelte';
  import Table from '$lib/components/Table.svelte';
  import Tabs from '$lib/components/Tabs.svelte';
  import UserAvatar from '$lib/components/UserAvatar.svelte';
  import EmptyState from '$lib/components/form/EmptyState.svelte';
  import Field from '$lib/components/form/Field.svelte';
  import Input from '$lib/components/form/Input.svelte';
  import PageHeader from '$lib/components/form/PageHeader.svelte';
  import SecondaryButton from '$lib/components/form/SecondaryButton.svelte';
  import Select from '$lib/components/form/Select.svelte';

  type Member = {
    user: { name: string; email: string; id: string; picture?: string | null };
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

  let showInviteForm = $state(false);
  let activeView: 'members' | 'pending-invites' = $state('members');

  let { data } = $props();
  let members: Member[] = $state([]);
  let pendingInvites: PendingInvite[] = $state([]);
  let currentPage = $state(1);
  let itemsPerPage = $state(10);
  let orgMemberCount = $state(0);
  let pendingInviteCount = $state(0);
  let totalPages = $state(0);
  let allowMemberInvite = $state(false);
  let isLoading = $state(false);
  let userEmail = $state('');
  let userRole = $state('MEMBER');
  let inviteInProgress = $state(false);
  let resendInProgressInviteId: string | null = $state(null);
  let latestRequestId = 0;
  let lastFetchKey = '';

  async function fetchMembers() {
    const requestId = ++latestRequestId;
    isLoading = true;
    const searchParams = page.url.searchParams;
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
      `/api/v2/${page.params.subdomain}/admin/members?page=${requestedPage}&itemsPerPage=${requestedItemsPerPage}`,
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

  // Refetch when the URL or the org changes. The fetch itself is untracked,
  // so the state it reads and writes does not re-run this.
  $effect(() => {
    const nextFetchKey = `${page.url.search}|${page.params.subdomain}`;
    if (nextFetchKey !== lastFetchKey) {
      lastFetchKey = nextFetchKey;
      untrack(() => fetchMembers());
    }
  });

  async function inviteUser() {
    inviteInProgress = true;
    const result = await postJson(`/api/v2/${page.params.subdomain}/members/invite`, {
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
    const result = await postJson(
      `/api/v2/${page.params.subdomain}/members/invite/${inviteId}/resend`,
      {},
    );

    if (!result.ok) {
      toast.error(result.error ?? 'Unable to resend invite');
      resendInProgressInviteId = null;
      return;
    }

    await fetchMembers();
    toast.success('Invite resent successfully');
    resendInProgressInviteId = null;
  }

  async function copyPassword(password: string) {
    await navigator.clipboard.writeText(password);
    toast.success('SIP password copied');
  }
</script>

<PageHeader
  title="Members"
  description="Everyone in this organisation, with the SIP login their phone or browser uses to take calls."
>
  {#snippet actions()}
    <div class="flex flex-col items-end gap-1">
      <Button onclick={() => (showInviteForm = true)} disabled={!allowMemberInvite}>Invite</Button>
      {#if !allowMemberInvite && !isLoading}
        <p class="text-xs text-gray-500 dark:text-gray-400">
          The organization's max member limit is reached.
        </p>
      {/if}
    </div>
  {/snippet}
</PageHeader>

<Dialog
  showDialog={showInviteForm}
  title="Invite a member"
  description="They get an email with a link to join this organisation."
  onClose={() => (showInviteForm = false)}
>
  <form
    class="space-y-5"
    onsubmit={(e) => {
      e.preventDefault();
      inviteUser();
    }}
  >
    <Field label="Email" for="email">
      <Input
        type="email"
        id="email"
        name="email"
        bind:value={userEmail}
        placeholder="name@company.com"
        required
      />
    </Field>
    <Field label="Role" for="role" hint="Admins can manage members, numbers, billing and settings.">
      <Select id="role" name="role" bind:value={userRole} required>
        <option value="MEMBER">Member</option>
        <option value="ADMIN">Admin</option>
      </Select>
    </Field>
    <div class="flex gap-3">
      <Button type="submit" progress={inviteInProgress}>Send Invite</Button>
      <SecondaryButton onclick={() => (showInviteForm = false)}>Cancel</SecondaryButton>
    </div>
  </form>
</Dialog>

<div class="mb-4">
  <Tabs
    tabs={[
      { id: 'members', label: `Members (${orgMemberCount})` },
      { id: 'pending-invites', label: `Pending Invites (${pendingInviteCount})` },
    ]}
    current={activeView}
    onSelect={(id) => (activeView = id as 'members' | 'pending-invites')}
  />
</div>

{#if activeView === 'members'}
  <Table
    columns={[
      'Name',
      'Email',
      'SIP username',
      'SIP password',
      'Extension',
      'Role',
      { label: 'Actions', srOnly: true },
    ]}
    loading={isLoading}
    isEmpty={members.length === 0}
  >
    {#snippet empty()}
      <EmptyState title="No members yet" description="Invite your team to start taking calls." />
    {/snippet}
    {#each members as member (member.user.id)}
      <tr class="hover:bg-gray-50 dark:hover:bg-gray-700/50">
        <th scope="row" class="whitespace-nowrap font-medium text-gray-900 dark:text-white">
          <div class="flex items-center gap-3">
            <UserAvatar
              picture={member.user.picture}
              name={member.user.name}
              email={member.user.email}
            />
            {member.user.name}
          </div>
        </th>
        <td>{member.user.email}</td>
        <td>{member.username}</td>
        <td>
          <div class="flex w-48 items-center gap-1.5">
            <Input
              type="password"
              autocomplete="off"
              readonly
              value={member.sipPassword}
              aria-label="SIP password of {member.user.name}"
            />
            <button
              type="button"
              title="Copy SIP password"
              onclick={() => copyPassword(member.sipPassword)}
              class="shrink-0 rounded-lg p-2.5 text-gray-500 hover:bg-gray-100 hover:text-gray-900 dark:text-gray-400 dark:hover:bg-gray-700 dark:hover:text-white"
            >
              <span class="sr-only">Copy SIP password</span>
              <CopyIcon />
            </button>
          </div>
        </td>
        <td>{member.extensionNumber || '-'}</td>
        <td>
          <Pill tone={member.role === 'ADMIN' ? 'cyan' : 'gray'}>{formatEnum(member.role)}</Pill>
        </td>
        <td class="text-right">
          <SecondaryButton
            size="sm"
            href="/app/{page.params.subdomain}/members/{member.user.id}/edit"
          >
            Edit
          </SecondaryButton>
        </td>
      </tr>
    {/each}
  </Table>

  <Pagination
    baseUrl={`${data.basePath}/members`}
    {totalPages}
    {currentPage}
    {itemsPerPage}
    totalCount={orgMemberCount}
  />
{:else}
  <Table
    columns={[
      'Email',
      'Role',
      'Status',
      'Last sent',
      'Resends',
      { label: 'Actions', srOnly: true },
    ]}
    loading={isLoading}
    isEmpty={pendingInvites.length === 0}
  >
    {#snippet empty()}
      <EmptyState
        title="No pending invites"
        description="Invites you send show here until the person joins."
      />
    {/snippet}
    {#each pendingInvites as invite (invite.id)}
      <tr class="hover:bg-gray-50 dark:hover:bg-gray-700/50">
        <td class="font-medium text-gray-900 dark:text-white">{invite.email}</td>
        <td>
          <Pill tone={invite.role === 'ADMIN' ? 'cyan' : 'gray'}>{formatEnum(invite.role)}</Pill>
        </td>
        <td><Pill tone="amber" dot>{formatEnum(invite.status)}</Pill></td>
        <td>{formatDateTime(invite.inviteEmailSentAt, 'Not sent')}</td>
        <td>{invite.inviteResendCount}</td>
        <td class="text-right">
          <SecondaryButton
            size="sm"
            disabled={resendInProgressInviteId === invite.id}
            onclick={() => resendInvite(invite.id)}
          >
            {resendInProgressInviteId === invite.id ? 'Resending...' : 'Resend'}
          </SecondaryButton>
        </td>
      </tr>
    {/each}
  </Table>
{/if}
