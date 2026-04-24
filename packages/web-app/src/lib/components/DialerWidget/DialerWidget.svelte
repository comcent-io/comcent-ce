<svelte:options accessors={true} />

<script lang="ts">
  import '../../../tailwind.css';
  import MinusIcon from '$lib/components/Icons/MinusIcon.svelte';
  import ExpandIcon from '$lib/components/Icons/ExpandIcon.svelte';
  import ClearLeftIcon from '$lib/components/Icons/ClearLeftIcon.svelte';
  import KeyboardIcon from '$lib/components/Icons/KeyboardIcon.svelte';
  import PhoneIcon from '$lib/components/Icons/PhoneIcon.svelte';
  import { slide } from 'svelte/transition';
  import DialPad from './DialPad.svelte';
  import { onDestroy, onMount } from 'svelte';
  import type { Invitation } from 'sip.js';
  import RingNotification from '$lib/components/DialerWidget/RingNotification.svelte';
  import PhoneDisconnectIcon from '$lib/components/Icons/PhoneDisconnectIcon.svelte';
  import { Session, UserAgent } from 'sip.js';
  import { SessionManager } from 'sip.js/lib/platform/web';
  import type { SessionManagerDelegate } from 'sip.js/lib/platform/web';
  import CurrentCall from '$lib/components/DialerWidget/CurrentCall.svelte';
  import type { DialerWidgetDelegate } from './types/DialerWidgetDelegate';
  import { isValidPhoneNumber } from 'libphonenumber-js';
  import type { MemberSearchResult } from '$lib/server/types/MemberSearchResult';
  import Spinner from '../Icons/Spinner.svelte';
  import toast from 'svelte-french-toast';
  import { Socket } from 'phoenix';

  export let subdomain = '';
  export let username: string;
  export let password: string;
  export let displayName: string;

  export let origin: string | null = null;
  export let appBaseUrl: string | null = null;
  export let sipWsUrl: string | null = null;
  export let sipDomain: string | null = null;

  export let authToken: string | undefined;

  export let delegate: DialerWidgetDelegate = {};

  export let numbers: {
    id: string;
    name: string;
    number: string;
    sipTrunk: {
      id: string;
      name: string;
    };
  }[] = [];

  let selectedOutboundInfo = '';
  let selectedOutboundNumber = '';
  let userId = '';
  // This variable is required as widget may be hosted in different website.
  // Widget embedders MUST provide appBaseUrl, sipWsUrl, and sipDomain props;
  // example.com fallbacks exist only to prevent crashes during development.
  let resolvedAppBaseUrl = appBaseUrl || origin || 'https://app.example.com';
  let domainName = `${subdomain}.${sipDomain || 'example.com'}`;
  const ringSoundUrl = `${resolvedAppBaseUrl}/sounds/phone_ringing.mp3`;
  let wsUrl = sipWsUrl || 'wss://sip-ws.example.com/';
  let invitations: Invitation[] = [];
  export let currentCall: Session | null = null;
  let heldForAttendedTransfer: Session | null = null;
  let callOnHoldStack: Session[] = [];
  let startTimeForSession: Record<string, Date> = {};

  let remoteAudio: HTMLAudioElement;
  let ringSound: HTMLAudioElement;

  let searchResults: MemberSearchResult[] = [];
  let errorMessage = '';
  let isDialing = false;

  let socket: Socket | undefined;
  let presenceChannel: any;

  async function searchUser(searchText: string) {
    try {
      const encodedSearchText = encodeURIComponent(searchText);
      const response = await fetch(`/api/v2/${subdomain}/members?search=${encodedSearchText}`);
      if (!response.ok) {
        console.error('Network response was not ok');
        return [];
      }
      return await response.json();
    } catch (error) {
      console.error('Error fetching data:', error);
      return [];
    }
  }

  async function newCallNotification(invitation: Invitation) {
    let notification: Notification | undefined;
    const title = 'Incoming Call';
    const fromString = invitation.remoteIdentity.displayName || invitation.remoteIdentity.uri.aor;
    const options = {
      body: `From ${fromString}`,
    };
    if (!('Notification' in window)) {
      // Check if the browser supports notifications
      console.log('This browser does not support desktop notification');
    } else if (Notification.permission === 'granted') {
      notification = new Notification(title, options);
    } else if (Notification.permission !== 'denied') {
      // We need to ask the user for permission
      const permission = await Notification.requestPermission();
      // If the user accepts, let's create a notification
      if (permission === 'granted') {
        notification = new Notification(title, options);
      }
    }

    if (notification) {
      notification.addEventListener('click', function () {
        window.focus();
        notification?.close();
      });
    }
  }

  async function fetchSuggestions(event: Event) {
    const target = event.target as HTMLInputElement;
    let userInput = target.value;
    if (!isValidPhoneNumber(userInput)) {
      if (userInput.length < 3) {
        searchResults = [];
      } else {
        searchResults = await searchUser(userInput);
      }
    }
  }
  function selectUser(member: MemberSearchResult) {
    toAddress = member.username;
    searchResults = [];
  }

  function playRing() {
    ringSound.currentTime = 0;
    ringSound.play();
  }

  function stopRing() {
    ringSound?.pause();
  }

  let onHangupCallbacks: any[] = [];
  let onConnectedCallbacks: any[] = [];

  export function setOnHangupCallback(callback: any) {
    onHangupCallbacks.push(callback);
  }

  export function setOnConnectedCallback(callback: any) {
    onConnectedCallbacks.push(callback);
  }

  export function getUaStatus() {
    return uaStatus;
  }

  const sessionManagerDelegate: SessionManagerDelegate = {
    onCallReceived(invitation) {
      playRing();
      newCallNotification(invitation as Invitation);
      invitations.push(invitation as Invitation);
      invitations = invitations;
      const invite = invitation as Invitation;
      delegate?.onCallReceived?.({
        from: {
          name: invite.request.from.displayName,
          address: invite.request.from.uri.user ?? '',
        },
        to: {
          name: displayName,
          address: `sip:${username}@${domainName}`,
        },
        paths: invite.request.headers['X-Inbound-Info']?.[0]?.raw?.split('|').map((p) => {
          const [type, address, name] = p.split(':');
          return { type, address, name: name ?? '' };
        }),
      });
    },
    onServerConnect() {
      uaStatus = 'Connected';
    },
    onServerDisconnect() {
      uaStatus = 'Disconnected';
    },
    onRegistered() {
      uaStatus = 'Registered';
    },
    async onCallAnswered(session) {
      onConnectedCallbacks.forEach((callback) => {
        callback();
      });
      startTimeForSession[session.id] = new Date();
      currentCall = session;
      invitations = invitations.filter((i) => i !== session);
      if (invitations.length === 0) {
        stopRing();
      }
    },
    onCallHangup(session) {
      onHangupCallbacks.forEach((callback) => {
        callback();
      });
      delete startTimeForSession[session.id];
      if (currentCall === session) {
        currentCall = null;
      } else {
        // Remove either from invitations of from on hold stack
        invitations = invitations.filter((i) => i !== session);
        if (invitations.length === 0) {
          stopRing();
        }
        callOnHoldStack = callOnHoldStack.filter((i) => i !== session);
      }

      if (heldForAttendedTransfer === session) {
        heldForAttendedTransfer = null;
        // TODO show popup toaster saying that other party hung up
      }
    },
  };

  let sessionManager: SessionManager;
  onMount(async () => {
    getCurrentPresence();
    // Initialize WebSocket connection for presence updates
    if (authToken) {
      socket = new Socket(`/ws`, {
        params: {
          subdomain,
          token: authToken,
        },
      });

      socket.connect();

      presenceChannel = socket.channel(`presence:${subdomain}`, {});

      presenceChannel
        .join()
        .receive('ok', (resp: any) => {
          console.log(`Joined presence channel for ${subdomain}`, resp);
        })
        .receive('error', (resp: any) => {
          console.error(`Unable to join presence channel for ${subdomain}`, resp);
        });

      presenceChannel.on('presence_update', (payload: any) => {
        if (payload.userId === userId) {
          status = payload.presence;
          console.log(`Updated presence to ${status} for ${username}`);
        }
      });

      socket.onOpen(() => {
        console.info('WebSocket connected');
      });

      socket.onClose(() => {
        console.info('WebSocket disconnected');
      });
    }

    // Initialize SIP session manager
    sessionManager = new SessionManager(wsUrl, {
      delegate: sessionManagerDelegate,
      userAgentOptions: {
        authorizationUsername: username,
        authorizationPassword: password,
        displayName: displayName,
        uri: UserAgent.makeURI(`sip:${username}@${domainName}`),
        sessionDescriptionHandlerFactoryOptions: {
          iceGatheringTimeout: 1000,
        },
      },
      media: {
        remote: {
          audio: remoteAudio,
        },
      },
    });
    await sessionManager.connect();
    await sessionManager.register();
    checkPaymentError();
  });

  function checkPaymentError() {
    if (!sessionManager.userAgent.transport.onMessage) {
      sessionManager.userAgent.transport.onMessage = onMessageReceived;
    } else {
      sessionManager.userAgent.transport.ws.addEventListener('message', (ev: MessageEvent) =>
        onWebSocketMessageReceived(ev, sessionManager.userAgent.transport.ws),
      );
    }
  }

  function formatIncomingResponse(message: string) {
    const status = message.split('\n')[0];
    const statusCode = status.split(' ')[1];
    const statusText = status.split(' ').slice(2).join(' ');
    if (statusCode === '402') {
      errorMessage = statusText;
    }
  }

  function onMessageReceived(message: string) {
    formatIncomingResponse(message);
  }

  function onWebSocketMessageReceived(ev: MessageEvent, ws: WebSocket): void {
    formatIncomingResponse(ev.data);
  }

  onDestroy(async () => {
    await sessionManager?.unregister();
    await sessionManager?.disconnect();
    presenceChannel?.leave();
    socket?.disconnect();
  });

  function onAnswer(event: CustomEvent<Invitation>) {
    const invitation = event.detail;
    invitation?.accept();
  }

  function onDecline(event: CustomEvent<Invitation>) {
    const invitation = event.detail;
    invitation?.reject();
  }

  export async function dial(fromNumber: number, toNumber: number) {
    selectedOutboundNumber = String(fromNumber);
    toAddress = String(toNumber);
    await onDial();
  }

  async function onDial() {
    isDialing = true;
    const extraHeaders = [];
    if (selectedOutboundNumber) {
      extraHeaders.push(`X-outbound-number: ${selectedOutboundNumber}`);
    }
    currentCall = await sessionManager.call(`sip:${toAddress}@${domainName}`, {
      extraHeaders,
      earlyMedia: true,
    });
    isDialing = false;
  }

  async function onBlindTransfer(e: CustomEvent<{ transferAddress: string }>) {
    const transferAddress = e.detail.transferAddress;
    if (!currentCall || !transferAddress) {
      return;
    }
    console.log(`Blind transfer call to ${transferAddress}`);
    await sessionManager.transfer(currentCall, `sip:${transferAddress}@${domainName}`, {
      requestDelegate: {
        onAccept() {
          console.log('Blind transfer accepted');
          currentCall = null;
        },
      },
    });
  }

  async function onAttendedTransfer(e: CustomEvent<{ transferAddress: string }>) {
    const transferAddress = e.detail.transferAddress;
    if (!currentCall || !transferAddress) {
      return;
    }
    console.log(`Attended transfer call to ${transferAddress}`);
    await sessionManager.hold(currentCall);
    heldForAttendedTransfer = currentCall;
    currentCall = await sessionManager.call(`sip:${transferAddress}@${domainName}`);
  }

  async function onAttendedTransferComplete() {
    if (!heldForAttendedTransfer || !currentCall) return;
    await sessionManager.transfer(heldForAttendedTransfer, currentCall, {
      requestDelegate: {
        onAccept() {
          console.log('Attended transfer accepted');
          heldForAttendedTransfer = null;
          currentCall = null;
        },
      },
    });
  }

  async function onAttendedTransferReject() {
    if (!currentCall) return;
    await sessionManager.hangup(currentCall);
    if (heldForAttendedTransfer) {
      currentCall = heldForAttendedTransfer;
      heldForAttendedTransfer = null;
      await sessionManager.unhold(currentCall);
      (sessionManager as any).setupRemoteMedia(currentCall);
    }
  }

  function onHangup() {
    if (!currentCall) {
      return;
    }
    sessionManager.hangup(currentCall);
  }

  function onHold() {
    if (!currentCall) {
      return;
    }
    sessionManager.hold(currentCall);
  }

  function onUnhold() {
    if (!currentCall) {
      return;
    }
    sessionManager.unhold(currentCall);
  }

  function onMute() {
    if (!currentCall) {
      return;
    }
    sessionManager.mute(currentCall);
  }

  function onUnmute() {
    if (!currentCall) {
      return;
    }
    sessionManager.unmute(currentCall);
  }

  let expanded = false;
  let showDialPad = false;
  let toAddress = '';
  let uaStatus = 'Connecting...';

  let availableStatus = ['Logged Out', 'Available', 'On Break', 'On Call', 'Wrap Up', 'Busy'];
  let status = 'Available';

  $: showExpanded = expanded || !!currentCall;

  function toggleExpanded() {
    expanded = !expanded;
  }

  function onOutboundInfoChanged(e: Event) {
    const target = e.target as HTMLSelectElement;
    const [address, , name] = target.value.split('/');
    delegate?.onOutboundNumberChanged?.({
      address,
      name,
    });
  }

  async function onStatusChange(e: Event) {
    const target = e.target as HTMLSelectElement;
    const status = target.value;
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
    };
    if (authToken) {
      headers['Authorization'] = `Bearer ${authToken}`;
    }
    try {
      const presenceResponse = await fetch(`${resolvedAppBaseUrl}/api/v2/${subdomain}/members/presence`, {
        method: 'POST',
        headers,
        body: JSON.stringify({ presence: status }),
      });
      if (!presenceResponse.ok)
        throw new Error((await presenceResponse.json()).error ?? presenceResponse.statusText);
    } catch (error: any) {
      toast.error('Error updating presence:', error.message);
    }

    await getCurrentPresence();
  }

  async function getCurrentPresence() {
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
    };
    if (authToken) {
      headers['Authorization'] = `Bearer ${authToken}`;
    }
    try {
      const presenceGetResponse = await fetch(
        `${resolvedAppBaseUrl}/api/v2/${subdomain}/members/presence`,
        { headers },
      );
      if (!presenceGetResponse.ok)
        throw new Error((await presenceGetResponse.json()).error ?? presenceGetResponse.statusText);
      const presenceData = await presenceGetResponse.json();
      status = presenceData.presence;
      userId = presenceData.id;
      return;
    } catch (error: any) {
      toast.error('Error getting presence:', error.message);
    }
  }

  let showNumbers = false;
  function showOrHideNumbers() {
    showNumbers = !showNumbers;
  }

  let filteredNumbers: any[] = numbers;
  function fetchNumbers(event: Event) {
    const target = event.target as HTMLInputElement;
    const userInput = target.value.toLowerCase();
    if (userInput.length === 0) {
      filteredNumbers = numbers;
    } else {
      filteredNumbers = numbers.filter((number) => number.name.toLowerCase().includes(userInput));
    }

    if (filteredNumbers.length === 0) {
      filteredNumbers = numbers;
    }
    showNumbers = true;
  }

  function selectNumber(selectedNumber: any) {
    selectedOutboundInfo = `${selectedNumber.name} ${selectedNumber.number}`;
    selectedOutboundNumber = selectedNumber.number;
    showNumbers = false;
  }
