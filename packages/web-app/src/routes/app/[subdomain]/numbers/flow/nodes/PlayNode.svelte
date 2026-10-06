<script lang="ts">
  import { onMount } from 'svelte';
  import type { PlayNode } from './PlayNode';
  import type { NodeProps } from './NodeProps';
  import { routeParam } from '$lib/routeParam';
  import Draggable from '../utils/Draggable.svelte';
  import Inlet from '../utils/Inlet.svelte';
  import CloseButton from '../utils/CloseButton.svelte';
  import EditButton from '../utils/EditButton.svelte';
  import AudioPlayer from './AudioPlayer.svelte';
  import { deleteS3File, extractFilenameFromS3Url } from '../utils/DeleteUploads';
  import MediaUploadRecord from '$lib/components/MediaUploadRecord.svelte';
  import { getPlaybackUrl } from '$lib/playback';
  import type { AudioChangePayload } from '../AudioChangedPayload';
  import { uploadRecording } from '../uploadRecording';
  import Button from '$lib/components/Button.svelte';
  import Dialog from '$lib/components/Dialog.svelte';
  import Hint from '$lib/components/form/Hint.svelte';
  import Label from '$lib/components/form/Label.svelte';
  import SecondaryButton from '$lib/components/form/SecondaryButton.svelte';

  let {
    node,
    inletConnected = false,
    inletConnectable = false,
    onClose,
    onInletSelected,
    onDisconnectInlet,
    onDragEnd,
    onStatusChanged,
  }: NodeProps<PlayNode> = $props();
  let editing = $state(false);
  let deleteFileName = '';
  let savedMediaURL = $state('');
  const subdomain = routeParam('subdomain');

  let changedAudio: AudioChangePayload | undefined = $state();

  export async function triggerUpload() {
    if (changedAudio) {
      onStatusChanged?.({ nodeId: node.data.id, status: 'uploading' });
      const s3Url = await uploadRecording(routeParam('subdomain'), changedAudio);
      onStatusChanged?.({ nodeId: node.data.id, status: 'completed' });
      if (s3Url) {
        editing = false;
        node.data.data.media = s3Url; // Update the node data with the S3 URL
        if (deleteFileName) {
          await deleteS3File(subdomain, deleteFileName);
        }
      } else {
        throw Error('User is not a member of this org');
      }
    }
  }

  onMount(async () => {
    if (node.data.data.media && node.data.data.media.startsWith('s3://')) {
      const fileName = extractFilenameFromS3Url(node.data.data.media);
      savedMediaURL = getPlaybackUrl(subdomain, fileName);
    }
  });

  function onAudioChange(audio: AudioChangePayload) {
    changedAudio = audio;
  }

  function onUpdate() {
    editing = false;
    if (changedAudio) {
      if (node.data.data.media) {
        deleteFileName = node.data.data.media;
      }
    }
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
    <div class="space-y-2 p-3">
      <p class="text-xs font-semibold uppercase tracking-wide text-slate-500 dark:text-slate-300">
        Audio
      </p>
      {#if changedAudio}
        <p class="text-sm text-slate-600 dark:text-slate-300">New audio, uploaded when you save.</p>
      {:else if savedMediaURL}
        <div class="flex items-center gap-2">
          <AudioPlayer src={savedMediaURL} />
          <span class="text-sm text-slate-600 dark:text-slate-300">Play the recording</span>
        </div>
      {:else}
        <p class="text-sm text-slate-600 dark:text-slate-300">
          No audio yet. Edit this step to add one.
        </p>
      {/if}
    </div>
  </Inlet>
</Draggable>

<Dialog
  showDialog={editing}
  title="Play"
  description="Plays a recording to the caller."
  onClose={() => (editing = false)}
>
  <div>
    <Label tag="p">Audio</Label>
    <MediaUploadRecord nodeId={node.data.id} audioUrl={savedMediaURL} {onAudioChange} />
    <Hint>Choose an audio file or record one here.</Hint>
  </div>
  <div class="flex flex-wrap items-center gap-3 pt-2">
    <Button onclick={onUpdate}>Save</Button>
    <SecondaryButton onclick={() => (editing = false)}>Cancel</SecondaryButton>
  </div>
</Dialog>
