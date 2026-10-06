<script lang="ts">
  import type { DialNode } from './DialNode';
  import type { NodeProps } from './NodeProps';
  import Draggable from '../utils/Draggable.svelte';
  import Inlet from '../utils/Inlet.svelte';
  import CloseButton from '../utils/CloseButton.svelte';
  import EditButton from '../utils/EditButton.svelte';
  import { isValidPhoneNumber } from 'libphonenumber-js';
  import Outlet from '../utils/Outlet.svelte';
  import { searchMemberUsernames } from '../utils/searchMembers';
  import { routeParam } from '$lib/routeParam';
  import Button from '$lib/components/Button.svelte';
  import Dialog from '$lib/components/Dialog.svelte';
  import CheckboxRow from '$lib/components/form/CheckboxRow.svelte';
  import Field from '$lib/components/form/Field.svelte';
  import Input from '$lib/components/form/Input.svelte';
  import SecondaryButton from '$lib/components/form/SecondaryButton.svelte';
  import SuggestInput from '$lib/components/form/SuggestInput.svelte';

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
  }: NodeProps<DialNode> = $props();

  // A working copy for the edit form; saved into the node on Update.
  // svelte-ignore state_referenced_locally
  let editData = $state(JSON.parse(JSON.stringify(node.data)));
  let editing = $state(false);

  let suggestions: string[] = $state([]);
  let inputError = $state('');

  const subdomain = routeParam('subdomain');

  async function fetchSuggestions(userInput: string) {
    inputError = '';
    if (!isValidPhoneNumber(userInput)) {
      if (userInput.length < 3) {
        suggestions = [];
      } else {
        suggestions = await searchMemberUsernames(subdomain, userInput);
      }
    }
  }

  async function onUpdate() {
    let userInput = editData.data.to;
    if (!isValidPhoneNumber(userInput)) {
      const usernames = await searchMemberUsernames(subdomain, userInput);
      if (!usernames.includes(userInput)) {
        inputError = 'Please enter a valid username/number';
        return;
      }
    }
    if (editData.data.timeout > 60) {
      editData.data.timeout = 60;
    }
    node.data = $state.snapshot(editData);
    editing = false;
  }
</script>

<Draggable
  {node}
  title={node.data.type}
  class="block w-[17rem] rounded-lg border-2 border-amber-400 bg-white shadow dark:border-amber-400 dark:bg-gray-800"
  {onDragEnd}
>
  {#snippet headerActions()}
    <EditButton onEdit={() => (editing = true)} />
    <CloseButton {onClose} />
  {/snippet}
  <Inlet
    {node}
    connected={inletConnected}
    connectable={inletConnectable}
    {onInletSelected}
    {onDisconnectInlet}
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
        {onOutletSelected}
        {onDisconnectOutlet}
      >
        <p class="text-center text-sm font-semibold dark:text-white">Timeout</p>
      </Outlet>
    </div>
  </Inlet>
</Draggable>

<Dialog
  showDialog={editing}
  title="Dial"
  description="Ring one team member or phone number."
  onClose={() => (editing = false)}
>
  <Field
    for={`dial-to-${node.data.id}`}
    label="Username or number"
    hint="Type three or more letters to find a team member, or enter a phone number."
    error={inputError}
  >
    <SuggestInput
      id={`dial-to-${node.data.id}`}
      placeholder="Enter username/number"
      bind:value={editData.data.to}
      {suggestions}
      invalid={Boolean(inputError)}
      oninput={fetchSuggestions}
    />
  </Field>
  <Field for={`dial-timeout-${node.data.id}`} label="Timeout" hint="From 1 to 60.">
    <Input
      id={`dial-timeout-${node.data.id}`}
      type="number"
      min="1"
      max="60"
      bind:value={editData.data.timeout}
    />
  </Field>
  <CheckboxRow
    id={`dial-spoof-${node.data.id}`}
    label="Spoof number"
    description="Spoofing works only if the SIP trunk associated with the number supports it."
    bind:checked={editData.data.shouldSpoof}
  />
  <div class="flex flex-wrap items-center gap-3 pt-2">
    <Button onclick={onUpdate}>Save</Button>
    <SecondaryButton onclick={() => (editing = false)}>Cancel</SecondaryButton>
  </div>
</Dialog>
