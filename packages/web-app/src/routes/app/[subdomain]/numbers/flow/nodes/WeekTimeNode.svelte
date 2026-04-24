<script lang="ts">
  import type { SelectedOutlet } from '../SelectedOutlet';
  import type { WeekTimeNode } from './WeekTimeNode';
  import Draggable from '../utils/Draggable.svelte';
  import Inlet from '../utils/Inlet.svelte';
  import Outlet from '../utils/Outlet.svelte';
  import CloseButton from '../utils/CloseButton.svelte';
  import EditButton from '../utils/EditButton.svelte';
  import moment from 'moment-timezone';
  import { createEventDispatcher } from 'svelte';
  import ErrorMessage from '$lib/components/ErrorMessage.svelte';
  import CloseIcon from '$lib/components/Icons/CloseIcon.svelte';
  import PlusIcon from '$lib/components/Icons/PlusIcon.svelte';
  import MinusSignIcon from '$lib/components/Icons/MinusSignIcon.svelte';

  const dispatch = createEventDispatcher();

  export let node: WeekTimeNode;
  let editData = JSON.parse(JSON.stringify(node.data));
  export let selectedOutlet: SelectedOutlet | null;
  export let inletConnected = false;
  export let inletConnectable = false;

  let editing = false;

  const weekdays = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
  const timezones = moment.tz.names();
  function onEdit() {
    editing = true;
  }

  let error = {
    message: '',
  };
  function onUpdate() {
    error.message = '';
    for (const weekday of weekdays) {
      let weekData = editData.data[weekday];
      if (weekData.include) {
        for (let i = 0; i < weekData.timeSlots.length; i++) {
          // extracting hours and minutes separately and converting them to numbers.
          const [fromHour, fromMinute] = weekData.timeSlots[i].from.split(':').map(Number);
          const [toHour, toMinute] = weekData.timeSlots[i].to.split(':').map(Number);

          // checking if the time is between 00:00 24:00
          if (
            fromHour > 24 ||
            toHour > 24 ||
            fromMinute > 59 ||
            toMinute > 59 ||
            (fromHour === 24 && fromMinute > 0) ||
            (toHour === 24 && toMinute > 0)
          ) {
            error.message = 'Enter valid time';

            // checking if the To time is greater than From time
          } else if (toHour < fromHour || (toHour === fromHour && toMinute < fromMinute)) {
            error.message = 'To time is less than From time';
          } else if (i + 1 < weekData.timeSlots.length) {
            const [nextFromHour, nextFromMinute] = weekData.timeSlots[i + 1].from
              .split(':')
              .map(Number);

            // checking if the time is between 00:00 24:00
            if (
              nextFromHour > 24 ||
              nextFromMinute > 59 ||
              (nextFromHour === 24 && nextFromMinute > 0)
            ) {
              error.message = 'Enter valid time';

              // checking if the next From time is greater than current To time
            } else if (
              nextFromHour < toHour ||
              (nextFromHour === toHour && nextFromMinute < toMinute)
            ) {
              error.message = 'Time Intersects at ' + weekday;
            }
          }
        }
      }
    }

    if (error.message.length === 0) {
      node.data = editData;
      editing = false;
      dispatch('updated', { node: node });
    }
  }

  // adding new time slot
  function addNewSlot(weekday: string) {
    editData.data[weekday].timeSlots = [
      ...editData.data[weekday].timeSlots,
      { from: '00:00', to: '00:00' },
    ];
  }

  // remove time slot
  function removeSlot(weekday: string, index: number) {
    console.log(index);
    editData.data[weekday].timeSlots = [
      ...editData.data[weekday].timeSlots.slice(0, index),
      ...editData.data[weekday].timeSlots.slice(index + 1),
    ];
  }
</script>

<Draggable
  {node}
  title={node.data.type}
  class="block w-[18.5rem] rounded-lg border-2 border-amber-400 bg-white shadow dark:border-amber-400 dark:bg-gray-800"
  on:dragEnd
