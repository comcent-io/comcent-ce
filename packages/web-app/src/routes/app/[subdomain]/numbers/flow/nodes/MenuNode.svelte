<script lang="ts">
  import { onMount } from 'svelte';
  import type { MenuNode } from './MenuNode';
  import type { NodeProps } from './NodeProps';
  import type { SelectedOutlet } from '../SelectedOutlet';
  import { page } from '$app/state';
  import { routeParam } from '$lib/routeParam';
  import Draggable from '../utils/Draggable.svelte';
  import Inlet from '../utils/Inlet.svelte';
  import CloseButton from '../utils/CloseButton.svelte';
  import EditButton from '../utils/EditButton.svelte';
  import AudioPlayer from './AudioPlayer.svelte';
  import { deleteS3File, extractFilenameFromS3Url } from '../utils/DeleteUploads';
  import Outlet from '../utils/Outlet.svelte';
  import MediaUploadRecord from '$lib/components/MediaUploadRecord.svelte';
  import { getPlaybackUrl } from '$lib/playback';
  import type { AudioChangePayload } from '../AudioChangedPayload';
  import { uploadRecording } from '../uploadRecording';
  import Button from '$lib/components/Button.svelte';
  import Dialog from '$lib/components/Dialog.svelte';
  import Field from '$lib/components/form/Field.svelte';
  import Input from '$lib/components/form/Input.svelte';
  import Label from '$lib/components/form/Label.svelte';
  import SecondaryButton from '$lib/components/form/SecondaryButton.svelte';

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
  }: NodeProps<MenuNode> = $props();

  let newOutletKey = $state('');
  let addingOption = $state(false);
  let errorMessage = $state('');

  // A working copy for the edit form; saved into the node on Update.
  // svelte-ignore state_referenced_locally
  let editData = $state(JSON.parse(JSON.stringify(node.data)));
  let editing = $state(false);

  let audioRecordingURLs = $state({
    savedPromptAudioURL: '',
    savedErrorAudioURL: '',
    promptAudioURL: '',
    errorAudioURL: '',
  });

  let updatedFiles: Record<string, AudioChangePayload> = {};
  let oldFiles: Record<string, string> = {};
  let isMainContentLoaded = $state(false);

  let changedPromptAudio: AudioChangePayload | undefined;
  let changedErrorAudio: AudioChangePayload | undefined;

  const subdomain = routeParam('subdomain');

  export async function triggerUpload() {
    if (Object.keys(updatedFiles).length > 0) {
      for (let key in updatedFiles) {
        const changedAudio = updatedFiles[key];
        const s3Url = await uploadRecording(routeParam('subdomain'), changedAudio);
        if (s3Url) {
          if (key === 'prompt') {
            node.data.data.promptAudio = s3Url; // Update the node data with the S3 URL
          } else {
            node.data.data.errorAudio = s3Url;
          }
          if (oldFiles[key]) {
            await deleteS3File(subdomain, oldFiles[key]);
          }
        } else {
          throw Error('User is not a member of this org');
        }
      }
      editing = false;
    }
  }

  onMount(async () => {
    if (node.data.data.promptAudio?.startsWith('s3://')) {
      const fileName = extractFilenameFromS3Url(node.data.data.promptAudio);
      audioRecordingURLs.savedPromptAudioURL = getPlaybackUrl(subdomain, fileName);
    }
    if (node.data.data.errorAudio?.startsWith('s3://')) {
      const fileName = extractFilenameFromS3Url(node.data.data.errorAudio);
      audioRecordingURLs.savedErrorAudioURL = getPlaybackUrl(subdomain, fileName);
    }
    audioRecordingURLs.promptAudioURL = audioRecordingURLs.savedPromptAudioURL;
    audioRecordingURLs.errorAudioURL = audioRecordingURLs.savedErrorAudioURL;
    isMainContentLoaded = true;
  });

  function onPromptAudioChange(audio: AudioChangePayload) {
    changedPromptAudio = audio;
  }

  function onErrorAudioChange(audio: AudioChangePayload) {
    changedErrorAudio = audio;
  }

  function onUpdate() {
    node.data = $state.snapshot(editData);
    editing = false;
    if (changedPromptAudio) {
      updatedFiles['prompt'] = changedPromptAudio;
      oldFiles['prompt'] = node.data.data.promptAudio;
    }
    if (changedErrorAudio) {
      updatedFiles['error'] = changedErrorAudio;
      oldFiles['error'] = node.data.data.errorAudio;
    }
  }

  function tryAddOutlet() {
    errorMessage = '';
    const normalizedOutletKey = newOutletKey.trim();

    if (normalizedOutletKey === '') {
      errorMessage = 'Enter the digits callers should press.';
      return;
    }

    if (!/^\d+$/.test(normalizedOutletKey)) {
      errorMessage = 'Use digits only, like 1, 2, or 12.';
      return;
    }

    if (!(normalizedOutletKey in node.data.outlets)) {
      node.data.outlets[normalizedOutletKey] = '';
      newOutletKey = '';
      addingOption = false;
    } else {
      errorMessage = normalizedOutletKey + ' already exists.';
    }
  }

  function handleKeydown(event: KeyboardEvent) {
    if (event.key === 'Enter') {
      event.preventDefault();
      tryAddOutlet();
    }
  }

  function handleDeleteOutlet({ outletId }: SelectedOutlet) {
    delete node.data.outlets[outletId];
  }

  function showAddOption() {
    errorMessage = '';
    addingOption = true;
  }

  function cancelAddOption() {
    addingOption = false;
    newOutletKey = '';
    errorMessage = '';
  }
