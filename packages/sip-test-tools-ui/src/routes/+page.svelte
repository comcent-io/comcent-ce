<script lang="ts">
  import { onMount } from 'svelte';
  import ActiveCalls from '$lib/components/ActiveCalls.svelte';
  import toast from 'svelte-french-toast';

  type State = {
    fromNumber: string;
    toNumber: string;
    calls: any[];
    status?: string;
    ipAddress?: string;
    trunkStatus?: string;
  };

  let state: State = {
    fromNumber: '',
    toNumber: '',
    calls: [],
  };

  $: dialedCalls = state.calls.filter((call) => call.direction === 'out');
  $: receivedCalls = state.calls.filter((call) => call.direction === 'in');

  let ws: any = null;
  let webRtcConnectionInitiated = false;
  let webRtcPeerConnection: RTCPeerConnection | null = null;
  let audioStream = null;
  let audioElement: HTMLAudioElement | null = null;
  let isWebRtcConnected = false;

  async function setupWebRTC() {
    if (webRtcPeerConnection && webRtcPeerConnection.connectionState == 'connected') {
      console.log('Terminating WebRTC connection...');
      isWebRtcConnected = false;
      // Stop all tracks before closing
      webRtcPeerConnection.getSenders().forEach((sender) => sender.track?.stop());
      webRtcPeerConnection.close();
      webRtcPeerConnection = null;

      // Reset the audio element properly
      if (audioElement) {
        audioElement.srcObject = null;
      }

      webRtcConnectionInitiated = false;
      ws.send(JSON.stringify({ action: 'TerminateWebRtc' }));
      return;
    }

    if (webRtcConnectionInitiated) {
      console.log('WebRTC already being initiated...');
      return;
    }

    webRtcConnectionInitiated = true;

    console.log('Setting up WebRTC...');

    // WebRTC configuration
    const configuration = {
      iceServers: [{ urls: 'stun:stun.l.google.com:19302' }],
    };
    webRtcPeerConnection = new RTCPeerConnection(configuration);

    // Add event listeners
    webRtcPeerConnection.addEventListener('iceconnectionstatechange', () => {
      console.log('ICE connection state:', webRtcPeerConnection?.iceConnectionState);
    });

    webRtcPeerConnection.addEventListener('signalingstatechange', () => {
      console.log('Signaling state:', webRtcPeerConnection?.signalingState);
    });

    webRtcPeerConnection.ontrack = (event) => {
      console.log('ontrack event triggered', event);
      audioStream = event.streams[0];
      audioElement = document.getElementById('remoteAudio') as HTMLAudioElement;
      if (audioElement) {
        audioElement.srcObject = audioStream;
        console.log('Set remote audio stream to audio element');
      }
    };

    // Get user media
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      console.log('Got local media stream with tracks:', stream.getTracks().length);

      stream.getTracks().forEach((track) => {
        console.log('Adding track to peer connection:', track.kind, track.id);
        webRtcPeerConnection!.addTrack(track, stream);
      });
    } catch (err) {
      console.error('Error getting user media:', err);
      toast.error(`Error accessing microphone: ${err}`);
      webRtcConnectionInitiated = false;
      return;
    }

    webRtcPeerConnection.addTransceiver('audio', {
      direction: 'sendrecv',
      sendEncodings: [{ maxBitrate: 64000 }],
    });

    let offerSent = false;

    webRtcPeerConnection.addEventListener('icegatheringstatechange', () => {
      console.log('icegatheringstatechange', webRtcPeerConnection!.iceGatheringState);
      if (webRtcPeerConnection!.iceGatheringState === 'complete' && !offerSent) {
        offerSent = true;
        ws.send(
          JSON.stringify({
            action: 'webRtcOffer',
            offer: webRtcPeerConnection!.localDescription,
          }),
        );
      }
    });

    setTimeout(() => {
      if (!offerSent) {
        offerSent = true;
        ws.send(
          JSON.stringify({
            action: 'webRtcOffer',
            offer: webRtcPeerConnection!.localDescription,
          }),
        );
      }
    }, 3000);

    webRtcPeerConnection.addEventListener('connectionstatechange', () => {
      console.log('connectionstatechange:', webRtcPeerConnection!.connectionState);
      if (webRtcPeerConnection!.connectionState === 'connected') {
        console.log('WebRTC connection established successfully');
        isWebRtcConnected = true;
      } else if (
        webRtcPeerConnection!.connectionState === 'disconnected' ||
        webRtcPeerConnection!.connectionState === 'failed' ||
        webRtcPeerConnection!.connectionState === 'closed'
      ) {
        console.log('WebRTC connection ended');
        isWebRtcConnected = false;
        webRtcConnectionInitiated = false;
        webRtcPeerConnection = null;
      }
    });

    const offer = await webRtcPeerConnection.createOffer();
    await webRtcPeerConnection.setLocalDescription(offer);
  }

  onMount(() => {
    ws = new WebSocket('ws://localhost:8080/ws');
    ws.onmessage = async (e: MessageEvent) => {
      const message = JSON.parse(e.data);
      state = { ...state, ...message };

      console.log('WebSocket message received:', message);

      if (message.type === 'webRtcAnswer') {
        console.log('WebRTC answer received:', message.answer.sdp);
        try {
          await webRtcPeerConnection?.setRemoteDescription(message.answer);
        } catch (error) {
          console.error('Error setting remote description:', error);
          toast.error(`Error setting remote description: ${error}`);
        }
      }
    };

    ws.onopen = async () => {
      console.log('WebSocket connected');
      toast.success('WebSocket connected');
    };

    ws.onerror = (error: ErrorEvent) => {
      console.error('WebSocket error:', error);
      toast.error('WebSocket connection error');
    };

    ws.onclose = () => {
      console.log('WebSocket closed');
      toast.error('WebSocket connection closed');
    };

    const fromNumber = localStorage.getItem('fromNumber');
    if (fromNumber) {
      state.fromNumber = fromNumber;
    }

    const toNumber = localStorage.getItem('toNumber');
    if (toNumber) {
      state.toNumber = toNumber;
    }
  });

  function onDial() {
    localStorage.setItem('fromNumber', state.fromNumber);
    localStorage.setItem('toNumber', state.toNumber);
    ws.send(
      JSON.stringify({ action: 'Dial', fromNumber: state.fromNumber, toNumber: state.toNumber }),
    );
  }

  function onHangUp(callId: string) {
    ws.send(JSON.stringify({ action: 'HangUp', callId: callId }));
  }

  async function onSpeakOrListen(callId: string) {
    if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
      toast.error('Your browser does not support audio recording.');
      return;
    }
    try {
      ws.send(
        JSON.stringify({
          action: 'speakOrListen',
          callId: callId,
        }),
      );
    } catch (error) {
      toast.error('Unable to access the microphone. Please check your browser settings.');
    }
  }

  function onInviteAccepted(callId: string) {
    console.log('onInviteAccepted', callId);
    ws.send(
      JSON.stringify({ action: 'InvitationResponse', isInviteAccepted: true, callId: callId }),
    );
  }