>
  <svelte:fragment slot="headerActions">
    <EditButton on:edit={onEdit} />
    <CloseButton on:close />
  </svelte:fragment>
  <Inlet
    {node}
    {selectedOutlet}
    connected={inletConnected}
    connectable={inletConnectable}
    on:inletSelected
    on:disconnectInlet
  >
    <div class="space-y-2 p-3">
      <!-- eslint-disable-next-line @typescript-eslint/no-unused-vars -->
      {#each Object.entries(node.data.outlets) as [key, value]}
        <Outlet
          {selectedOutlet}
          nodeId={node.data.id}
          outletId={key}
          connected={Boolean(node.data.outlets[key])}
          class="w-full"
          on:outletSelected
          on:disconnectOutlet
        >
          <p class="text-sm font-semibold dark:text-white">
            {key}
          </p>
        </Outlet>
      {/each}
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
          <h3 class="text-xl font-semibold text-gray-900 dark:text-white">
            Weekend Time Condition
          </h3>
          <button
            type="button"
            class="text-gray-400 bg-transparent hover:bg-gray-200 hover:text-gray-900 rounded-lg text-sm w-8 h-8 ml-auto inline-flex justify-center items-center dark:hover:bg-gray-600 dark:hover:text-white"
            on:click={() => (editing = false)}
          >
            <CloseIcon />
          </button>
        </div>
        {#if error.message.length > 0}
          <ErrorMessage {error} />
        {/if}
        <!-- Modal body -->
        <div class="p-6 space-y-6">
          <div>
            <label
              for="timezone"
              class="block mb-2 text-sm font-medium text-gray-900 dark:text-white"
            >
              Timezone
            </label>
            <select
              id="timezone"
              bind:value={editData.data.timezone}
              class="bg-gray-50 border border-gray-300 text-gray-900 text-sm rounded-lg focus:ring-blue-500 focus:border-blue-500 block w-full p-2.5 dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500"
            >
              {#each timezones as timezone}
                <option value={timezone}>{timezone}</option>
              {/each}
            </select>
          </div>
          <div class="relative overflow-x-auto overflow-y-auto max-h-[545px]">
            <table class="w-full text-sm text-left text-gray-500 dark:text-gray-400">
              <thead
                class="text-xs text-gray-700 uppercase bg-gray-50 dark:bg-gray-700 dark:text-gray-400"
              >
                <tr>
                  <th scope="col" class="px-6 py-3">Include</th>
                  <th scope="col" class="px-6 py-3">Weekday</th>
                  <th scope="col" class="px-6 py-3">Start</th>
                  <th scope="col" class="px-6 py-3">End</th>
                </tr>
              </thead>
              <tbody>
                {#each weekdays as weekday}
                  <tr class="bg-white border-b dark:bg-gray-800 dark:border-gray-700">
                    <td class="px-6 py-4">
                      <input
                        type="checkbox"
                        bind:checked={editData.data[weekday].include}
                        class="w-4 h-4 text-blue-600 bg-gray-100 border-gray-300 rounded focus:ring-blue-500 dark:focus:ring-blue-600 dark:ring-offset-gray-800 focus:ring-2 dark:bg-gray-700 dark:border-gray-600"
                      />
                    </td>
                    <td class="px-6 py-4">{weekday}</td>
                    <td class="px-6 py-4">
                      {#each editData.data[weekday].timeSlots as timeSlot, idx}
                        <input
                          type="text"
                          class="bg-gray-50 border border-gray-300 text-gray-900 text-sm rounded-lg focus:ring-blue-500 focus:border-blue-500 block w-24 p-2.5 dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500 my-4"
                          placeholder="00:00"
                          required
                          bind:value={timeSlot.from}
                        />
                      {/each}
                    </td>
                    <td class="px-6 py-4">
                      {#each editData.data[weekday].timeSlots as timeSlot, idx}
                        <div class="flex items-center">
                          <input
                            type="text"
                            class="bg-gray-50 border border-gray-300 text-gray-900 text-sm rounded-lg focus:ring-blue-500 focus:border-blue-500 block w-24 p-2.5 dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500 my-2"
                            placeholder="23:59"
                            required
                            bind:value={timeSlot.to}
                          />
                          {#if editData.data[weekday].timeSlots.length > 1}
                            <button
                              type="button"
                              on:click={() => removeSlot(weekday, idx)}
                              class="text-blue-700 hover:bg-blue-700 hover:text-white focus:ring-4 focus:outline-none focus:ring-blue-300 font-bold rounded-full text-sm p-1 text-center inline-flex items-center dark:border-blue-500 dark:text-blue-500 dark:hover:text-white dark:focus:ring-blue-800 dark:hover:bg-blue-500 ml-1"
                            >
                              <MinusSignIcon />
                            </button>
                          {/if}
                          {#if idx === editData.data[weekday].timeSlots.length - 1}
                            <button
                              type="button"
                              on:click={() => addNewSlot(weekday)}
                              class="text-blue-700 hover:bg-blue-700 hover:text-white focus:ring-4 focus:outline-none focus:ring-blue-300 font-bold rounded-full text-sm p-1 text-center inline-flex items-center dark:border-blue-500 dark:text-blue-500 dark:hover:text-white dark:focus:ring-blue-800 dark:hover:bg-blue-500 ml-1"
                            >
                              <PlusIcon />
                            </button>
                          {/if}
                        </div>
                      {/each}
                    </td>
                  </tr>
                {/each}
              </tbody>
            </table>
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
