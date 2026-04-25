<script lang="ts">
  import { page } from '$app/stores';
  import { deleteJson, postJson } from '$lib/http';
  import toast from 'svelte-french-toast';
  import { publicSipUserRootDomain } from '$lib/publicConfig';
  export let data;
  const sipDomain = publicSipUserRootDomain || 'example.com';
  let isLoading = false;
  let hasChanged = false;
  let showNewKeyModal = false;
  let apiKeyErrorMessage = '';
  let newApiKeyName = '';
  let memberProfile = data.member;
  let selectedNumber = memberProfile.number?.number || '';

  function handleSelectionChange(event: Event) {
    const target = event.target as HTMLSelectElement;
    selectedNumber = target.value;
    hasChanged = true;
  }

  async function handleNumberUpdate(event: Event) {
    event.preventDefault();
    isLoading = true;
    const result = await postJson(`/api/v2/${$page.params.subdomain}/members/default-number`, {
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

  async function createApiKey(event: Event) {
    event.preventDefault();
    apiKeyErrorMessage = '';

    const result = await postJson<{ apiKey: string; name: string }>(
      `/api/v2/${$page.params.subdomain}/me/api-keys`,
      { name: newApiKeyName },
    );

    if (!result.ok) {
      apiKeyErrorMessage = result.error;
      showNewKeyModal = true;
      return;
    }

    memberProfile = {
      ...memberProfile,
      apiKeys: [...(memberProfile.apiKeys ?? []), result.data],
    };
    newApiKeyName = '';
    showNewKeyModal = false;
    toast.success('API key created');
  }

  async function removeApiKey(apiKey: string) {
    const result = await deleteJson(
      `/api/v2/${$page.params.subdomain}/me/api-keys/${encodeURIComponent(apiKey)}`,
    );

    if (!result.ok) {
      toast.error(result.error);
      return;
    }

    memberProfile = {
      ...memberProfile,
      apiKeys: (memberProfile.apiKeys ?? []).filter((item: any) => item.apiKey !== apiKey),
    };
    toast.success('API key deleted');
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
      {memberProfile.username}@{$page.params.subdomain}.{sipDomain}
    </span>
  </div>
</div>

<div class="relative overflow-x-auto shadow-md sm:rounded-lg mt-10 max-w-xl">
  <div class="mb-3">
    <button
      type="button"
      on:click={() => (showNewKeyModal = true)}
      class="text-white bg-blue-700 hover:bg-blue-800 focus:ring-4 focus:ring-blue-300 font-medium rounded-lg text-sm px-5 py-2.5 mr-2 mb-2 dark:bg-blue-600 dark:hover:bg-blue-700 focus:outline-none dark:focus:ring-blue-800"
    >
      New key
    </button>
  </div>
  <table class="w-full text-sm text-left text-gray-500 dark:text-gray-400">
    <caption>API Keys</caption>
    <thead class="text-xs text-gray-700 uppercase bg-gray-50 dark:bg-gray-700 dark:text-gray-400">
      <tr>
        <th scope="col" class="px-6 py-3">Name</th>
        <th scope="col" class="px-6 py-3">Key</th>
        <th scope="col" class="px-6 py-3">
          <span class="sr-only">Edit</span>
          <span class="sr-only">Delete</span>
        </th>
      </tr>
    </thead>
    <tbody>
      {#each memberProfile.apiKeys ?? [] as apiKey}
        <tr
          class="bg-white border-b dark:bg-gray-800 dark:border-gray-700 hover:bg-gray-50 dark:hover:bg-gray-600"
        >
          <th
            scope="row"
            class="px-6 py-4 font-medium text-gray-900 whitespace-nowrap dark:text-white"
          >
            {apiKey.name}
          </th>
          <td class="px-6 py-4">
            <div class="flex">
              <input
                type="password"
                autocomplete="off"
                readonly
                class="rounded-none rounded-l-lg bg-gray-300 border text-gray-900 focus:ring-blue-500 focus:border-blue-500 block flex-1 min-w-0 w-full text-sm border-gray-300 p-2.5 dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500"
                value={apiKey.apiKey}
              />
              <button
                on:click={() => navigator.clipboard.writeText(apiKey.apiKey)}
                class="dark:text-gray-400 dark:border-gray-600 border border-l-0 border-gray-300 rounded-r-md px-3 text-gray-900 bg-gray-200 hover:bg-gray-300 focus:ring-4 focus:outline-none focus:ring-blue-300 font-medium text-sm p-2.5 text-center inline-flex items-center mr-2 dark:bg-blue-600 dark:hover:bg-blue-700 dark:focus:ring-blue-800"
              >
                <svg
                  class="w-6 h-6 text-gray-800 dark:text-white"
                  aria-hidden="true"
                  xmlns="http://www.w3.org/2000/svg"
                  fill="currentColor"
                  viewBox="0 0 18 20"
                >
                  <path
                    d="M5 9V4.13a2.96 2.96 0 0 0-1.293.749L.879 7.707A2.96 2.96 0 0 0 .13 9H5Zm11.066-9H9.829a2.98 2.98 0 0 0-2.122.879L7 1.584A.987.987 0 0 0 6.766 2h4.3A3.972 3.972 0 0 1 15 6v10h1.066A1.97 1.97 0 0 0 18 14V2a1.97 1.97 0 0 0-1.934-2Z"
                  />
                  <path
                    d="M11.066 4H7v5a2 2 0 0 1-2 2H0v7a1.969 1.969 0 0 0 1.933 2h9.133A1.97 1.97 0 0 0 13 18V6a1.97 1.97 0 0 0-1.934-2Z"
                  />
                </svg>
              </button>
            </div>
          </td>
          <td class="px-6 py-4 text-right">
            <button
              type="button"
              class="font-medium text-blue-600 dark:text-blue-500 hover:underline"
              on:click={() => removeApiKey(apiKey.apiKey)}
            >
              Delete
            </button>
          </td>
        </tr>
      {/each}
    </tbody>
  </table>
</div>

<div
  tabindex="-1"
  aria-hidden={!showNewKeyModal}
  class="fixed top-0 left-0 right-0 z-50 w-full p-4 overflow-x-hidden md:inset-0 max-h-full bg-gray-700/[.4]"
  class:hidden={!showNewKeyModal}
>
  <div class="relative w-full max-w-md max-h-full mx-auto">
    <div class="relative bg-white rounded-lg shadow dark:bg-gray-700">
      <button
        type="button"
        class="absolute top-3 right-2.5 text-gray-400 bg-transparent hover:bg-gray-200 hover:text-gray-900 rounded-lg text-sm w-8 h-8 ml-auto inline-flex justify-center items-center dark:hover:bg-gray-600 dark:hover:text-white"
        on:click={() => (showNewKeyModal = false)}
      >
        <svg
          class="w-3 h-3"
          aria-hidden="true"
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 14 14"
        >
          <path
            stroke="currentColor"
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="m1 1 6 6m0 0 6 6M7 7l6-6M7 7l-6 6"
          />
        </svg>
        <span class="sr-only">Close modal</span>
      </button>
      <div class="px-6 py-6 lg:px-8">
        {#if apiKeyErrorMessage}
          <div
            class="flex items-center p-4 mb-4 text-sm text-red-800 rounded-lg bg-red-50 dark:bg-gray-800 dark:text-red-400"
            role="alert"
          >
            <span class="sr-only">Error</span>
            <div>
              <span class="font-medium">Error!</span>
              {apiKeyErrorMessage}
            </div>
          </div>
        {/if}
        <h3 class="mb-4 text-xl font-medium text-gray-900 dark:text-white">New Api Key</h3>
        <form class="space-y-6" on:submit|preventDefault={createApiKey}>
          <div>
            <label for="email" class="block mb-2 text-sm font-medium text-gray-900 dark:text-white">
              Name
            </label>
            <input
              type="text"
              name="name"
              bind:value={newApiKeyName}
              class="bg-gray-50 border border-gray-300 text-gray-900 text-sm rounded-lg focus:ring-blue-500 focus:border-blue-500 block w-full p-2.5 dark:bg-gray-600 dark:border-gray-500 dark:placeholder-gray-400 dark:text-white"
              placeholder="Friendly name"
              required
            />
          </div>
          <button
            type="submit"
            class="w-full text-white bg-blue-700 hover:bg-blue-800 focus:ring-4 focus:outline-none focus:ring-blue-300 font-medium rounded-lg text-sm px-5 py-2.5 text-center dark:bg-blue-600 dark:hover:bg-blue-700 dark:focus:ring-blue-800"
          >
            Create
          </button>
        </form>
      </div>
    </div>
  </div>
</div>
<form method="POST" on:submit={handleNumberUpdate}>
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
        on:change={handleSelectionChange}
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
