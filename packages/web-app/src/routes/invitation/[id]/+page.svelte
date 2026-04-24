<script lang="ts">
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import { page } from '$app/stores';
  import ErrorMessage from '$lib/components/ErrorMessage.svelte';
  import { getJson, postJson } from '$lib/http';

  type InvitationData = {
    id: string;
    email: string;
    role: string;
    org: {
      id: string;
      name: string;
    };
  };

  let invitation: InvitationData | null = null;
  let error: { message: string; formErrors: { message: string; path: string[] }[] } | null = null;
  let username = '';
  let loading = false;
  let saving = false;

  onMount(() => {
    void loadInvitation();
  });

  async function loadInvitation() {
    loading = true;
    error = null;

    const result = await getJson<{ invitation: InvitationData; suggestedUsername: string }>(
      `/api/v2/user/invitations/${$page.params.id}`,
    );

    if (!result.ok) {
      if (result.status === 401) {
        await goto('/login');
        return;
      }
      error = { message: result.error, formErrors: [] };
      loading = false;
      return;
    }

    invitation = result.data.invitation;
    username = result.data.suggestedUsername || '';
    loading = false;
  }

  async function acceptInvitation(event: Event) {
    event.preventDefault();
    saving = true;
    error = null;

    const result = await postJson(`/api/v2/user/invitations/${$page.params.id}/accept`, {
      username,
    });

    if (!result.ok) {
      if (result.status === 401) {
        await goto('/login');
        return;
      }
      error = { message: result.error, formErrors: [] };
      saving = false;
      return;
    }

    await goto('/org');
  }
</script>

{#if error}
  <div class="max-w-sm mx-auto">
    <ErrorMessage {error} />
  </div>
{/if}

{#if loading}
  <div class="max-w-sm mx-auto text-sm text-gray-600 dark:text-gray-300">Loading invitation...</div>
{/if}

{#if invitation}
  <div
    class="mx-auto max-w-sm p-6 bg-white border border-gray-200 rounded-lg shadow dark:bg-gray-800 dark:border-gray-700"
  >
    <h5 class="mb-2 text-2xl font-bold tracking-tight text-gray-900 dark:text-white">
      Invitation to join organization
    </h5>
    <p class="mb-3 font-normal text-gray-700 dark:text-gray-400">
      You have been invited to join the team {invitation.org.name}.
    </p>
    <form method="POST" on:submit={acceptInvitation}>
      <label
        for="username"
        class="block w-full mb-2 text-sm font-medium text-gray-900 dark:text-white"
      >
        Desired username
      </label>
      <input
        type="text"
        id="username"
        name="username"
        bind:value={username}
        class="block w-full shadow-sm bg-gray-50 border border-gray-300 text-gray-900 text-sm rounded-lg focus:ring-blue-500 focus:border-blue-500 p-2.5 dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500 dark:shadow-sm-light"
        placeholder="user.name"
        required
      />
      <button
        type="submit"
        disabled={saving}
        class="mt-4 inline-flex items-center px-3 py-2 text-sm font-medium text-center text-white bg-blue-700 rounded-lg hover:bg-blue-800 focus:ring-4 focus:outline-none focus:ring-blue-300 dark:bg-blue-600 dark:hover:bg-blue-700 dark:focus:ring-blue-800"
      >
        {saving ? 'Accepting...' : 'Accept'}
      </button>
    </form>
  </div>
{/if}
