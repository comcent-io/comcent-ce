<script lang="ts">
  import { page } from '$app/state';
  import { goto } from '$app/navigation';
  import Button from '$lib/components/Button.svelte';
  import ErrorMessage from '$lib/components/ErrorMessage.svelte';
  import Field from '$lib/components/form/Field.svelte';
  import FormActions from '$lib/components/form/FormActions.svelte';
  import FormSection from '$lib/components/form/FormSection.svelte';
  import Input from '$lib/components/form/Input.svelte';
  import Select from '$lib/components/form/Select.svelte';
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
  class="space-y-6"
>
  {#if errorMessage}
    <ErrorMessage error={{ message: errorMessage, formErrors: [] }} />
  {/if}

  <FormSection
    title="Number details"
    description="The phone number, the trunk it comes in on, and which numbers it may call."
  >
    <div class="grid gap-5 lg:grid-cols-2">
      <Field for="name" label="Name" hint="How this number is shown in Comcent.">
        <Input
          type="text"
          id="name"
          name="name"
          placeholder="Friendly Name"
          required
          bind:value={formData.name}
        />
      </Field>
      <Field for="number" label="Number" hint="In E.164 form, e.g. +14155550123.">
        <Input
          type="text"
          id="number"
          name="number"
          placeholder="Number in E.164 format"
          required
          bind:value={formData.number}
        />
      </Field>
      <Field for="sipTrunkId" label="SIP trunk" hint="The carrier this number's calls use.">
        <Select id="sipTrunkId" name="sipTrunkId" bind:value={formData.sipTrunkId}>
          {#each sipTrunks as trunk (trunk.id)}
            <option value={trunk.id} selected={trunk.id === formData.sipTrunkId}>
              {trunk.name}
            </option>
          {/each}
        </Select>
      </Field>
      <Field
        for="allowOutboundRegex"
        label="Allowed outbound destinations"
        optional
        hint={`A regular expression. Outbound calls from this number to a destination that doesn't match are refused. Destinations are checked in E.164 form (+14155550123), so ^\\+1[0-9]{10}$ allows only North American numbers. Leave empty to allow any destination.`}
      >
        <Input
          type="text"
          id="allowOutboundRegex"
          name="allowOutboundRegex"
          placeholder={'^\\+1[0-9]{10}$'}
          bind:value={formData.allowOutboundRegex}
        />
      </Field>
    </div>
  </FormSection>

  <section>
    <FlowDiagram
      bind:this={flowDiagram}
      inboundFlowGraph={formData.inboundFlowGraph || defaultInboundFlow}
      onUpdate={(json) => (formData.inboundFlowGraph = json)}
    />
  </section>

  <FormActions cancelHref={`/app/${subdomain}/numbers`}>
    <Button onclick={handleSubmit} progress={isLoading}>{isUpdate ? 'Update' : 'Add'}</Button>
  </FormActions>
</form>
