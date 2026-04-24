<script lang="ts">
  import { createEventDispatcher } from 'svelte';
  const dispatch = createEventDispatcher();

  export let audioUrl = '';
  export let nodeId = '';

  let fileInput: HTMLInputElement | null = null;
  let mimeType = '';
  let changedAudioUrl = '';
  let recording = false;
  let mediaRecorder: MediaRecorder | null = null;
  let audioChunks: Blob[] = [];
  let recordingDuration = 0;
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
    dispatch('audioChange', {
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
      dispatch('audioChange', {
        audioUrl: changedAudioUrl,
        audioBlob,
        mimeType: input.files![0].type,
        fileName: generateFileName(),
      });
    };
    reader.readAsArrayBuffer(input.files[0]);
  }
</script>

<div class="flex items-center justify-between">
  <audio src={changedAudioUrl || audioUrl} controls></audio>
  <input type="file" bind:this={fileInput} on:change={fileChanged} accept="audio/*" hidden />
  <button
    class="ml-2 text-white bg-blue-500 hover:bg-blue-600 p-2 rounded"
    on:click|preventDefault={() => fileInput?.click()}
    title="Select audio file from your computer"
  >
    Browse📂
    <span class="sr-only">Select audio file</span>
  </button>
  <button
    class="ml-2 text-white bg-red-500 hover:bg-red-600 p-2 rounded min-w-23 flex items-center justify-center"
    on:click|preventDefault={recording ? stopRecording : startRecording}
    title={recording ? 'Stop recording' : 'Start recording'}
  >
    {recording ? 'Stop   ⏹️' : 'Record ⏺️'}
    <span class="sr-only">{recording ? 'Stop recording' : 'Start recording'}</span>
  </button>

  {#if recording}
    <span class="ml-0 text-sm font-semibold text-white p-4">
      {formatDuration(recordingDuration)}
    </span>
  {/if}
</div>
