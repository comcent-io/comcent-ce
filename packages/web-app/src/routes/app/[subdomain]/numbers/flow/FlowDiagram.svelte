<script lang="ts">
  import StartNode from './nodes/StartNode.svelte';
  import { createEventDispatcher, tick, onDestroy, afterUpdate } from 'svelte';
  import LeaderLine from 'leader-line-new?client';
  import type { SelectedOutlet } from './SelectedOutlet';
  import type { SelectedInlet } from './SelectedInlet';
  import { browser } from '$app/environment';
  import { DialNode } from './nodes/DialNode';
  import { DialGroupNode } from './nodes/DialGroupNode';
  import { InboundFlowGraph } from './nodes/InboundFlowGraph';
  import type { FlowNode } from './nodes/FlowNode';
  import { WeekTimeNode } from './nodes/WeekTimeNode';
  import { PlayNode } from './nodes/PlayNode';
  import { MenuNode } from './nodes/MenuNode';
  import { QueueNode } from './nodes/QueueNode';
  import { VoiceBotNode } from './nodes/VoiceBotNode';
  import { page } from '$app/stores';
  import { deleteS3Uploads } from './utils/DeleteUploads';

  const dispatch = createEventDispatcher();

  export let inboundFlowGraph: any;
  let hideAddDropdown = true;
  let selectedOutlet: SelectedOutlet | null = null;

  let graphJson = new InboundFlowGraph(inboundFlowGraph);

  let nodesComponents = {};

  let deletedNodes: FlowNode[] = [];
  let flowCanvas: HTMLDivElement | null = null;
  let lineRefreshFrame: number | null = null;

  $: dispatch('update', graphJson.json());

  const promises: any[] = [];
  export async function triggerUploads() {
    for (const component of Object.values(nodesComponents)) {
      if (component && component.triggerUpload) {
        const promise = component.triggerUpload();
        promises.push(promise);
      }
    }
    await Promise.all(promises).catch((e) => `Error in uploading ${e}`);
  }

  export async function cleanupUploads() {
    deleteS3Uploads($page.params.subdomain, deletedNodes);
  }

  function newNode(node: FlowNode) {
    graphJson.addNode(node);
    graphJson = graphJson;
  }

  function deleteNode(node: FlowNode) {
    graphJson.removeNode(node.data.id);
    deletedNodes.push(node);
    graphJson = graphJson;
  }

  function onOutletSelected(e: CustomEvent) {
    // Unselect option if already selected
    if (
      selectedOutlet?.nodeId === e.detail.nodeId &&
      selectedOutlet?.outletId === e.detail.outletId
    ) {
      selectedOutlet = null;
      return;
    }
    selectedOutlet = e.detail;
  }

  function onInletIdSelected(e: CustomEvent) {
    const selectedInlet = e.detail as SelectedInlet;
    if (!selectedOutlet) {
      return;
    }
    if (selectedOutlet.nodeId === '_start') {
      graphJson.start = selectedInlet.nodeId;
    } else {
      graphJson.nodes[selectedOutlet.nodeId].linkOutletToInlet(
        selectedOutlet.outletId,
        selectedInlet.nodeId,
      );
    }
    graphJson = graphJson;
    selectedOutlet = null;
    drawLines();
  }

  function onDisconnectOutlet(e: CustomEvent) {
    const { nodeId, outletId } = e.detail;
    if (nodeId === '_start') {
      graphJson.start = '';
    } else if (graphJson.nodes[nodeId]?.data?.outlets) {
      graphJson.nodes[nodeId].data.outlets[outletId] = '';
    }
    graphJson = graphJson;
    if (selectedOutlet?.nodeId === nodeId && selectedOutlet?.outletId === outletId) {
      selectedOutlet = null;
    }
    drawLines();
  }

  function onDisconnectInlet(e: CustomEvent) {
    const { nodeId } = e.detail;
    if (graphJson.start === nodeId) {
      graphJson.start = '';
    }
    for (const node of Object.values(graphJson.nodes)) {
      if (!node.data.outlets) {
        continue;
      }
      for (const [outletId, inletNodeId] of Object.entries(node.data.outlets) as [
        string,
        string | null,
      ][]) {
        if (inletNodeId === nodeId) {
          node.data.outlets[outletId] = '';
        }
      }
    }
    graphJson = graphJson;
    drawLines();
  }

  $: graphJson && drawLines();

  let lines: LeaderLine[] = [];
  function connectorAnchor(element: HTMLElement) {
    return LeaderLine.pointAnchor(element, { x: '50%', y: '50%' });
  }

  function createConnectorLine(startAnchor: HTMLElement, endAnchor: HTMLElement) {
    return new LeaderLine(connectorAnchor(startAnchor), connectorAnchor(endAnchor), {
      path: 'fluid',
      color: '#14b8a6',
      size: 3.5,
      startPlug: 'disc',
      endPlug: 'disc',
      startPlugSize: 1,
      endPlugSize: 1,
      endSocketGravity: [-70, 0],
      startSocketGravity: [70, 0],
    });
  }

  function positionLines() {
    if (!browser) {
      return;
    }
    for (const line of lines) {
      line.position();
    }
  }

  function scheduleLineRefresh() {
    if (!browser) {
      return;
    }
    if (lineRefreshFrame !== null) {
      cancelAnimationFrame(lineRefreshFrame);
    }
    lineRefreshFrame = requestAnimationFrame(() => {
      lineRefreshFrame = null;
      positionLines();
    });
  }

  function isInletConnected(nodeId: string) {
    if (graphJson.start === nodeId) {
      return true;
    }
    for (const node of Object.values(graphJson.nodes)) {
      if (!node.data.outlets) {
        continue;
      }
      for (const inletNodeId of Object.values(node.data.outlets) as (string | null)[]) {
        if (inletNodeId === nodeId) {
          return true;
        }
      }
    }
    return false;
  }

  function isInletConnectable(nodeId: string) {
    if (!selectedOutlet) {
      return false;
    }
    if (selectedOutlet.nodeId === nodeId) {
      return false;
    }
    return !isInletConnected(nodeId);
  }

  async function drawLines() {
    if (!browser) {
      return;
    }
    console.log('drawLines', lines.length);
    await tick();
    for (const line of lines) {
      line.remove();
    }
    lines = [];
    if (graphJson.nodes[graphJson.start]) {
      const startAnchor = document.getElementById('_start-default__outlet');
      const startTarget = document.getElementById(`${graphJson.start}__inlet`);

      if (startAnchor && startTarget) {
        lines.push(createConnectorLine(startAnchor, startTarget));
      }
    }
    for (const node of Object.values(graphJson.nodes)) {
      if (!node.data.outlets) {
        continue;
      }
      for (const [outletId, inletNodeId] of Object.entries(node.data.outlets) as [
        [string, string | null],
      ]) {
        if (inletNodeId) {
          const outletAnchor = document.getElementById(`${node.data.id}-${outletId}__outlet`);
          const inletAnchor = document.getElementById(`${inletNodeId}__inlet`);
          if (outletAnchor && inletAnchor) {
            lines.push(createConnectorLine(outletAnchor, inletAnchor));
          }
        }
      }
    }
  }

  function onDragEnded(e) {
    const { node, tx, ty } = e.detail;
    graphJson.nodes[node.data.id].updatePosition(tx, ty);
    graphJson = graphJson;
    drawLines();
  }

  function onUpdated() {
    graphJson = graphJson;
    console.log('updated', graphJson.json());
  }

  onDestroy(() => {
    if (lineRefreshFrame !== null) {
      cancelAnimationFrame(lineRefreshFrame);
    }
    for (const line of lines) {
      line.remove();
    }
  });

  afterUpdate(() => {
    scheduleLineRefresh();
  });

  let statusArray: any[] = [];
  let isUploading = false;
  function onStatusChanged(e: any) {
    if (e.detail.status === 'uploading') {
      statusArray.push({ nodeId: e.detail.nodeId, status: e.detail.status });
    } else if (e.detail.status === 'completed') {
      const index = statusArray.findIndex((item) => item.nodeId === e.detail.nodeId);
      statusArray[index].status = e.detail.status;
    }
    statusArray = statusArray;
    isUploading = true;
  }

  function selectedOutletLabel() {
    if (!selectedOutlet) {
      return '';
    }

    if (selectedOutlet.nodeId === '_start') {
      return 'Start';
    }

    const node = graphJson.nodes[selectedOutlet.nodeId];
    if (!node) {
      return 'selected node';
    }

    if (selectedOutlet.outletId === 'default') {
      return node.data.type;
    }

    return `${node.data.type} • ${selectedOutlet.outletId}`;
  }

  function connectionHelpText() {
    if (!selectedOutlet) {
      return '';
    }
    return 'Click a blue target connector to complete the route.';
  }
