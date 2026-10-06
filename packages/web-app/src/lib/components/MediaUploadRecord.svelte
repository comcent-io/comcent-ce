<script lang="ts" module>
  export type AudioChange = {
    audioUrl: string;
    audioBlob: Blob;
    mimeType: string;
    fileName: string;
  };
</script>

<script lang="ts">
  import SecondaryButton from '$lib/components/form/SecondaryButton.svelte';

  // An audio clip to upload: a player for the current one, and buttons to
  // choose a file or record a new one in the browser.
  interface Props {
    audioUrl?: string;
    nodeId?: string;
    onAudioChange?: (audio: AudioChange) => void;
  }

  let { audioUrl = '', nodeId = '', onAudioChange }: Props = $props();

  let fileInput: HTMLInputElement | null = $state(null);
  let mimeType = '';
  let changedAudioUrl = $state('');
  let recording = $state(false);
  let mediaRecorder: MediaRecorder | null = null;
  let audioChunks: Blob[] = [];
  let recordingDuration = $state(0);
  let durationInterval: ReturnType<typeof setInterval>;

  const formatDuration = (duration: number) =>
    `${Math.floor(duration / 60)
      .toString()
      .padStart(2, '0')}:${(duration % 60).toString().padStart(2, '0')}`;

  async function onRecordingStop() {
    mimeType = mediaRecorder!.mimeType;
    const audioBlob = new Blob(audioChunks, { type: mediaRecorder!.mimeType });
    audioChunks = [];
    mediaRecorder = null;
    changedAudioUrl = URL.createObjectURL(audioBlob);
    onAudioChange?.({
      audioUrl: changedAudioUrl,
      audioBlob,
      mimeType,
      fileName: generateFileName(),
    });
  }

  async function startRecording() {
    const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
    mediaRecorder = new MediaRecorder(stream);
    mediaRecorder.ondataavailable = (e) => audioChunks.push(e.data);
    mediaRecorder.onstop = onRecordingStop;

    resetRecording();
    mediaRecorder.start();
    recording = true;
    durationInterval = setInterval(() => recordingDuration++, 1000);
  }

  async function stopRecording() {
    mediaRecorder?.stop();
    recording = false;
    clearInterval(durationInterval);
  }

  function resetRecording() {
    audioChunks = [];
    recordingDuration = 0;
    clearInterval(durationInterval);
  }

  function generateFileName() {
    const timestamp = new Date().getTime();
    const id = nodeId || 'playnode';
    let extension;
    if (mimeType.includes('wav')) {
      extension = 'wav';
    } else if (mimeType.includes('webm')) {
      extension = 'webm';
    }
    if (!extension) {
      const message = `Audio extension not supported ${extension}`;
      alert(message);
      throw Error(message);
    }
    return `node_audio_${id}_${timestamp}.${extension}`;
  }

  function fileChanged(event: Event): void {
    const input = event.target as HTMLInputElement;
    if (!input.files || input.files.length === 0) return;

    const file = input.files[0];
    mimeType = file.type;

    const reader = new FileReader();
    reader.onload = (e) => {
      const audioBlob = new Blob([e.target!.result as ArrayBuffer], { type: mimeType });
      changedAudioUrl = URL.createObjectURL(audioBlob);
      onAudioChange?.({
        audioUrl: changedAudioUrl,
        audioBlob,
        mimeType: input.files![0].type,
        fileName: generateFileName(),
      });
    };
    reader.readAsArrayBuffer(input.files[0]);
  }
</script>

<div class="space-y-3">
  <audio class="w-full" src={changedAudioUrl || audioUrl} controls></audio>
  <input type="file" bind:this={fileInput} onchange={fileChanged} accept="audio/*" hidden />
  <div class="flex flex-wrap items-center gap-3">
    <SecondaryButton size="sm" onclick={() => fileInput?.click()}>Choose file</SecondaryButton>
    <SecondaryButton
      size="sm"
      tone={recording ? 'danger' : 'default'}
      onclick={() => (recording ? stopRecording() : startRecording())}
    >
      {recording ? 'Stop recording' : 'Record'}
    </SecondaryButton>
    {#if recording}
      <span class="text-sm font-medium tabular-nums text-gray-700 dark:text-gray-300">
        {formatDuration(recordingDuration)}
      </span>
    {/if}
  </div>
</div>