</script>

<div class="w-1/4 fixed bottom-1 right-1 block max-w-md">
  {#each invitations as invitation}
    <RingNotification bind:invitation on:answer={onAnswer} on:decline={onDecline} />
  {/each}
  {#if currentCall}
    <CurrentCall
      startTime={startTimeForSession[currentCall.id]}
      {sessionManager}
      session={currentCall}
      {heldForAttendedTransfer}
      on:hangup={onHangup}
      on:mute={onMute}
      on:unmute={onUnmute}
      on:hold={onHold}
      on:unhold={onUnhold}
      on:blindTransfer={onBlindTransfer}
      on:attendedTransfer={onAttendedTransfer}
      on:confirmAttendedTransfer={onAttendedTransferComplete}
      on:cancelAttendedTransfer={onAttendedTransferReject}
    />
  {/if}

  <div
    class="bg-white border border-gray-200 rounded-lg shadow dark:bg-gray-800 dark:border-gray-700"
  >
    <div class="flex justify-between bg-gray-950 py-3 px-5">
      <div class="text-gray-500 dark:text-gray-400">
        {#if uaStatus !== 'Registered'}
          {uaStatus}
        {:else}
          <select
            id="countries"
            bind:value={status}
            on:change={onStatusChange}
            class="bg-gray-50 border border-gray-300 text-gray-900 text-sm rounded-sm focus:ring-blue-500 focus:border-blue-500 p-1 dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500"
          >
            {#each availableStatus as s}
              <option value={s}>{s}</option>
            {/each}
          </select>
        {/if}
      </div>
      {#if expanded}
        <button
          on:click={toggleExpanded}
          class="w-6 p-0 text-blue-700 hover:bg-gray-800 hover:text-white focus:ring-4 focus:outline-none focus:ring-blue-300 font-medium text-sm text-center inline-flex items-center dark:border-blue-500 dark:text-blue-500 dark:hover:text-white dark:focus:ring-blue-800 dark:hover:bg-gray-500"
        >
          <MinusIcon />
        </button>
      {:else}
        <button
          on:click={toggleExpanded}
          class="w-6 p-0 text-blue-700 hover:bg-gray-800 hover:text-white focus:ring-4 focus:outline-none focus:ring-blue-300 font-medium text-sm text-center inline-flex items-center dark:border-blue-500 dark:text-blue-500 dark:hover:text-white dark:focus:ring-blue-800 dark:hover:bg-gray-500"
        >
          <ExpandIcon />
        </button>
      {/if}
    </div>
    {#if showExpanded}
      <div class="p-3 relative">
        {#if errorMessage}
          <p class="text-red-500 text-sm mb-2">{errorMessage}</p>
        {/if}
        <div>
          <label
            for="countries"
            class="block mb-2 text-sm font-medium text-gray-900 dark:text-white"
          >
            Outbound Number
          </label>
          <div class="relative">
            <input
              autocomplete="off"
              type="text"
              id="name"
              name="name"
              class="cursor-default bg-gray-50 border border-gray-300 text-gray-900 text-sm rounded-lg focus:ring-blue-500 focus:border-blue-500 block w-full p-2.5 pr-10 dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500"
              placeholder="Search.."
              required
              bind:value={selectedOutboundInfo}
              on:input={fetchNumbers}
              on:click={showOrHideNumbers}
            />
            <svg
              class="absolute inset-y-0 right-0 mr-3 mt-3 w-4 h-4 text-gray-800 dark:text-gray-400"
              aria-hidden="true"
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M19 9l-7 7-7-7"
              />
            </svg>
          </div>

          {#if showNumbers}
            <div
              class="absolute bottom-[7.3rem] w-[22rem] z-10 mb-2 bg-white divide-y divide-gray-100 rounded-lg shadow dark:bg-gray-700 max-h-64 overflow-y-auto"
            >
              <ul
                class="py-2 text-sm text-gray-700 dark:text-gray-200"
                aria-labelledby="dropdownDefaultButton"
              >
                {#each filteredNumbers as number}
                  <li>
                    <button
                      on:click|preventDefault={() => selectNumber(number)}
                      class="w-full block px-2 py-2 hover:bg-gray-100 dark:hover:bg-gray-600 dark:hover:text-white text-left"
                    >
                      <div class="flex-1 min-w-0">
                        <p class="text-sm font-medium text-gray-900 truncate dark:text-white">
                          {number.name}
                          {number.number}
                        </p>
                      </div>
                    </button>
                  </li>
                {/each}
              </ul>
            </div>
          {/if}
        </div>
        <div class="flex justify-between items-center">
          <div class="relative">
            <label
              for="countries"
              class="block mb-2 text-sm font-medium text-gray-900 dark:text-white"
            >
              Recipient
            </label>
            <input
              autocomplete="off"
              type="text"
              id="destination"
              name=""
              class="bg-gray-50 border border-gray-300 text-gray-900 text-sm rounded-lg focus:ring-blue-500 focus:border-blue-500 block w-full p-2.5 dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500"
              placeholder="Destination number"
              required
              bind:value={toAddress}
              on:input={fetchSuggestions}
            />
            {#if searchResults.length > 0}
              <div
                class="absolute bottom-full mb-2 z-10 bg-white divide-y divide-gray-100 rounded-lg shadow w-auto min-w-full dark:bg-gray-700"
              >
                <ul
                  class="py-2 text-sm text-gray-700 dark:text-gray-200"
                  aria-labelledby="dropdownDefaultButton"
                >
                  {#each searchResults as member}
                    <li>
                      <button
                        on:click|preventDefault={() => selectUser(member)}
                        class="w-full block px-2 py-2 hover:bg-gray-100 dark:hover:bg-gray-600 dark:hover:text-white text-left"
                      >
                        <div class="flex-1 min-w-0">
                          <p class="text-sm font-medium text-gray-900 truncate dark:text-white">
                            {member.username} [{member.presence}]
                          </p>
                        </div>
                      </button>
                    </li>
                  {/each}
                </ul>
              </div>
            {/if}
          </div>
          <button
            type="button"
            on:click={() => (toAddress = '')}
            class="rounded-full mr-1 mt-6 text-white bg-blue-700 hover:bg-blue-800 focus:ring-4 focus:outline-none focus:ring-blue-300 font-medium text-sm p-2.5 inline-flex justify-center items-center dark:bg-blue-600 dark:hover:bg-blue-700 dark:focus:ring-blue-800"
          >
            <ClearLeftIcon />
            <span class="sr-only">Clear</span>
          </button>

          {#if currentCall}
            <button
              type="button"
              on:click={onHangup}
              class="rounded-full text-white bg-red-700 hover:bg-red-800 focus:ring-4 focus:outline-none focus:ring-red-300 font-medium text-sm p-2.5 inline-flex justify-center items-center dark:bg-red-600 dark:hover:bg-red-700 dark:focus:ring-red-800 mr-1 mt-6 w-9 h-9"
            >
              <PhoneDisconnectIcon />
              <span class="sr-only">Hangup</span>
            </button>
          {:else}
            <button
              type="button"
              on:click={onDial}
              disabled={isDialing}
              class="rounded-full mr-1 mt-6 text-white bg-blue-700 hover:bg-blue-800 focus:ring-4 focus:outline-none focus:ring-blue-300 font-medium text-sm p-2.5 inline-flex justify-center items-center dark:bg-blue-600 dark:hover:bg-blue-700 dark:focus:ring-blue-800 w-9 h-9"
            >
              {#if isDialing}
                <Spinner className="ml-2" />
              {:else}
                <PhoneIcon />
              {/if}
              <span class="sr-only">Dial</span>
            </button>
          {/if}

          <button
            type="button"
            on:click={() => (showDialPad = !showDialPad)}
            class=" rounded-full mt-6 text-white bg-blue-700 hover:bg-blue-800 focus:ring-4 focus:outline-none focus:ring-blue-300 font-medium text-sm p-2.5 inline-flex justify-center items-center dark:bg-blue-600 dark:hover:bg-blue-700 dark:focus:ring-blue-800"
          >
            <KeyboardIcon />
            <span class="sr-only">Show/Hide Keypad</span>
          </button>
        </div>
        {#if showDialPad}
          <div transition:slide={{ delay: 250, duration: 300 }} class="mt-2">
            <DialPad
              on:dialKeyPress={(e) => {
                if (!toAddress) toAddress = '';
                toAddress += e.detail.number;
              }}
            />
          </div>
        {/if}
      </div>
    {/if}

    <audio id="remoteAudio" bind:this={remoteAudio}>
      <div
        class="p-4 mb-4 text-sm text-red-800 rounded-lg bg-red-50 dark:bg-gray-800 dark:text-red-400"
        role="alert"
      >
        Your browser doesn't support HTML5 audio.
      </div>
    </audio>
    <audio id="ringSound" bind:this={ringSound} loop src={ringSoundUrl} />
  </div>
</div>
