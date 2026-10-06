<script lang="ts">
  import type { WeekTimeNode } from './WeekTimeNode';
  import type { NodeProps } from './NodeProps';
  import Draggable from '../utils/Draggable.svelte';
  import Inlet from '../utils/Inlet.svelte';
  import Outlet from '../utils/Outlet.svelte';
  import CloseButton from '../utils/CloseButton.svelte';
  import EditButton from '../utils/EditButton.svelte';
  import moment from 'moment-timezone';
  import Button from '$lib/components/Button.svelte';
  import Dialog from '$lib/components/Dialog.svelte';
  import Checkbox from '$lib/components/form/Checkbox.svelte';
  import Field from '$lib/components/form/Field.svelte';
  import Hint from '$lib/components/form/Hint.svelte';
  import Input from '$lib/components/form/Input.svelte';
  import RemoveButton from '$lib/components/form/RemoveButton.svelte';
  import SecondaryButton from '$lib/components/form/SecondaryButton.svelte';
  import Select from '$lib/components/form/Select.svelte';

  let {
    node,
    selectedOutlet,
    inletConnected = false,
    inletConnectable = false,
    onClose,
    onOutletSelected,
    onDisconnectOutlet,
    onInletSelected,
    onDisconnectInlet,
    onDragEnd,
  }: NodeProps<WeekTimeNode> = $props();

  // A working copy for the edit form; saved into the node on Update.
  // svelte-ignore state_referenced_locally
  let editData = $state(JSON.parse(JSON.stringify(node.data)));
  let editing = $state(false);

  const weekdays = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
  const weekdayNames: Record<string, string> = {
    mon: 'Monday',
    tue: 'Tuesday',
    wed: 'Wednesday',
    thu: 'Thursday',
    fri: 'Friday',
    sat: 'Saturday',
    sun: 'Sunday',
  };
  const timezones = moment.tz.names();
  function onEdit() {
    editing = true;
  }

  let errorMessage = $state('');
  function onUpdate() {
    errorMessage = '';
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
            errorMessage = 'Enter valid time';

            // checking if the To time is greater than From time
          } else if (toHour < fromHour || (toHour === fromHour && toMinute < fromMinute)) {
            errorMessage = 'To time is less than From time';
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
              errorMessage = 'Enter valid time';

              // checking if the next From time is greater than current To time
            } else if (
              nextFromHour < toHour ||
              (nextFromHour === toHour && nextFromMinute < toMinute)
            ) {
              errorMessage = 'Time Intersects at ' + weekday;
            }
          }
        }
      }
    }

    if (errorMessage.length === 0) {
      node.data = $state.snapshot(editData);
      editing = false;
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
  {onDragEnd}
>
  {#snippet headerActions()}
    <EditButton {onEdit} />
    <CloseButton {onClose} />
  {/snippet}
  <Inlet
    {node}
    connected={inletConnected}
    connectable={inletConnectable}
    {onInletSelected}
    {onDisconnectInlet}
  >
    <div class="space-y-2 p-3">
      <!-- eslint-disable-next-line @typescript-eslint/no-unused-vars -->
      {#each Object.entries(node.data.outlets) as [key, value]}
        <Outlet
          {selectedOutlet}
          nodeId={node.data.id}
          outletId={key}
          connected={Boolean(node.data.outlets[key as keyof typeof node.data.outlets])}
          class="w-full"
          {onOutletSelected}
          {onDisconnectOutlet}
        >
          <p class="text-sm font-semibold dark:text-white">
            {key}
          </p>
        </Outlet>
      {/each}
    </div>
  </Inlet>
</Draggable>

<Dialog
  showDialog={editing}
  title="Week time"
  description="Tick the days and hours that count as “true”. Any other time is “false”."
  className="max-w-2xl"
  onClose={() => (editing = false)}
>
  <Field for={`week-time-zone-${node.data.id}`} label="Timezone">
    <Select id={`week-time-zone-${node.data.id}`} bind:value={editData.data.timezone}>
      {#each timezones as timezone}
        <option value={timezone}>{timezone}</option>
      {/each}
    </Select>
  </Field>

  <div
    class="divide-y divide-gray-200 rounded-lg border border-gray-200 dark:divide-gray-700 dark:border-gray-700"
  >
    {#each weekdays as weekday}
      <div class="flex flex-wrap items-start gap-x-6 gap-y-2 px-4 py-3">
        <label
          class="flex w-32 shrink-0 cursor-pointer items-center gap-3 py-2.5 text-sm font-medium text-gray-900 dark:text-white"
        >
          <Checkbox bind:checked={editData.data[weekday].include} />
          {weekdayNames[weekday]}
        </label>
        <div class="space-y-2">
          {#each editData.data[weekday].timeSlots as timeSlot, idx}
            <div class="flex items-center gap-2">
              <div class="w-24">
                <Input
                  type="text"
                  placeholder="00:00"
                  aria-label={`${weekdayNames[weekday]} from`}
                  required
                  bind:value={timeSlot.from}
                />
              </div>
              <span class="text-sm text-gray-500 dark:text-gray-400">to</span>
              <div class="w-24">
                <Input
                  type="text"
                  placeholder="23:59"
                  aria-label={`${weekdayNames[weekday]} to`}
                  required
                  bind:value={timeSlot.to}
                />
              </div>
              {#if editData.data[weekday].timeSlots.length > 1}
                <RemoveButton label="Remove these hours" onclick={() => removeSlot(weekday, idx)} />
              {/if}
              {#if idx === editData.data[weekday].timeSlots.length - 1}
                <SecondaryButton size="sm" onclick={() => addNewSlot(weekday)}>
                  + Add hours
                </SecondaryButton>
              {/if}
            </div>
          {/each}
        </div>
      </div>
    {/each}
  </div>

  {#if errorMessage}
    <Hint error>{errorMessage}</Hint>
  {/if}
  <div class="flex flex-wrap items-center gap-3 pt-2">
    <Button onclick={onUpdate}>Save</Button>
    <SecondaryButton onclick={() => (editing = false)}>Cancel</SecondaryButton>
  </div>
</Dialog>