</script>

<div class="flex space-x-10">
  <div
    class="mt-4 block w-80 rounded-lg border border-gray-200 bg-white p-6 shadow hover:bg-gray-100 dark:border-gray-700 dark:bg-gray-800 dark:hover:bg-gray-700"
  >
    <h5 class="mb-2 text-2xl font-bold tracking-tight text-gray-900 dark:text-white">
      SIP Test Tools
    </h5>
    {#if state}
      <p class="font-normal text-gray-700 dark:text-gray-400">
        Status: {state.status}
      </p>
      <p class="font-normal text-gray-700 dark:text-gray-400">
        IP address: {state.ipAddress}
      </p>
      <p class="font-normal text-gray-700 dark:text-gray-400">
        SipTrunkStatus: {state.trunkStatus}
      </p>
    {/if}
  </div>

  <button
    on:click={setupWebRTC}
    class="mt-20 h-10 w-60 rounded-lg bg-blue-700 px-4 py-1 text-sm font-medium text-white hover:bg-blue-800 focus:outline-none focus:ring-4 focus:ring-blue-300 dark:bg-blue-600 dark:hover:bg-blue-700 dark:focus:ring-blue-800"
  >
    {#if isWebRtcConnected}
      Terminate audio connection
    {:else}
      Establish audio connection
    {/if}
  </button>
</div>

<div class="mt-4 grid grid-cols-2 gap-2">
  <div
    class="block rounded-lg border border-gray-200 bg-white p-6 shadow dark:border-gray-700 dark:bg-gray-800"
  >
    <h5 class="mb-2 text-2xl font-bold tracking-tight text-gray-900 dark:text-white">Dialer</h5>

    <div class="mb-6 ml-2 flex space-x-10">
      <input
        type="text"
        class="block h-11 w-80 rounded-lg border border-gray-300 bg-gray-50 p-2 text-sm text-gray-900 focus:border-blue-500 focus:ring-blue-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white dark:placeholder-gray-400 dark:focus:border-blue-500 dark:focus:ring-blue-500"
        placeholder="From Number in E.164 format"
        bind:value={state.fromNumber}
        required
      />

      <input
        type="text"
        class="block h-11 w-80 rounded-lg border border-gray-300 bg-gray-50 p-2 text-sm text-gray-900 focus:border-blue-500 focus:ring-blue-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white dark:placeholder-gray-400 dark:focus:border-blue-500 dark:focus:ring-blue-500"
        placeholder="To Number in E.164 format"
        bind:value={state.toNumber}
        required
      />
      <button
        on:click={onDial}
        type="button"
        disabled={!state.fromNumber || !state.toNumber}
        class="w-20 rounded-lg bg-blue-700 px-4 py-1 text-sm font-medium text-white hover:bg-blue-800 focus:outline-none focus:ring-4 focus:ring-blue-300 dark:bg-blue-600 dark:hover:bg-blue-700 dark:focus:ring-blue-800"
      >
        Dial
      </button>
    </div>

    {#if state}
      <ActiveCalls
        calls={dialedCalls}
        {onSpeakOrListen}
        {onHangUp}
        webRtcConnected={isWebRtcConnected}
      />
      <audio id="remoteAudio" autoplay></audio>
    {/if}
  </div>
  <div
    class="block rounded-lg border border-gray-200 bg-white p-6 shadow dark:border-gray-700 dark:bg-gray-800"
  >
    <h5 class="mb-2 text-2xl font-bold tracking-tight text-gray-900 dark:text-white">Receiver</h5>
    {#if state}
      <ActiveCalls
        calls={receivedCalls}
        {onSpeakOrListen}
        {onHangUp}
        {onInviteAccepted}
        webRtcConnected={isWebRtcConnected}
      />
    {/if}
  </div>
</div>
