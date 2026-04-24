<script lang="ts">
  import { deleteJson, getJson, postJson } from '$lib/http';
  import SearchIcon from '$lib/components/Icons/SearchIcon.svelte';
  import Spinner from '$lib/components/Icons/Spinner.svelte';
  import toast from 'svelte-french-toast';

  type QueueMemberItem = {
    id: string;
    name: string;
    username: string;
  };

  type SearchMember = {
    id: string;
    username: string;
    user?: {
      name?: string;
    };
  };

  export let queueMembers: QueueMemberItem[] = [];
  export let subdomain = '';
  export let queueId = '';

  let searchValue = '';
  let searchResults: QueueMemberItem[] = [];
  let searchProgress = false;
  let searchMessage = 'Type at least 2 characters to search by member name or SIP username.';
  let searchRequestId = 0;

  function getMemberName(member: SearchMember) {
    return member.user?.name?.trim() || member.username;
  }

  function normalizeMember(member: SearchMember | QueueMemberItem): QueueMemberItem {
    if ('name' in member) return member;

    return {
      id: member.id,
      name: getMemberName(member),
      username: member.username,
    };
  }

  async function onSearchChange(event: Event) {
    const requestId = ++searchRequestId;
    searchProgress = true;
    searchValue = (event.currentTarget as HTMLInputElement).value;
    const search = searchValue.trim();

    if (search.length < 2) {
      searchResults = [];
      searchMessage = 'Type at least 2 characters to search by member name or SIP username.';
      searchProgress = false;
      return;
    }

    const result = await getJson<{ members?: SearchMember[] }>(
      `/api/v2/${subdomain}/members?search=${encodeURIComponent(search)}`,
    );

    if (requestId !== searchRequestId) return;

    if (!result.ok) {
      searchResults = [];
      searchMessage = result.error || 'Unable to search members right now.';
      searchProgress = false;
      return;
    }

    const currentIds = new Set(queueMembers.map((member) => member.id));

    searchResults = (result.data.members ?? [])
      .map(normalizeMember)
      .filter((member) => !currentIds.has(member.id));

    searchMessage =
      searchResults.length > 0
        ? ''
        : 'No matching members were found, or they are already assigned to this queue.';
    searchProgress = false;
  }

  async function onMemberClick(member: QueueMemberItem) {
    const result = await postJson(`/api/v2/${subdomain}/queues/${queueId}/members`, {
      userId: member.id,
    });

    if (!result.ok) {
      toast.error(result.error || 'Unable to add member to queue.');
      return;
    }

    queueMembers = [...queueMembers, member];
    searchValue = '';
    searchResults = [];
    searchMessage = 'Type at least 2 characters to search by member name or SIP username.';
    toast.success(`${member.name} added to the queue`);
  }

  async function onMemberDeleteClick(member: QueueMemberItem) {
    const result = await deleteJson(`/api/v2/${subdomain}/queues/${queueId}/members/${member.id}`);

    if (!result.ok) {
      toast.error(result.error || 'Unable to remove member from queue.');
      return;
    }

    queueMembers = queueMembers.filter((m) => m.id !== member.id);
    toast.success(`${member.name} removed from the queue`);
  }
</script>

