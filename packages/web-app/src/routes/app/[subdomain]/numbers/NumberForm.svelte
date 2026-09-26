<script lang="ts">
  import { page } from '$app/state';
  import { goto } from '$app/navigation';
  import FlowDiagram from './flow/FlowDiagram.svelte';
  import type { numberData } from './schema';
  let flowDiagram: FlowDiagram | undefined = $state();
  let isLoading = $state(false);
  let errorMessage = $state('');
  const subdomain = page.params.subdomain;

  async function handleSubmit() {
    isLoading = true;
    errorMessage = '';
    try {
      await flowDiagram?.triggerUploads();
      await flowDiagram?.cleanupUploads();

      if (!formData.allowOutboundRegex) {
        formData.allowOutboundRegex = '';
      }
      if (!formData.inboundFlowGraph) {
        formData.inboundFlowGraph = defaultInboundFlow;
      } else if (typeof formData.inboundFlowGraph !== 'string') {
        formData.inboundFlowGraph = JSON.stringify(formData.inboundFlowGraph);
      }
      if (isUpdate) {
        const response = await fetch(`/api/v2/${subdomain}/numbers/${formData.id}`, {
          method: 'PUT',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(formData),
        });
        if (!response.ok) throw new Error((await response.json()).error ?? response.statusText);
      } else {
        const response = await fetch(`/api/v2/${subdomain}/numbers`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(formData),
        });
        if (!response.ok) throw new Error((await response.json()).error ?? response.statusText);
      }
      goto(`/app/${subdomain}/numbers`, { invalidateAll: true });
    } catch (error: any) {
      if (error.message.includes('Number already exists')) {
        errorMessage = 'Number already exists';
      } else {
        try {
          const errorJson = JSON.parse(error.message);
          errorMessage = errorJson[0].message;
        } catch {
          errorMessage = error.message;
        }
      }
    } finally {
      isLoading = false;
    }
  }

  const defaultInboundFlow = JSON.stringify({
    start: '',
    nodes: {},
    outlets: {},
  });
  interface Props {
    sipTrunks?: any[];
    formData?: numberData;
    isUpdate?: boolean;
  }

  let {
    sipTrunks = [],
    formData = $bindable({
      id: '',
      number: '',
      name: '',
      sipTrunkId: '',
      allowOutboundRegex: '',
      inboundFlowGraph: defaultInboundFlow,
    }),
    isUpdate = false,
  }: Props = $props();
</script>

<form
  onsubmit={(e) => {
    e.preventDefault();
    handleSubmit();
  }}
  class="space-y-8"
>
  {#if errorMessage}
    <div class="mb-4 rounded-lg border border-red-200 bg-red-50 px-4 py-3 text-red-600">
      {errorMessage}
    </div>
  {/if}

  <section
    class="rounded-2xl border border-slate-200 bg-white p-6 shadow-sm dark:border-slate-700 dark:bg-slate-900/60"
  >
    <div class="mb-4">
      <h4 class="text-xl font-semibold text-slate-900 dark:text-white">Number details</h4>
      <p class="mt-1 text-sm text-slate-600 dark:text-slate-300">
        Set the phone number, its trunk, and optional outbound restrictions before defining the
        inbound flow.
      </p>
    </div>

    <div class="grid gap-6 lg:grid-cols-2">
      <div>
        <label for="name" class="mb-2 block text-sm font-medium text-gray-900 dark:text-white">
          Name
        </label>
        <input
          type="text"
          id="name"
          name="name"
          class="block w-full rounded-lg border border-gray-300 bg-gray-50 p-2.5 text-sm text-gray-900 focus:border-blue-500 focus:ring-blue-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white dark:placeholder-gray-400 dark:focus:border-blue-500 dark:focus:ring-blue-500"
          placeholder="Friendly Name"
          required
          bind:value={formData.name}
        />
      </div>
      <div>
        <label for="number" class="mb-2 block text-sm font-medium text-gray-900 dark:text-white">
          Number (E.164)
        </label>
        <input
          type="text"
          id="number"
          name="number"
          class="block w-full rounded-lg border border-gray-300 bg-gray-50 p-2.5 text-sm text-gray-900 focus:border-blue-500 focus:ring-blue-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white dark:placeholder-gray-400 dark:focus:border-blue-500 dark:focus:ring-blue-500"
          placeholder="Number in E.164 format"
          required
          bind:value={formData.number}
        />
      </div>
      <div>
        <label
          for="sipTrunkId"
          class="mb-2 block text-sm font-medium text-gray-900 dark:text-white"
        >
          SIP Trunk
        </label>
        <select
          id="sipTrunkId"
          name="sipTrunkId"
          bind:value={formData.sipTrunkId}
          class="block w-full rounded-lg border border-gray-300 bg-gray-50 p-2.5 text-sm text-gray-900 focus:border-blue-500 focus:ring-blue-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white dark:placeholder-gray-400 dark:focus:border-blue-500 dark:focus:ring-blue-500"
        >
          {#each sipTrunks as trunk}
            <option value={trunk.id} selected={trunk.id === formData.sipTrunkId}>
              {trunk.name}
            </option>
          {/each}
        </select>
      </div>
      <div>
        <label
          for="allowOutboundRegex"
          class="mb-2 block text-sm font-medium text-gray-900 dark:text-white"
        >
          Allow Outbound if destination matches regex
        </label>
        <input
          type="text"
          id="allowOutboundRegex"
          name="allowOutboundRegex"
          class="block w-full rounded-lg border border-gray-300 bg-gray-50 p-2.5 text-sm text-gray-900 focus:border-blue-500 focus:ring-blue-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white dark:placeholder-gray-400 dark:focus:border-blue-500 dark:focus:ring-blue-500"
          placeholder={'^\\+1[0-9]{10}$'}
          aria-describedby="allowOutboundRegexHelp"
          bind:value={formData.allowOutboundRegex}
        />
        <p id="allowOutboundRegexHelp" class="mt-1 text-xs text-slate-500 dark:text-slate-400">
          {`Outbound calls from this number to a destination that doesn't match are refused. Destinations are checked in E.164 form (+14155550123), so ^\\+1[0-9]{10}$ allows only North American numbers. Leave empty to allow any destination.`}
        </p>
      </div>
    </div>
  </section>

  <section>
    <FlowDiagram
      bind:this={flowDiagram}
      inboundFlowGraph={formData.inboundFlowGraph || defaultInboundFlow}
      onUpdate={(json) => (formData.inboundFlowGraph = json)}
    />
  </section>

  <button
    type="button"
    onclick={handleSubmit}
    disabled={isLoading}
    class="w-full rounded-lg bg-blue-700 px-5 py-3 text-center text-sm font-medium text-white focus:outline-none focus:ring-4 focus:ring-blue-300 hover:bg-blue-800 sm:w-auto dark:bg-blue-600 dark:hover:bg-blue-700 dark:focus:ring-blue-800"
  >
    {#if isLoading}
      <!-- Tailwind CSS Spinner -->
      <svg
        class="animate-spin -ml-1 mr-3 h-5 w-5 text-white"
        xmlns="http://www.w3.org/2000/svg"
        fill="none"
        viewBox="0 0 24 24"
      >
        <circle
          class="opacity-25"
          cx="12"
          cy="12"
          r="10"
          stroke="currentColor"
          stroke-width="4"
        ></circle>
        <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 010-16v8h8"></path>
      </svg>
    {:else}
      {isUpdate ? 'Update' : 'Add'}
    {/if}
  </button>
</form>