</script>

<Draggable
  {node}
  title={node.data.type}
  class="block w-[18.5rem] rounded-lg border-2 border-amber-400 bg-white shadow dark:border-amber-400 dark:bg-gray-800"
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
    <div class="space-y-3 p-3">
      <div
        class="rounded-lg border border-amber-200 bg-amber-50/80 p-3 text-sm text-amber-950 dark:border-amber-700 dark:bg-amber-950/40 dark:text-amber-100"
      >
        <p class="font-semibold">Menu prompt</p>
        <p class="mt-1 text-xs leading-5 text-amber-900/80 dark:text-amber-100/80">
          Play a recording like “Press 1 for sales, press 2 for support” and route each digit choice
          below.
        </p>
      </div>

      {#if node.data.data.promptAudio && isMainContentLoaded}
        <div
          class="flex items-center gap-2 rounded-lg border border-slate-200 bg-slate-50 px-3 py-2 dark:border-slate-700 dark:bg-slate-900/60"
        >
          <h3 class="text-sm font-medium dark:text-white">Prompt audio</h3>
          <AudioPlayer src={audioRecordingURLs.savedPromptAudioURL} />
        </div>
      {/if}

      {#if node.data.data.errorAudio && isMainContentLoaded}
        <div
          class="flex items-center gap-2 rounded-lg border border-slate-200 bg-slate-50 px-3 py-2 dark:border-slate-700 dark:bg-slate-900/60"
        >
          <h3 class="text-sm font-medium dark:text-white">Error audio</h3>
          <AudioPlayer src={audioRecordingURLs.savedErrorAudioURL} />
        </div>
      {/if}
    </div>
    <div class="px-3 pb-3">
      <div class="mb-3 flex items-center justify-between gap-3">
        <div>
          <h4
            class="text-sm font-semibold uppercase tracking-wide text-slate-500 dark:text-slate-300"
          >
            Digit routes
          </h4>
          <p class="mt-1 text-xs text-slate-500 dark:text-slate-400">
            Add one route for each digit or digit combination callers can press.
          </p>
        </div>
        {#if !addingOption}
          <SecondaryButton size="sm" class="shrink-0" onclick={showAddOption}>
            Add option
          </SecondaryButton>
        {/if}
      </div>

      {#if addingOption}
        <div class="mb-3 space-y-3 rounded-lg border border-gray-200 p-3 dark:border-gray-700">
          <Field
            for={`menu-option-${node.data.id}`}
            label="Digits callers press"
            hint="A single digit or a combination like 12. Each entry becomes its own route out."
            error={errorMessage}
          >
            <Input
              id={`menu-option-${node.data.id}`}
              type="text"
              inputmode="numeric"
              placeholder="1"
              invalid={Boolean(errorMessage)}
              bind:value={newOutletKey}
              onkeydown={handleKeydown}
            />
          </Field>
          <div class="flex items-center gap-2">
            <Button onclick={tryAddOutlet}>Add</Button>
            <SecondaryButton onclick={cancelAddOption}>Cancel</SecondaryButton>
          </div>
        </div>
      {/if}

      {#if Object.keys(node.data.outlets).length === 0}
        <div
          class="rounded-lg border border-dashed border-gray-300 px-4 py-5 text-sm text-gray-500 dark:border-gray-600 dark:text-gray-400"
        >
          No digit routes yet. Add the first option to create a route callers can press.
        </div>
      {/if}

      {#each Object.entries(node.data.outlets) as [key]}
        <Outlet
          {selectedOutlet}
          nodeId={node.data.id}
          outletId={key}
          connected={Boolean(node.data.outlets[key])}
          isDeletable={true}
          class="w-full text-left"
          {onOutletSelected}
          {onDisconnectOutlet}
          onDeleteOutlet={handleDeleteOutlet}
        >
          <div class="pr-8">
            <p
              class="text-xs font-semibold uppercase tracking-wide text-slate-500 dark:text-slate-400"
            >
              Caller presses
            </p>
            <p class="mt-1 text-base font-semibold text-slate-900 dark:text-white">
              {key}
            </p>
          </div>
        </Outlet>
      {/each}
    </div>
  </Inlet>
</Draggable>

<Dialog
  showDialog={editing}
  title="Menu"
  description="Plays a prompt and routes the caller by the digits they press."
  onClose={() => (editing = false)}
>
  <div>
    <Label tag="p">Prompt audio</Label>
    <MediaUploadRecord
      audioUrl={audioRecordingURLs.promptAudioURL}
      nodeId={node.data.id}
      onAudioChange={onPromptAudioChange}
    />
  </div>
  <div>
    <Label tag="p">Error audio</Label>
    <MediaUploadRecord
      audioUrl={audioRecordingURLs.errorAudioURL}
      nodeId={node.data.id}
      onAudioChange={onErrorAudioChange}
    />
  </div>
  <div class="grid gap-4 sm:grid-cols-3">
    <Field for={`menu-repeat-${node.data.id}`} label="Repeat error audio">
      <Input
        id={`menu-repeat-${node.data.id}`}
        type="number"
        placeholder="3"
        required
        bind:value={editData.data.repeat}
      />
    </Field>
    <Field for={`menu-prompt-wait-${node.data.id}`} label="Wait time after prompt">
      <Input
        id={`menu-prompt-wait-${node.data.id}`}
        type="number"
        placeholder="3"
        required
        bind:value={editData.data.afterPromptWaitTime}
      />
    </Field>
    <Field for={`menu-digit-wait-${node.data.id}`} label="Multi-digit wait time">
      <Input
        id={`menu-digit-wait-${node.data.id}`}
        type="number"
        placeholder="3"
        required
        bind:value={editData.data.multiDigitWaitTime}
      />
    </Field>
  </div>
  <div class="flex flex-wrap items-center gap-3 pt-2">
    <Button onclick={onUpdate}>Save</Button>
    <SecondaryButton onclick={() => (editing = false)}>Cancel</SecondaryButton>
  </div>
</Dialog>
