<script lang="ts">
  import { page } from '$app/state';
  import { postJson } from '$lib/http';
  import toast from '$lib/toast';
  import { publicSipUserRootDomain } from '$lib/publicConfig';
  let { data } = $props();
  const sipDomain = publicSipUserRootDomain || 'example.com';
  let isLoading = $state(false);
  let hasChanged = $state(false);
  // A local copy the page edits and saves.
  // svelte-ignore state_referenced_locally
  let memberProfile = $state(data.member);
  // svelte-ignore state_referenced_locally
  let selectedNumber = $state(memberProfile.number?.number || '');

  function handleSelectionChange(event: Event) {
    const target = event.target as HTMLSelectElement;
    selectedNumber = target.value;
    hasChanged = true;
  }

  async function handleNumberUpdate(event: Event) {
    event.preventDefault();
    isLoading = true;
    const result = await postJson(`/api/v2/${page.params.subdomain}/members/default-number`, {
      number: selectedNumber,
    });

    if (!result.ok) {
      toast.error(result.error || 'Failed to update member default number.');
      isLoading = false;
      return;
    }

    memberProfile = {
      ...memberProfile,
      number: data.numbers.find((number: any) => number.number === selectedNumber) ?? null,
    };
    isLoading = false;
    hasChanged = false;
  }
</script>

<div
  class="w-full max-w-sm bg-white border border-gray-200 rounded-lg shadow dark:bg-gray-800 dark:border-gray-700"
>
  <div class="flex flex-col items-center pt-10 pb-10">
    <img class="w-24 h-24 mb-3 rounded-full shadow-lg" src={data.user.picture} alt="Profile" />
    <h5 class="mb-1 text-xl font-medium text-gray-900 dark:text-white">{data.user.name}</h5>
    <span class="text-sm text-gray-500 dark:text-gray-400">{memberProfile.role}</span>
    <span class="text-sm text-gray-500 dark:text-gray-400">
      {memberProfile.username}@{page.params.subdomain}.{sipDomain}
    </span>
  </div>
</div>

<form method="POST" onsubmit={handleNumberUpdate}>
  <div class="max-w-xl mt-10">
    <label for="defaultNumber" class="block mb-2 text-lg font-bold text-gray-900 dark:text-white">
      Default Outbound Number
    </label>
    <div class="flex items-center space-x-2">
      <select
        name="numberId"
        id="defaultNumber"
        class="bg-gray-50 border border-gray-300 text-gray-900 text-sm rounded-lg focus:ring-blue-500 focus:border-blue-500 block w-3/4 p-2.5 dark:bg-gray-600 dark:border-gray-500 dark:text-white"
        bind:value={selectedNumber}
        onchange={handleSelectionChange}
      >
        {#each data.numbers as number}
          <option value={number.number}>{number.name} ({number.number})</option>
        {/each}
      </select>

      {#if hasChanged}
        {#if isLoading}
          <div class="loader"></div>
        {:else}
          <button
            type="submit"
            class="text-white bg-blue-700 hover:bg-blue-800 focus:ring-4 focus:outline-none focus:ring-blue-300 font-medium rounded-lg text-sm px-5 py-2.5 text-center dark:bg-blue-600 dark:hover:bg-blue-700 dark:focus:ring-blue-800"
          >
            Update
          </button>
        {/if}
      {/if}
    </div>
  </div>
</form>

<style>
  @keyframes spinner {
    0% {
      transform: rotate(0deg);
    }
    100% {
      transform: rotate(360deg);
    }
  }
  .loader {
    display: inline-flex;
    justify-content: center;
    align-items: center;
    background-color: transparent;
    border-radius: 50%;
    padding: 0.625rem;
    font-size: 0.875rem;
    animation: spinner 1s linear infinite;
    border: 4px solid #f3f3f3;
    border-top-color: #3498db;
    width: 2rem;
    height: 2rem;
  }
</style>
