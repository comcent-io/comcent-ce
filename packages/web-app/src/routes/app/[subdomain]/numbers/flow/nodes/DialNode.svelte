<script lang="ts">
  import type { SelectedOutlet } from '../SelectedOutlet';
  import type { DialNode } from './DialNode';
  import Draggable from '../utils/Draggable.svelte';
  import Inlet from '../utils/Inlet.svelte';
  import CloseButton from '../utils/CloseButton.svelte';
  import { createEventDispatcher } from 'svelte';
  import EditButton from '../utils/EditButton.svelte';
  import { page } from '$app/stores';
  import { isValidPhoneNumber } from 'libphonenumber-js';
  import Outlet from '../utils/Outlet.svelte';

  const dispatch = createEventDispatcher();
  export let node: DialNode;
  let editData = JSON.parse(JSON.stringify(node.data));
  export let selectedOutlet: SelectedOutlet | null;
  export let inletConnected = false;
  export let inletConnectable = false;

  let editing = false;

  let searchResults: any[] = [];
  let searchProgress = false;
  let inputError = '';

  async function searchUser(searchText: string) {
    try {
      const encodedSearchText = encodeURIComponent(searchText);
      const response = await fetch(
        `/api/v2/${$page.params.subdomain}/members?search=${encodedSearchText}`,
      );
      if (!response.ok) {
        throw new Error('Network response was not ok');
      }
      const payload = await response.json();
      return payload.members ?? [];
    } catch (error) {
      console.error('Error fetching data:', error);
      return [];
    }
  }

  async function fetchSuggestions(event: any) {
    let userInput = event.target.value;
    if (!isValidPhoneNumber(userInput)) {
      if (userInput.length < 3) {
        searchResults = [];
      } else {
        searchProgress = true;
        searchResults = await searchUser(userInput);
        searchProgress = false;
      }
    }
  }

  function selectUser(member: { username: string }) {
    editData.data.to = member.username;
    searchResults = [];
  }

  async function onUpdate() {
    let userInput = editData.data.to;
    if (!isValidPhoneNumber(userInput)) {
      const data = await searchUser(userInput);
      const usernameExists = data.some((item: any) => item.username === userInput);
      if (!usernameExists) {
        inputError = 'Please enter a valid username/number';
        return;
      }
    }
    if (editData.data.timeout > 60) {
      editData.data.timeout = 60;
    }
    node.data = editData;
    editing = false;
    dispatch('updated', { node: node });
  }
</script>

<Draggable
  {node}
  title={node.data.type}
  class="block w-[17rem] rounded-lg border-2 border-amber-400 bg-white shadow dark:border-amber-400 dark:bg-gray-800"
  on:dragEnd
>
  <svelte:fragment slot="headerActions">
    <EditButton on:edit={() => (editing = true)} />
    <CloseButton on:close />
  </svelte:fragment>
  <Inlet
    {selectedOutlet}
    {node}
    connected={inletConnected}
    connectable={inletConnectable}
    on:inletSelected
    on:disconnectInlet
  >
    <div class="space-y-1 p-3">
      <p class="text-sm font-medium text-slate-800 dark:text-white">
        To: <span class="font-normal">{node.data.data.to}</span>
      </p>
      <p class="text-sm font-medium text-slate-800 dark:text-white">
        Spoof: <span class="font-normal">{node.data.data.shouldSpoof ?? 'false'}</span>
      </p>
    </div>

    <div class="px-3 pb-3">
      <Outlet
        {selectedOutlet}
        nodeId={node.data.id}
        outletId={'timeout'}
        connected={Boolean(node.data.outlets.timeout)}
        class="w-full"
        on:outletSelected
        on:disconnectOutlet
      >
        <p class="text-center text-sm font-semibold dark:text-white">Timeout</p>
      </Outlet>
    </div>
  </Inlet>
</Draggable>

