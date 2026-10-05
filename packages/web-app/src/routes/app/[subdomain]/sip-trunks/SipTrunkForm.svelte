<script lang="ts">
  import { page } from '$app/state';
  import { goto } from '$app/navigation';
  import { getJson, postJson, putJson } from '$lib/http';
  import { sipTrunkCreateSchema } from './schema';
  import ErrorMessage from '$lib/components/ErrorMessage.svelte';
  import Button from '$lib/components/Button.svelte';
  import Field from '$lib/components/form/Field.svelte';
  import FormActions from '$lib/components/form/FormActions.svelte';
  import FormSection from '$lib/components/form/FormSection.svelte';
  import Checkbox from '$lib/components/form/Checkbox.svelte';
  import Hint from '$lib/components/form/Hint.svelte';
  import Input from '$lib/components/form/Input.svelte';
  import Label from '$lib/components/form/Label.svelte';
  import SecondaryButton from '$lib/components/form/SecondaryButton.svelte';
  import Textarea from '$lib/components/form/Textarea.svelte';
  import toast from '$lib/toast';

  type FormError = { message: string; formErrors: { message: string; path: string[] }[] };
  interface Props {
    formData?: any;
    isUpdate?: boolean;
    showCredentialFields?: boolean;
    error?: FormError | null;
  }

  let {
    formData = $bindable({}),
    isUpdate = false,
    showCredentialFields = $bindable(false),
    error = $bindable(null),
  }: Props = $props();
  let isLoading = $state(false);

  // The addresses the customer configures on their carrier. They differ per
  // deployment, so they come from the server; one that isn't configured is
  // left out rather than guessed, because a wrong address gets calls rejected.
  type TrunkSettings = { publicIp: string | null; sipHost: string | null };
  let settings = $state<TrunkSettings>({ publicIp: null, sipHost: null });

  $effect(() => {
    const subdomain = page.params.subdomain;
    getJson<TrunkSettings>(`/api/v2/${subdomain}/sip-trunks/settings`).then((result) => {
      if (result.ok) settings = result.data;
    });
  });

  async function copy(value: string) {
    try {
      await navigator.clipboard.writeText(value);
      toast.success('Copied');
    } catch {
      toast.error('Could not copy. Select the text and copy it instead.');
    }
  }

  async function handleSubmit(event: Event) {
    event.preventDefault();
    isLoading = true;
    const inputModified = {
      ...formData,
      // Only checked, and sent, while "Provide Outbound Credentials" is
      // ticked. A trunk saved without them loads with both null, which the
      // schema's optional strings refuse: editing such a trunk failed even
      // with the box unticked.
      outboundUsername: showCredentialFields
        ? String(formData.outboundUsername ?? '').trim()
        : undefined,
      outboundPassword: showCredentialFields ? String(formData.outboundPassword ?? '') : undefined,
      inboundIps: String(formData.inboundIps ?? '')
        .split(',')
        .map((s) => s.trim())
        .filter(Boolean),
    };

    try {
      const parsed = sipTrunkCreateSchema.parse(inputModified);
      if (showCredentialFields && (!parsed.outboundUsername || !parsed.outboundPassword)) {
        throw new Error(
          'Enter both the username and the password, or untick Provide Outbound Credentials.',
        );
      }
      const payload = {
        name: parsed.name,
        outboundUsername: showCredentialFields ? parsed.outboundUsername : null,
        outboundPassword: showCredentialFields ? parsed.outboundPassword : null,
        outboundContact: parsed.outboundContact,
        inboundIps: parsed.inboundIps,
      };

      const result = isUpdate
        ? await putJson(`/api/v2/${page.params.subdomain}/sip-trunks/${formData.id}`, payload)
        : await postJson(`/api/v2/${page.params.subdomain}/sip-trunks`, payload);

      if (!result.ok) {
        error = { message: result.error, formErrors: [] };
        isLoading = false;
        return;
      }

      error = null;
      await goto(`/app/${page.params.subdomain}/sip-trunks`, { invalidateAll: true });
    } catch (err: any) {
      const errors: any[] = [];
      if (err.errors?.length) {
        for (let i = 0; i < err.errors.length; i++) {
          if (err.errors[i].path[0] === 'inboundIps') {
            const pathvariable = 'inboundIps';
            err.errors.forEach((innerError: any) => {
              if (innerError.path && innerError.path[0] === pathvariable) {
                innerError.message = `Inbound IP Address at position ${innerError.path[1] + 1} is invalid`;
                innerError.path = ['Error'];
              }
            });
          } else if (err.errors[i].path[0] === 'outboundContact') {
            err.errors[i].message = 'Invalid SIP Proxy Address';
            err.errors[i].path = ['Error'];
          }
        }
        errors.push(...err.errors);
      } else if (err.message) {
        errors.push({ message: err.message, path: ['Error'] });
      }
      error = { message: '', formErrors: errors };
    } finally {
      isLoading = false;
    }
  }
