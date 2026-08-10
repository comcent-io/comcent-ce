<svelte:options accessors={true} />

<script lang="ts">
  import '../../../tailwind.css';
  import MinusIcon from '$lib/components/Icons/MinusIcon.svelte';
  import ExpandIcon from '$lib/components/Icons/ExpandIcon.svelte';
  import ClearLeftIcon from '$lib/components/Icons/ClearLeftIcon.svelte';
  import PhoneIcon from '$lib/components/Icons/PhoneIcon.svelte';
  import { slide } from 'svelte/transition';
  import DialPad from './DialPad.svelte';
  import { onDestroy, onMount } from 'svelte';
  import type { Invitation } from 'sip.js';
  import RingNotification from '$lib/components/DialerWidget/RingNotification.svelte';
  import { Session, UserAgent } from 'sip.js';
  import { SessionManager } from 'sip.js/lib/platform/web';
  import type { SessionManagerDelegate } from 'sip.js/lib/platform/web';
  import CurrentCall from '$lib/components/DialerWidget/CurrentCall.svelte';
  import CallTime from '$lib/components/DialerWidget/CallTime.svelte';
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
  let heldCalls: { session: Session; heldSince: Date }[] = [];
  let startTimeForSession: Record<string, Date> = {};

  // Incoming calls the agent has soft-dismissed (not SIP-rejected — just
  // demoted out of the primary overlay into the "Also Waiting" list) until
  // answered, declined, or the caller hangs up.
  let ignoredInvitationIds: Set<string> = new Set();
  $: primaryInvitation = invitations.find((i) => !ignoredInvitationIds.has(i.id)) ?? invitations[0];
  $: waitingInvitations = invitations.filter((i) => i !== primaryInvitation);
  // True when the primary card is itself an ignored call shown only because
  // there's nothing else to promote — lets the UI show it's been silenced
  // instead of looking unchanged and identical to a fresh, un-ignored call.
  $: primaryIsIgnored = primaryInvitation ? ignoredInvitationIds.has(primaryInvitation.id) : false;

  let remoteAudio: HTMLAudioElement;
  let ringSound: HTMLAudioElement;

  let searchResults: MemberSearchResult[] = [];
  let errorMessage = '';
  let isDialing = false;

  let socket: Socket | undefined;
  let presenceChannel: any;

  function sessionLabel(s: Session) {
    return String(s.remoteIdentity.friendlyName ?? s.remoteIdentity.uri);
  }

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
    ringSound.play().catch(() => {});
  }

  function stopRing() {
    if (!ringSound) return;
    ringSound.pause();
    ringSound.currentTime = 0;
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
      ignoredInvitationIds.delete(session.id);
      ignoredInvitationIds = ignoredInvitationIds;

      if (currentCall === session) {
        if (heldCalls.length > 0) {
          // Resume the longest-parked call automatically, same as picking up
          // the next line once the current one clears.
          const [next, ...rest] = heldCalls;
          heldCalls = rest;
          sessionManager.unhold(next.session);
          currentCall = next.session;
        } else {
          currentCall = null;
        }
      } else {
        // Remove either from invitations or from the held-calls park stack.
        invitations = invitations.filter((i) => i !== session);
        if (invitations.length === 0) {
          stopRing();
        }
        heldCalls = heldCalls.filter((h) => h.session !== session);
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

  async function onAnswer(event: CustomEvent<Invitation>) {
    const invitation = event.detail;
    if (!invitation) return;
    ignoredInvitationIds.delete(invitation.id);
    ignoredInvitationIds = ignoredInvitationIds;
    if (currentCall) {
      await sessionManager.hold(currentCall);
      heldCalls = [...heldCalls, { session: currentCall, heldSince: new Date() }];
    }
    // Go through SessionManager rather than the raw Invitation so its
    // internal session bookkeeping/media setup runs (see the manual
    // setupRemoteMedia patch in onAttendedTransferReject below, needed
    // precisely because bypassing SessionManager skips that wiring).
    await sessionManager.answer(invitation);
  }

  function onDecline(event: CustomEvent<Invitation>) {
    const invitation = event.detail;
    if (!invitation) return;
    sessionManager.decline(invitation);
  }

  function onIgnore(event: CustomEvent<Invitation>) {
    const invitation = event.detail;
    if (!invitation) return;
    ignoredInvitationIds.add(invitation.id);
    ignoredInvitationIds = ignoredInvitationIds;
    // Ignore silences the audible alert without touching the SIP session —
    // the call keeps ringing on the network and stays visible (demoted into
    // the waiting list), it just stops making noise.
    stopRing();
  }

  async function resumeHeldCall(target: Session) {
    if (currentCall) {
      await sessionManager.hold(currentCall);
      heldCalls = [...heldCalls, { session: currentCall, heldSince: new Date() }];
    }
    heldCalls = heldCalls.filter((h) => h.session !== target);
    await sessionManager.unhold(target);
    currentCall = target;
  }

  function dropHeldCall(session: Session) {
    sessionManager.hangup(session);
  }

  // Explicit "start a new call" action rather than overloading Hold: parks
  // the current call the same way answering a second incoming call does,
  // then clears currentCall so the idle dial panel reappears to place the
  // new outbound call.
  async function onNewCall() {
    if (!currentCall) return;
    await sessionManager.hold(currentCall);
    heldCalls = [...heldCalls, { session: currentCall, heldSince: new Date() }];
    currentCall = null;
  }

  function onDtmf(event: CustomEvent<{ number: string }>) {
    if (!currentCall) return;
    sessionManager.sendDTMF(currentCall, event.detail.number);
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
    await sessionManager.transfer(currentCall, `sip:${transferAddress}@${domainName}`, {
      requestDelegate: {
        onAccept() {
          toast.success(`Call transferred to ${transferAddress}`);
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
    await sessionManager.hold(currentCall);
    heldForAttendedTransfer = currentCall;
    currentCall = await sessionManager.call(`sip:${transferAddress}@${domainName}`);
  }

  async function onAttendedTransferComplete() {
    if (!heldForAttendedTransfer || !currentCall) return;
    const transferredTo = sessionLabel(currentCall);
    await sessionManager.transfer(heldForAttendedTransfer, currentCall, {
      requestDelegate: {
        onAccept() {
          toast.success(`Call transferred to ${transferredTo}`);
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
  let statusMenuOpen = false;
  const statusDotColors: Record<string, string> = {
    'Logged Out': 'bg-gray-400 dark:bg-gray-500',
    Available: 'bg-green-500',
    'On Break': 'bg-amber-500',
    'On Call': 'bg-blue-500',
    'Wrap Up': 'bg-purple-500',
    Busy: 'bg-red-500',
  };

  $: showExpanded = expanded || !!currentCall || heldCalls.length > 0;

  function toggleExpanded() {
    expanded = !expanded;
    statusMenuOpen = false;
  }

  // Drag/dock positioning. At rest the widget is pinned by whichever corner
  // it's docked against (bottom-right by default) using `bottom`/`right` (or
  // `top`/`left`) CSS rather than always `top`/`left` — that way content
  // that renders *above* the header (RingNotification, CurrentCall) grows
  // the box away from a fixed bottom edge, exactly like the browser handles
  // native `bottom`-anchored content, instead of pushing the header down
  // and then having it clamped back up once the content shrinks again.
  let widgetEl: HTMLDivElement;
  let anchorX: 'left' | 'right' = 'right';
  let anchorY: 'top' | 'bottom' = 'bottom';
  let offsetX: number | null = null; // px from the anchorX edge
  let offsetY: number | null = null; // px from the anchorY edge
  let dragging = false;
  let dragLeft = 0; // live top-left px while actively dragging
  let dragTop = 0;
  let dragOffsetX = 0;
  let dragOffsetY = 0;
  const EDGE_MARGIN = 8;
  const DOCK_THRESHOLD = 32;

  function initialPosition() {
    anchorX = 'right';
    anchorY = 'bottom';
    offsetX = EDGE_MARGIN;
    offsetY = EDGE_MARGIN;
  }

  // Keeps the widget fully on-screen whenever its size changes (expanding,
  // opening the dial pad, showing search/number dropdowns, an incoming call
  // notification) instead of only ever growing in a fixed direction and
  // risking clipping off the viewport. A no-op for the common case of a
  // widget docked flush against an edge — offset is already at EDGE_MARGIN,
  // so the browser grows the box away from that edge on its own.
  function clampPosition() {
    if (!widgetEl || offsetX === null || offsetY === null || dragging) return;
    const rect = widgetEl.getBoundingClientRect();
    const maxX = Math.max(EDGE_MARGIN, window.innerWidth - rect.width - EDGE_MARGIN);
    const maxY = Math.max(EDGE_MARGIN, window.innerHeight - rect.height - EDGE_MARGIN);
    offsetX = Math.min(Math.max(offsetX, EDGE_MARGIN), maxX);
    offsetY = Math.min(Math.max(offsetY, EDGE_MARGIN), maxY);
  }

  function onDragHandlePointerDown(e: PointerEvent) {
    const target = e.target as HTMLElement;
    if (target.closest('select, button')) return;
    if (!widgetEl) return;
    const rect = widgetEl.getBoundingClientRect();
    dragging = true;
    dragLeft = rect.left;
    dragTop = rect.top;
    dragOffsetX = e.clientX - rect.left;
    dragOffsetY = e.clientY - rect.top;
    window.addEventListener('pointermove', onDragPointerMove);
    window.addEventListener('pointerup', onDragPointerUp);
  }

  function onDragPointerMove(e: PointerEvent) {
    if (!dragging) return;
    dragLeft = e.clientX - dragOffsetX;
    dragTop = e.clientY - dragOffsetY;
  }

  function onDragPointerUp() {
    if (!dragging) return;
    dragging = false;
    window.removeEventListener('pointermove', onDragPointerMove);
    window.removeEventListener('pointerup', onDragPointerUp);
    dockFromDragPosition();
  }

  // Converts the free-floating drag-end position into a resting corner
  // anchor: docks flush against whichever edge(s) it was dropped near,
  // otherwise keeps it anchored to the nearer edge at its dropped offset.
  function dockFromDragPosition() {
    if (!widgetEl) return;
    const rect = widgetEl.getBoundingClientRect();
    const maxLeft = Math.max(EDGE_MARGIN, window.innerWidth - rect.width - EDGE_MARGIN);
    const maxTop = Math.max(EDGE_MARGIN, window.innerHeight - rect.height - EDGE_MARGIN);
    const left = Math.min(Math.max(dragLeft, EDGE_MARGIN), maxLeft);
    const top = Math.min(Math.max(dragTop, EDGE_MARGIN), maxTop);

    if (left - EDGE_MARGIN <= DOCK_THRESHOLD) {
      anchorX = 'left';
      offsetX = EDGE_MARGIN;
    } else if (maxLeft - left <= DOCK_THRESHOLD) {
      anchorX = 'right';
      offsetX = EDGE_MARGIN;
    } else if (left + rect.width / 2 < window.innerWidth / 2) {
      anchorX = 'left';
      offsetX = left;
    } else {
      anchorX = 'right';
      offsetX = window.innerWidth - (left + rect.width);
    }

    if (top - EDGE_MARGIN <= DOCK_THRESHOLD) {
      anchorY = 'top';
      offsetY = EDGE_MARGIN;
    } else if (maxTop - top <= DOCK_THRESHOLD) {
      anchorY = 'bottom';
      offsetY = EDGE_MARGIN;
    } else if (top + rect.height / 2 < window.innerHeight / 2) {
      anchorY = 'top';
      offsetY = top;
    } else {
      anchorY = 'bottom';
      offsetY = window.innerHeight - (top + rect.height);
    }
  }

  let resizeObserver: ResizeObserver | undefined;
  function bindWidgetEl(node: HTMLDivElement) {
    widgetEl = node;
    initialPosition();
    resizeObserver = new ResizeObserver(() => clampPosition());
    resizeObserver.observe(node);
    window.addEventListener('resize', clampPosition);
    return {
      destroy() {
        resizeObserver?.disconnect();
        window.removeEventListener('resize', clampPosition);
        window.removeEventListener('pointermove', onDragPointerMove);
        window.removeEventListener('pointerup', onDragPointerUp);
      },
    };
  }

  async function selectStatus(newStatus: string) {
    statusMenuOpen = false;
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
    };
    if (authToken) {
      headers['Authorization'] = `Bearer ${authToken}`;
    }
    try {
      const presenceResponse = await fetch(
        `${resolvedAppBaseUrl}/api/v2/${subdomain}/members/presence`,
        {
          method: 'POST',
          headers,
          body: JSON.stringify({ presence: newStatus }),
        },
      );
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

<div
  use:bindWidgetEl
  class="w-1/4 fixed block max-w-md z-[60] dialer-widget"
  class:dialer-widget--dragging={dragging}
  class:bottom-1={offsetX === null}
  class:right-1={offsetX === null}
  style={dragging
    ? `left: ${dragLeft}px; top: ${dragTop}px;`
    : offsetX !== null && offsetY !== null
      ? `${anchorX}: ${offsetX}px; ${anchorY}: ${offsetY}px;`
      : ''}
>
  {#if primaryInvitation}
    <RingNotification
      primary={primaryInvitation}
      waiting={waitingInvitations}
      isIgnored={primaryIsIgnored}
      currentCallerName={currentCall ? sessionLabel(currentCall) : undefined}
      on:answer={onAnswer}
      on:decline={onDecline}
      on:ignore={onIgnore}
    />
  {/if}
  <div
    class="rounded-xl border border-gray-200 bg-white shadow-xl dark:border-gray-700 dark:bg-gray-900"
  >
    <div
      class="flex items-center justify-between rounded-t-xl bg-gray-900 py-2.5 px-4 cursor-move touch-none select-none dark:bg-gray-950"
      on:pointerdown={onDragHandlePointerDown}
    >
      <div class="relative">
        {#if uaStatus !== 'Registered'}
          <span class="text-sm text-gray-400">{uaStatus}</span>
        {:else}
          <button
            type="button"
            on:click={() => (statusMenuOpen = !statusMenuOpen)}
            class="flex items-center gap-2 rounded-lg border border-gray-700 bg-gray-800 px-2.5 py-1.5 text-sm font-medium text-gray-100 hover:bg-gray-700"
          >
            <span class="h-2 w-2 rounded-full {statusDotColors[status] ?? 'bg-gray-400'}" />
            {status}
            <svg
              class="h-3 w-3 text-gray-400"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="2"
              stroke-linecap="round"
              stroke-linejoin="round"
            >
              <path d="M6 9l6 6 6-6" />
            </svg>
          </button>
          {#if statusMenuOpen}
            <div
              class="absolute left-0 top-full z-10 mt-1 w-44 rounded-lg border border-gray-200 bg-white py-1 shadow-lg dark:border-gray-700 dark:bg-gray-800"
            >
              {#each availableStatus as s}
                <button
                  type="button"
                  on:click={() => selectStatus(s)}
                  class="flex w-full items-center gap-2 px-3 py-2 text-left text-sm text-gray-700 hover:bg-gray-100 dark:text-gray-200 dark:hover:bg-gray-700"
                >
                  <span class="h-2 w-2 rounded-full {statusDotColors[s] ?? 'bg-gray-400'}" />
                  {s}
                </button>
              {/each}
            </div>
          {/if}
        {/if}
      </div>
      <button
        on:click={toggleExpanded}
        class="rounded-md p-1 text-gray-400 hover:bg-gray-800 hover:text-white"
      >
        {#if expanded}
          <MinusIcon />
        {:else}
          <ExpandIcon />
        {/if}
        <span class="sr-only">{expanded ? 'Minimize' : 'Expand'}</span>
      </button>
    </div>
    {#if showExpanded}
      <div class="p-3 relative" transition:slide={{ duration: 200 }}>
        {#if errorMessage}
          <p class="mb-2 text-sm text-red-500">{errorMessage}</p>
        {/if}

        {#if heldCalls.length > 0}
          <div class="mb-3">
            <div
              class="mb-2 text-xs font-bold uppercase tracking-wide text-gray-500 dark:text-gray-400"
            >
              On Hold ({heldCalls.length})
            </div>
            <div class="flex flex-col gap-1.5">
              {#each heldCalls as h (h.session.id)}
                <div
                  class="flex items-center gap-2 rounded-lg border border-amber-200 bg-amber-50 px-2.5 py-1.5 dark:border-amber-900 dark:bg-amber-950"
                >
                  <div class="min-w-0 flex-1">
                    <div class="truncate text-sm font-medium text-gray-800 dark:text-gray-100">
                      {h.session.remoteIdentity.friendlyName ?? h.session.remoteIdentity.uri}
                    </div>
                    <div class="flex items-center gap-1 text-xs text-amber-700 dark:text-amber-300">
                      <span>On hold</span>
                      <span>·</span>
                      <CallTime startTime={h.heldSince} class="text-xs" />
                    </div>
                  </div>
                  <button
                    type="button"
                    on:click={() => resumeHeldCall(h.session)}
                    class="whitespace-nowrap rounded-md bg-blue-600 px-2.5 py-1.5 text-xs font-semibold text-white transition-colors hover:bg-blue-700"
                  >
                    Resume
                  </button>
                  <button
                    type="button"
                    on:click={() => dropHeldCall(h.session)}
                    class="whitespace-nowrap rounded-md border border-gray-300 px-2 py-1.5 text-xs text-gray-600 transition-colors hover:bg-gray-100 dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-700"
                  >
                    End
                  </button>
                </div>
              {/each}
            </div>
          </div>
        {/if}

        {#if currentCall}
          <CurrentCall
            startTime={startTimeForSession[currentCall.id]}
            {sessionManager}
            session={currentCall}
            {heldForAttendedTransfer}
            search={searchUser}
            on:hangup={onHangup}
            on:mute={onMute}
            on:unmute={onUnmute}
            on:hold={onHold}
            on:unhold={onUnhold}
            on:blindTransfer={onBlindTransfer}
            on:attendedTransfer={onAttendedTransfer}
            on:confirmAttendedTransfer={onAttendedTransferComplete}
            on:cancelAttendedTransfer={onAttendedTransferReject}
            on:newCall={onNewCall}
            on:dtmfNumberPress={onDtmf}
          />
        {:else}
          <div>
            <label
              for="outboundNumber"
              class="mb-1.5 block text-xs font-bold uppercase tracking-wide text-gray-500 dark:text-gray-400"
            >
              Outbound Number
            </label>
            <div class="relative">
              <input
                autocomplete="off"
                type="text"
                id="outboundNumber"
                name="outboundNumber"
                class="w-full cursor-default rounded-lg border border-gray-300 bg-gray-50 p-2.5 pr-9 text-sm text-gray-900 focus:border-blue-500 focus:ring-blue-500 dark:border-gray-600 dark:bg-gray-800 dark:text-white dark:placeholder-gray-400"
                placeholder="Search.."
                required
                bind:value={selectedOutboundInfo}
                on:input={fetchNumbers}
                on:click={showOrHideNumbers}
              />
              <svg
                class="absolute inset-y-0 right-0 mr-3 mt-3 h-4 w-4 text-gray-500 dark:text-gray-400"
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
                class="absolute bottom-[7.3rem] z-10 mb-2 w-[22rem] divide-y divide-gray-100 rounded-lg border border-gray-200 bg-white shadow-lg dark:divide-gray-700 dark:border-gray-700 dark:bg-gray-800 max-h-64 overflow-y-auto"
              >
                <ul class="py-2 text-sm text-gray-700 dark:text-gray-200">
                  {#each filteredNumbers as number}
                    <li>
                      <button
                        on:click|preventDefault={() => selectNumber(number)}
                        class="block w-full px-3 py-2 text-left hover:bg-gray-100 dark:hover:bg-gray-700"
                      >
                        <p class="truncate text-sm font-medium text-gray-900 dark:text-white">
                          {number.name}
                          {number.number}
                        </p>
                      </button>
                    </li>
                  {/each}
                </ul>
              </div>
            {/if}
          </div>
          <div class="mt-3 flex items-end justify-between gap-2">
            <div class="relative flex-1">
              <label
                for="destination"
                class="mb-1.5 block text-xs font-bold uppercase tracking-wide text-gray-500 dark:text-gray-400"
              >
                Recipient
              </label>
              <input
                autocomplete="off"
                type="text"
                id="destination"
                name="destination"
                class="w-full rounded-lg border border-gray-300 bg-gray-50 p-2.5 font-mono text-sm text-gray-900 focus:border-blue-500 focus:ring-blue-500 dark:border-gray-600 dark:bg-gray-800 dark:text-white dark:placeholder-gray-400"
                placeholder="Destination number"
                required
                bind:value={toAddress}
                on:input={fetchSuggestions}
              />
              {#if searchResults.length > 0}
                <div
                  class="absolute bottom-full z-10 mb-2 w-auto min-w-full divide-y divide-gray-100 rounded-lg border border-gray-200 bg-white shadow-lg dark:divide-gray-700 dark:border-gray-700 dark:bg-gray-800"
                >
                  <ul class="py-2 text-sm text-gray-700 dark:text-gray-200">
                    {#each searchResults as member}
                      <li>
                        <button
                          on:click|preventDefault={() => selectUser(member)}
                          class="block w-full px-3 py-2 text-left hover:bg-gray-100 dark:hover:bg-gray-700"
                        >
                          <p class="truncate text-sm font-medium text-gray-900 dark:text-white">
                            {member.username} [{member.presence}]
                          </p>
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
              class="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-blue-600 text-white hover:bg-blue-700 focus:outline-none focus:ring-4 focus:ring-blue-300 dark:focus:ring-blue-800"
            >
              <ClearLeftIcon />
              <span class="sr-only">Clear</span>
            </button>

            <button
              type="button"
              on:click={onDial}
              disabled={isDialing}
              class="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-blue-600 text-white hover:bg-blue-700 focus:outline-none focus:ring-4 focus:ring-blue-300 disabled:opacity-60 dark:focus:ring-blue-800"
            >
              {#if isDialing}
                <Spinner className="ml-2" />
              {:else}
                <PhoneIcon />
              {/if}
              <span class="sr-only">Dial</span>
            </button>
          </div>

          <button
            type="button"
            on:click={() => (showDialPad = !showDialPad)}
            class="mt-3 flex w-full items-center justify-center gap-1.5 rounded-lg border border-gray-300 py-2 text-xs font-semibold text-gray-600 transition-colors hover:bg-gray-100 dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-800"
          >
            {showDialPad ? 'Hide Dial Pad' : 'Show Dial Pad'}
            <span class="text-[10px]">{showDialPad ? '▲' : '▼'}</span>
          </button>
          {#if showDialPad}
            <div transition:slide={{ delay: 250, duration: 300 }} class="mt-3">
              <DialPad
                on:dialKeyPress={(e) => {
                  if (!toAddress) toAddress = '';
                  toAddress += e.detail.number;
                }}
              />
            </div>
          {/if}
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

<style>
  .dialer-widget {
    transition:
      left 0.2s ease-out,
      right 0.2s ease-out,
      top 0.2s ease-out,
      bottom 0.2s ease-out;
  }

  .dialer-widget--dragging {
    transition: none;
  }
</style>
