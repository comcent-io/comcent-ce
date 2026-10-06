<script lang="ts">
  import Draggable from '../utils/Draggable.svelte';
  import Inlet from '../utils/Inlet.svelte';
  import CloseButton from '../utils/CloseButton.svelte';
  import EditButton from '../utils/EditButton.svelte';
  import { isValidPhoneNumber } from 'libphonenumber-js';
  import Outlet from '../utils/Outlet.svelte';
  import { searchMemberUsernames } from '../utils/searchMembers';
  import type { DialGroupNode } from './DialGroupNode';
  import type { NodeProps } from './NodeProps';
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
  }: NodeProps<DialGroupNode> = $props();

  // A working copy for the edit form; saved into the node on Update.
  // svelte-ignore state_referenced_locally
  let editData = $state({
    ...node.data,
    data: {
      to: [...node.data.data.to],
      shouldSpoof: node.data.data.shouldSpoof ?? false,
      timeout: node.data.data.timeout,
    },
  });
  let editing = $state(false);
  let currentInput = $state('');

  let suggestions: string[] = $state([]);
  let inputError = $state('');

  const subdomain = routeParam('subdomain');

  // Enter on typed text: a phone number, or a username from the suggestions.
  function addTyped(text: string) {
    if (editData.data.to.includes(text)) {
      inputError = 'Already exists';
      return;
    }
    if (!isValidPhoneNumber(text) && !suggestions.includes(text)) {
      inputError = 'Please enter a valid username/number';
      return;
    }
    editData.data.to = [...editData.data.to, text];
    currentInput = '';
  }

  async function fetchSuggestions(userInput: string) {
    inputError = '';
    if (!isValidPhoneNumber(userInput)) {
      if (userInput.length < 3) {
        suggestions = [];
      } else {
        const usernames = await searchMemberUsernames(subdomain, userInput);
        suggestions = usernames.filter((username) => !editData.data.to.includes(username));
      }
    }
  }

  async function onUpdate() {
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
      <p class="truncate text-sm font-medium text-slate-800 dark:text-white">
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
        <p class="text-sm font-semibold dark:text-white">Timeout</p>
      </Outlet>
    </div>
  </Inlet>
</Draggable>

<Dialog
  showDialog={editing}
  title="Dial group"
  description="Ring several team members or phone numbers."
  onClose={() => (editing = false)}
>
  <Field
    for={`dial-group-to-${node.data.id}`}
    label="Usernames or numbers"
    hint="Type three or more letters to find a team member, or enter a phone number and press Enter."
    error={inputError}
  >
    <SuggestInput
      id={`dial-group-to-${node.data.id}`}
      placeholder={editData.data.to.length === 0 ? 'Add a username or number' : ''}
      bind:value={currentInput}
      bind:values={editData.data.to}
      {suggestions}
      invalid={Boolean(inputError)}
      oninput={fetchSuggestions}
      onadd={addTyped}
    />
  </Field>
  <Field for={`dial-group-timeout-${node.data.id}`} label="Timeout" hint="From 1 to 60.">
    <Input
      id={`dial-group-timeout-${node.data.id}`}
      type="number"
      min="1"
      max="60"
      bind:value={editData.data.timeout}
    />
  </Field>
  <CheckboxRow
    id={`dial-group-spoof-${node.data.id}`}
    label="Spoof number"
    description="Spoofing works only if the SIP trunk associated with the number supports it."
    bind:checked={editData.data.shouldSpoof}
  />
  <div class="flex flex-wrap items-center gap-3 pt-2">
    <Button onclick={onUpdate}>Save</Button>
    <SecondaryButton onclick={() => (editing = false)}>Cancel</SecondaryButton>
  </div>
</Dialog>