<section class="space-y-5">
  <div class="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm dark:border-slate-700 dark:bg-slate-900">
    <div class="flex items-start justify-between gap-4">
      <div class="space-y-1">
        <h3 class="text-lg font-semibold text-slate-900 dark:text-slate-100">Queue members</h3>
        <p class="max-w-2xl text-sm text-slate-600 dark:text-slate-300">
          Search for an existing org member and add them to this queue. Members already assigned to
          the queue are automatically hidden from search results.
        </p>
      </div>
      <span
        class="inline-flex items-center rounded-full bg-slate-100 px-3 py-1 text-xs font-semibold text-slate-700 dark:bg-slate-800 dark:text-slate-200"
      >
        {queueMembers.length} assigned
      </span>
    </div>

    <div class="mt-5 space-y-3">
      <label for="queue-member-search" class="block text-sm font-medium text-slate-900 dark:text-slate-100">
        Add member
      </label>
      <div class="relative">
        <div class="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3 text-slate-400">
          <SearchIcon />
        </div>
        <input
          id="queue-member-search"
          value={searchValue}
          on:input={onSearchChange}
          type="search"
          autocomplete="off"
          class="block w-full rounded-xl border border-slate-300 bg-slate-50 p-3 pl-10 pr-11 text-sm text-slate-900 shadow-sm transition focus:border-blue-500 focus:ring-2 focus:ring-blue-500/30 dark:border-slate-600 dark:bg-slate-800 dark:text-slate-100"
          placeholder="Search by member name or SIP username"
        />
        {#if searchProgress}
          <div class="absolute right-3 top-1/2 -translate-y-1/2 text-slate-500 dark:text-slate-300">
            <Spinner />
          </div>
        {/if}
      </div>

      {#if searchResults.length > 0}
        <div class="overflow-hidden rounded-xl border border-slate-200 bg-slate-50 shadow-sm dark:border-slate-700 dark:bg-slate-950/60">
          <ul class="divide-y divide-slate-200 dark:divide-slate-700">
            {#each searchResults as member}
              <li>
                <button
                  on:click|preventDefault={() => onMemberClick(member)}
                  class="flex w-full items-center justify-between gap-4 px-4 py-3 text-left transition hover:bg-blue-50 dark:hover:bg-slate-800"
                >
                  <div class="min-w-0">
                    <p class="truncate text-sm font-semibold text-slate-900 dark:text-slate-100">
                      {member.name}
                    </p>
                    <p class="truncate text-sm text-slate-500 dark:text-slate-400">
                      {member.username}
                    </p>
                  </div>
                  <span class="rounded-full bg-blue-100 px-3 py-1 text-xs font-semibold text-blue-700 dark:bg-blue-950 dark:text-blue-200">
                    Add to queue
                  </span>
                </button>
              </li>
            {/each}
          </ul>
        </div>
      {:else}
        <p class="text-sm text-slate-500 dark:text-slate-400">{searchMessage}</p>
      {/if}
    </div>
  </div>

  <div class="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm dark:border-slate-700 dark:bg-slate-900">
    <div class="flex items-center justify-between gap-3">
      <div>
        <h4 class="text-base font-semibold text-slate-900 dark:text-slate-100">Assigned members</h4>
        <p class="text-sm text-slate-500 dark:text-slate-400">
          Members in this list will receive calls from the queue.
        </p>
      </div>
    </div>

    {#if queueMembers.length === 0}
      <div class="mt-4 rounded-xl border border-dashed border-slate-300 bg-slate-50 px-4 py-5 text-sm text-slate-500 dark:border-slate-700 dark:bg-slate-800/70 dark:text-slate-400">
        No members are assigned to this queue yet.
      </div>
    {:else}
      <ul class="mt-4 divide-y divide-slate-200 dark:divide-slate-700">
        {#each queueMembers as member}
          <li class="flex items-center justify-between gap-4 py-3">
            <div class="min-w-0">
              <p class="truncate text-sm font-semibold text-slate-900 dark:text-slate-100">
                {member.name}
              </p>
              <p class="truncate text-sm text-slate-500 dark:text-slate-400">{member.username}</p>
            </div>
            <button
              on:click|preventDefault={() => onMemberDeleteClick(member)}
              type="button"
              class="rounded-lg border border-rose-200 px-3 py-2 text-sm font-medium text-rose-700 transition hover:bg-rose-50 dark:border-rose-900 dark:text-rose-300 dark:hover:bg-rose-950/30"
            >
              Remove
            </button>
          </li>
        {/each}
      </ul>
    {/if}
  </div>
</section>