</script>

<svelte:window on:resize={scheduleLineRefresh} />

<div>
  <div
    class="mb-4 rounded-2xl border border-slate-200 bg-slate-50/80 p-4 shadow-sm dark:border-slate-700 dark:bg-slate-900/60"
  >
    <div class="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
      <div class="space-y-2">
        <h3 class="text-2xl font-bold dark:text-white">Flow diagram</h3>
        <p class="max-w-3xl text-sm text-slate-600 dark:text-slate-300">
          Build the inbound call path visually. Drag blocks by the header, then connect a source
          connector on the right to a target connector on the left.
        </p>
        <div class="flex flex-wrap gap-2 text-xs font-medium">
          <span
            class="rounded-full bg-white px-3 py-1 text-slate-700 shadow-sm dark:bg-slate-800 dark:text-slate-200"
          >
            1. Add a step
          </span>
          <span
            class="rounded-full bg-white px-3 py-1 text-slate-700 shadow-sm dark:bg-slate-800 dark:text-slate-200"
          >
            2. Drag it into place
          </span>
          <span
            class="rounded-full bg-white px-3 py-1 text-slate-700 shadow-sm dark:bg-slate-800 dark:text-slate-200"
          >
            3. Connect source to target
          </span>
        </div>
      </div>

      <div class="relative shrink-0">
        <button
          id="add"
          class="inline-flex items-center rounded-lg bg-blue-700 px-5 py-2.5 text-center text-sm font-medium text-white focus:outline-none focus:ring-4 focus:ring-blue-300 hover:bg-blue-800 dark:bg-blue-600 dark:hover:bg-blue-700 dark:focus:ring-blue-800"
          type="button"
          on:click={() => (hideAddDropdown = !hideAddDropdown)}
        >
          Add step
          <svg
            class="ml-2.5 h-2.5 w-2.5"
            aria-hidden="true"
            xmlns="http://www.w3.org/2000/svg"
            fill="none"
            viewBox="0 0 10 6"
          >
            <path
              stroke="currentColor"
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="m1 1 4 4 4-4"
            />
          </svg>
        </button>
        <div
          id="dropdown"
          class="absolute z-10 mt-2 w-48 divide-y divide-gray-100 rounded-lg bg-white shadow dark:bg-gray-700"
          class:hidden={hideAddDropdown}
        >
          <ul
            class="py-2 text-sm text-gray-700 dark:text-gray-200"
            aria-labelledby="dropdownDefaultButton"
          >
            <li>
              <button
                type="button"
                on:click={() => {
                  newNode(new DialNode());
                  hideAddDropdown = true;
                }}
                class="block w-full px-4 py-2 text-left hover:bg-gray-100 dark:hover:bg-gray-600 dark:hover:text-white"
              >
                Dial
              </button>
            </li>

            <li>
              <button
                type="button"
                on:click={() => {
                  newNode(new DialGroupNode());
                  hideAddDropdown = true;
                }}
                class="block w-full px-4 py-2 text-left hover:bg-gray-100 dark:hover:bg-gray-600 dark:hover:text-white"
              >
                DialGroup
              </button>
            </li>

            <li>
              <button
                type="button"
                on:click={() => {
                  newNode(new QueueNode());
                  hideAddDropdown = true;
                }}
                class="block w-full px-4 py-2 text-left hover:bg-gray-100 dark:hover:bg-gray-600 dark:hover:text-white"
              >
                Queue
              </button>
            </li>

            <li>
              <button
                type="button"
                on:click={() => {
                  newNode(new VoiceBotNode());
                  hideAddDropdown = true;
                }}
                class="block w-full px-4 py-2 text-left hover:bg-gray-100 dark:hover:bg-gray-600 dark:hover:text-white"
              >
                VoiceBot
              </button>
            </li>

            <li>
              <button
                type="button"
                on:click={() => {
                  newNode(new WeekTimeNode());
                  hideAddDropdown = true;
                }}
                class="block w-full px-4 py-2 text-left hover:bg-gray-100 dark:hover:bg-gray-600 dark:hover:text-white"
              >
                WeekTime
              </button>
            </li>
            <li>
              <button
                type="button"
                on:click={() => {
                  newNode(new PlayNode());
                  hideAddDropdown = true;
                }}
                class="block w-full px-4 py-2 text-left hover:bg-gray-100 dark:hover:bg-gray-600 dark:hover:text-white"
              >
                Play
              </button>
            </li>
            <li>
              <button
                type="button"
                on:click={() => {
                  newNode(new MenuNode());
                  hideAddDropdown = true;
                }}
                class="block w-full px-4 py-2 text-left hover:bg-gray-100 dark:hover:bg-gray-600 dark:hover:text-white"
              >
                Menu
              </button>
            </li>
          </ul>
        </div>
      </div>
    </div>
  </div>

  {#if selectedOutlet}
    <div
      class="mb-4 rounded-xl border border-sky-200 bg-sky-50 px-4 py-2.5 text-sm text-sky-800 shadow-sm dark:border-sky-800 dark:bg-sky-950/50 dark:text-sky-200"
    >
      Connecting from <span class="font-semibold">{selectedOutletLabel()}</span>
      .
      {connectionHelpText()} Click the same source connector again to cancel.
    </div>
  {/if}

  {#if graphJson}
    <div
      class="mb-2 flex items-center justify-between gap-3 px-1 text-xs text-slate-500 dark:text-slate-400"
    >
      <span>Scroll inside the canvas to explore more steps.</span>
      <span
        class="rounded-full border border-slate-200 bg-white px-2 py-1 font-medium shadow-sm dark:border-slate-700 dark:bg-slate-900"
      >
        Drag blocks, scroll canvas, then connect routes
      </span>
    </div>
    <div
      bind:this={flowCanvas}
      class="flow-canvas relative flex min-h-[28rem] flex-row flex-wrap content-start items-start gap-6 overflow-auto rounded-2xl border border-dashed border-slate-300 p-4 dark:border-slate-700"
      on:scroll={scheduleLineRefresh}
    >
      <StartNode
        {selectedOutlet}
        connected={Boolean(graphJson.start)}
        on:outletSelected={onOutletSelected}
        on:disconnectOutlet={onDisconnectOutlet}
      />
      {#each Object.entries(graphJson?.nodes ?? {}) as [key, node]}
        <svelte:component
          this={node.component}
          bind:this={nodesComponents[key]}
          {selectedOutlet}
          inletConnected={isInletConnected(node.data.id)}
          inletConnectable={isInletConnectable(node.data.id)}
          {node}
          on:close={() => deleteNode(node)}
          on:outletSelected={onOutletSelected}
          on:disconnectOutlet={onDisconnectOutlet}
          on:disconnectInlet={onDisconnectInlet}
          on:inletSelected={onInletIdSelected}
          on:dragEnd={onDragEnded}
          on:updated={onUpdated}
          on:statusChanged={onStatusChanged}
        />
      {/each}
    </div>
    {#if isUploading}
      <ul class="space-y-4 mb-4">
        {#each statusArray as statusItem}
          {#if statusItem.status === 'uploading'}
            <li>
              <div class="mb-4">
                <svg
                  width="400"
                  height="15"
                  viewBox="0 0 400 15"
                  xmlns="http://www.w3.org/2000/svg"
                >
                  <rect x="0" y="0" width="400" height="15" fill="#eee" rx="6" />
                  <rect x="-400" y="0" width="400" height="15" fill="#007bff" rx="6">
                    <animate
                      attributeName="x"
                      from="-400"
                      to="400"
                      dur="2s"
                      repeatCount="indefinite"
                    />
                  </rect>
                </svg>
              </div>
            </li>
          {:else if statusItem.status === 'completed'}
            <li>
              <div class="flex space-x-2 w-[400px]">
                <div class="h-4 w-[490px] dark:bg-green-500 bg-green-600 rounded-md"></div>
                <svg
                  class="w-6 h-6 text-gray-800 dark:text-white"
                  aria-hidden="true"
                  xmlns="http://www.w3.org/2000/svg"
                  width="24"
                  height="24"
                  fill="none"
                  viewBox="0 0 24 24"
                >
                  <path
                    stroke="currentColor"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M5 11.917 9.724 16.5 19 7.5"
                  />
                </svg>
              </div>
            </li>
          {/if}
        {/each}
      </ul>
    {/if}
  {/if}
</div>

<style lang="postcss">
  .flow-canvas {
    background-color: rgba(248, 250, 252, 0.8);
    background-image:
      linear-gradient(rgba(148, 163, 184, 0.15) 1px, transparent 1px),
      linear-gradient(90deg, rgba(148, 163, 184, 0.15) 1px, transparent 1px);
    background-size: 24px 24px;
    scrollbar-gutter: stable both-edges;
  }

  :global(.dark) .flow-canvas {
    background-color: rgba(15, 23, 42, 0.55);
  }

  .flow-canvas::-webkit-scrollbar {
    height: 12px;
    width: 12px;
  }

  .flow-canvas::-webkit-scrollbar-track {
    background: rgba(148, 163, 184, 0.18);
    border-radius: 9999px;
  }

  .flow-canvas::-webkit-scrollbar-thumb {
    background: rgba(15, 118, 110, 0.65);
    border-radius: 9999px;
    border: 2px solid transparent;
    background-clip: padding-box;
  }

  :global(.dark) .flow-canvas::-webkit-scrollbar-track {
    background: rgba(51, 65, 85, 0.6);
  }

  :global(.dark) .flow-canvas::-webkit-scrollbar-thumb {
    background: rgba(45, 212, 191, 0.7);
    border-color: transparent;
  }
</style>