<!-- Edit modal -->
{#if editing}
  <div
    tabindex="-1"
    aria-hidden="true"
    class="fixed top-0 left-0 right-0 z-50 w-full p-4 overflow-x-hidden overflow-y-auto md:inset-0 h-[calc(100%-1rem)] max-h-full flex justify-center items-center"
  >
    <div class="relative w-full max-w-2xl max-h-full">
      <!-- Modal content -->
      <div class="relative bg-white rounded-lg shadow dark:bg-gray-700">
        <!-- Modal header -->
        <div class="flex items-start justify-between p-4 border-b rounded-t dark:border-gray-600">
          <h3 class="text-xl font-semibold text-gray-900 dark:text-white">Dial</h3>
          <button
            type="button"
            class="text-gray-400 bg-transparent hover:bg-gray-200 hover:text-gray-900 rounded-lg text-sm w-8 h-8 ml-auto inline-flex justify-center items-center dark:hover:bg-gray-600 dark:hover:text-white"
            on:click={() => (editing = false)}
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
        </div>
        <!-- Modal body -->
        <div class="p-6 space-y-6">
          <label for="name" class="block mb-2 text-sm font-medium text-gray-900 dark:text-white">
            Username/number
          </label>
          <input
            autocomplete="off"
            type="text"
            id="name"
            name="name"
            class="bg-gray-50 border border-gray-300 text-gray-900 text-sm rounded-lg focus:ring-blue-500 focus:border-blue-500 block w-full p-2.5 dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500"
            placeholder="Enter username/number"
            required
            bind:value={editData.data.to}
            on:input={fetchSuggestions}
          />
          {#if inputError}
            <p class="text-red-500 text-xs italic">{inputError}</p>
          {/if}
          {#if searchResults.length > 0}
            <div
              class="absolute z-10 bg-white divide-y divide-gray-100 rounded-lg shadow w-44 dark:bg-gray-700"
            >
              <ul
                class="py-2 text-sm text-gray-700 dark:text-gray-200"
                aria-labelledby="dropdownDefaultButton"
              >
                {#each searchResults as member}
                  <li>
                    <button
                      on:click|preventDefault={() => selectUser(member)}
                      class=" w-full block px-2 py-2 hover:bg-gray-100 dark:hover:bg-gray-600 dark:hover:text-white text-left"
                    >
                      <div class="flex-1 min-w-0">
                        <p class="text-sm font-medium text-gray-900 truncate dark:text-white">
                          {member.username}
                        </p>
                      </div>
                    </button>
                  </li>
                {/each}
              </ul>
            </div>
          {/if}
          <label for="timeout" class="block mb-2 text-sm font-medium text-gray-900 dark:text-white">
            Timeout (1-60)
          </label>
          <input
            type="number"
            id="timeout"
            name="timeout"
            min="1"
            max="60"
            class="bg-gray-50 border border-gray-300 text-gray-900 text-sm rounded-lg focus:ring-blue-500 focus:border-blue-500 block w-full p-2.5 dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500"
            bind:value={editData.data.timeout}
          />
          <div class="flex items-center mb-4">
            <input
              id="spoofNumber"
              type="checkbox"
              bind:checked={editData.data.shouldSpoof}
              class="w-4 h-4 text-blue-600 bg-gray-100 border-gray-300 rounded focus:ring-blue-500 dark:focus:ring-blue-600 dark:ring-offset-gray-800 focus:ring-2 dark:bg-gray-700 dark:border-gray-600"
            />
            <label
              for="spoofNumber"
              class="ms-2 text-sm font-medium text-gray-900 dark:text-gray-300"
            >
              Spoof number
            </label>
            {#if editData.data.shouldSpoof}
              <div
                class="p-4 mb-4 text-sm text-yellow-800 rounded-lg bg-yellow-50 dark:bg-gray-800 dark:text-yellow-300"
                role="alert"
              >
                <span class="font-medium">Note!</span>
                Spoofing works only if Sip Trunk associated with number supports it.
              </div>
            {/if}
          </div>
        </div>
        <!-- Modal footer -->
        <div
          class="flex items-center p-6 space-x-2 border-t border-gray-200 rounded-b dark:border-gray-600"
        >
          <button
            data-modal-hide="defaultModal"
            type="button"
            on:click={onUpdate}
            class="text-white bg-blue-700 hover:bg-blue-800 focus:ring-4 focus:outline-none focus:ring-blue-300 font-medium rounded-lg text-sm px-5 py-2.5 text-center dark:bg-blue-600 dark:hover:bg-blue-700 dark:focus:ring-blue-800"
          >
            Save
          </button>
          <button
            data-modal-hide="defaultModal"
            type="button"
            on:click={() => (editing = false)}
            class="text-gray-500 bg-white hover:bg-gray-100 focus:ring-4 focus:outline-none focus:ring-blue-300 rounded-lg border border-gray-200 text-sm font-medium px-5 py-2.5 hover:text-gray-900 focus:z-10 dark:bg-gray-700 dark:text-gray-300 dark:border-gray-500 dark:hover:text-white dark:hover:bg-gray-600 dark:focus:ring-gray-600"
          >
            Cancel
          </button>
        </div>
      </div>
    </div>
  </div>
{/if}