</script>

{#snippet copyable(label: string, value: string, hint: string)}
  <div>
    <Label tag="p">{label}</Label>
    <div class="flex items-center gap-2">
      <code
        class="min-w-0 flex-1 truncate rounded-lg border border-gray-200 bg-gray-50 px-3 py-2.5 text-sm text-gray-900 dark:border-gray-600 dark:bg-gray-700 dark:text-white"
      >
        {value}
      </code>
      <SecondaryButton onclick={() => copy(value)}>Copy</SecondaryButton>
    </div>
    <Hint>{hint}</Hint>
  </div>
{/snippet}

<form
  class="max-w-3xl space-y-6"
  onsubmit={(e) => {
    e.preventDefault();
    handleSubmit(e);
  }}
>
  {#if error}
    <ErrorMessage {error} />
  {/if}

  <FormSection title="Details" description="How this trunk is shown in Comcent.">
    <Field for="name" label="Name" hint="3 to 25 characters, e.g. the carrier's name.">
      <Input
        type="text"
        id="name"
        name="name"
        placeholder="Your Name"
        required
        bind:value={formData.name}
      />
    </Field>
  </FormSection>

  <FormSection
    title="Outbound"
    description="Where we send the calls your team makes through this carrier."
  >
    <Field
      for="outboundContact"
      label="SIP proxy address"
      hint="Your carrier's SIP host name or IP address (an IP can include a :port)."
    >
      <Input
        type="text"
        id="outboundContact"
        name="outboundContact"
        placeholder="provider.example.com"
        required
        bind:value={formData.outboundContact}
      />
    </Field>

    <label for="showCredentialFields" class="flex cursor-pointer items-start gap-3">
      <Checkbox
        id="showCredentialFields"
        name="showCredentialFields"
        class="mt-0.5"
        bind:checked={showCredentialFields}
      />
      <span>
        <span class="block text-sm font-medium text-gray-900 dark:text-white">
          Provide Outbound Credentials
        </span>
        <span class="mt-0.5 block text-xs text-gray-500 dark:text-gray-400">
          If your carrier asks for a username and password. Otherwise it recognises us by the
          address we call from.
        </span>
      </span>
    </label>

    {#if showCredentialFields}
      <div class="grid gap-5 sm:grid-cols-2">
        <Field for="outboundUsername" label="Username">
          <Input
            type="text"
            id="outboundUsername"
            name="outboundUsername"
            autocomplete="off"
            placeholder="your username"
            required
            bind:value={formData.outboundUsername}
          />
        </Field>
        <Field for="outboundPassword" label="Password">
          <Input
            type="password"
            id="outboundPassword"
            name="outboundPassword"
            autocomplete="new-password"
            placeholder="Password"
            required
            bind:value={formData.outboundPassword}
          />
        </Field>
      </div>
    {/if}
  </FormSection>

  <FormSection title="Inbound" description="Which addresses may send calls to your numbers.">
    <Field
      for="inboundIps"
      label="Allowed IP ranges"
      hint="The addresses your carrier sends calls from, as comma-separated CIDR ranges (1.2.3.4/32 for a single address)."
    >
      <Textarea
        id="inboundIps"
        name="inboundIps"
        placeholder="2.2.2.0/24"
        rows={3}
        required
        bind:value={formData.inboundIps}
      />
    </Field>
  </FormSection>

  <!-- They differ per deployment and come from the server; one that isn't
       configured is left out rather than guessed. -->
  {#if settings.sipHost || settings.publicIp}
    <FormSection
      title="Point your carrier here"
      description="Set these up at your carrier, so it sends calls to us and accepts ours."
    >
      {#if settings.sipHost}
        {@render copyable(
          'Our SIP server',
          settings.sipHost,
          settings.publicIp
            ? `Where your carrier sends inbound calls (preferred; or the IP ${settings.publicIp}).`
            : 'Where your carrier sends inbound calls.',
        )}
      {:else if settings.publicIp}
        {@render copyable(
          'Our SIP server',
          settings.publicIp,
          'Where your carrier sends inbound calls.',
        )}
      {/if}
      {#if settings.publicIp}
        {@render copyable(
          'IP to allow',
          settings.publicIp,
          'We send outbound calls from this address; add it to your carrier’s allow list.',
        )}
      {/if}
    </FormSection>
  {/if}

  <FormActions cancelHref={`/app/${page.params.subdomain}/sip-trunks`}>
    <Button type="submit" progress={isLoading}>{isUpdate ? 'Update' : 'Create'}</Button>
  </FormActions>
</form>
