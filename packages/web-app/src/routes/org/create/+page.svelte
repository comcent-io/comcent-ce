<script lang="ts">
  import { goto } from '$app/navigation';
  import { publicSipUserRootDomain } from '$lib/publicConfig';
  import AccountAlert from '$lib/components/account/AccountAlert.svelte';
  import AccountButton from '$lib/components/account/AccountButton.svelte';
  import AccountField from '$lib/components/account/AccountField.svelte';
  import AccountInput from '$lib/components/account/AccountInput.svelte';
  import SipUsernameField from '$lib/components/account/SipUsernameField.svelte';
  import { postJson } from '$lib/http';
  import { createOrgSchema, type CreateOrgSchema } from '../schema';

  let formData: CreateOrgSchema = $state({
    name: '',
    subdomain: '',
    useCustomDomain: false,
    customDomain: '',
    sipUsername: '',
    userExt: '',
    assignExtAutomatically: false,
    autoExtStart: '1000',
    autoExtEnd: '9999',
  });

  type Field = 'name' | 'subdomain' | 'sipUsername';
  let fieldErrors: Partial<Record<Field, string>> = $state({});
  let errorMessage = $state('');
  let orgCreationInProgress = $state(false);
  // The subdomain follows the name until it is typed in itself.
  let subdomainEdited = $state(false);

  function toSubdomain(name: string) {
    return name
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, '-')
      .replace(/^[^a-z]+/, '')
      .slice(0, 15)
      .replace(/-+$/, '');
  }

  function onNameInput() {
    if (!subdomainEdited) formData.subdomain = toSubdomain(formData.name);
    fieldErrors.name = undefined;
  }

  function onSubdomainInput(event: Event) {
    subdomainEdited = true;
    const input = event.currentTarget as HTMLInputElement;
    formData.subdomain = input.value.toLowerCase().replace(/\s/g, '');
    fieldErrors.subdomain = undefined;
  }

  function buildFormData(): CreateOrgSchema {
    return {
      name: formData.name.trim(),
      subdomain: formData.subdomain.trim(),
      useCustomDomain: formData.useCustomDomain,
      customDomain: (formData.customDomain ?? '').trim(),
      sipUsername: formData.sipUsername.trim(),
      userExt: (formData.userExt ?? '').trim(),
      assignExtAutomatically: formData.assignExtAutomatically,
      autoExtStart: (formData.autoExtStart ?? '').trim() || '1000',
      autoExtEnd: (formData.autoExtEnd ?? '').trim() || '9999',
    };
  }

  function validate(payload: CreateOrgSchema) {
    const parsed = createOrgSchema.safeParse(payload);
    const errors: Partial<Record<Field, string>> = {};
    if (!parsed.success) {
      for (const issue of parsed.error.issues) {
        const field = issue.path[0] as Field;
        if (field === 'name' || field === 'subdomain' || field === 'sipUsername') {
          errors[field] ??= issue.message;
        }
      }
    }
    fieldErrors = errors;
    return Object.keys(errors).length === 0;
  }

  async function handleOrgCreation(event: SubmitEvent) {
    event.preventDefault();
    if (orgCreationInProgress) return;

    errorMessage = '';
    const payload = buildFormData();
    if (!validate(payload)) return;

    orgCreationInProgress = true;
    try {
      const result = await postJson<{ org: { subdomain: string } }>('/api/v2/user/orgs', payload);
      if (!result.ok) {
        if (result.status === 401) {
          await goto('/login');
          return;
        }
        errorMessage = result.error;
        return;
      }

      // Straight into the new org.
      await goto(`/app/${result.data.org.subdomain}`, { invalidateAll: true });
    } finally {
      orgCreationInProgress = false;
    }
  }
</script>

<section class="min-h-screen px-4 py-10 sm:py-16">
  <div class="mx-auto max-w-xl">
    <a
      href="/org"
      class="text-sm text-slate-500 hover:text-slate-900 dark:text-slate-400 dark:hover:text-white"
    >
      ← Your organizations
    </a>

    <p class="mt-8 text-sm uppercase tracking-[0.3em] text-cyan-600 dark:text-cyan-300">Comcent</p>
    <h1 class="mt-2 text-3xl font-semibold text-slate-900 dark:text-white">
      Create your organization
    </h1>
    <p class="mt-2 text-sm text-slate-500 dark:text-slate-400">
      Your team's workspace for numbers, calls and voice bots. You can invite teammates once it is
      set up.
    </p>

    <form
      method="POST"
      novalidate
      onsubmit={handleOrgCreation}
      class="mt-8 space-y-8 rounded-3xl border border-slate-200 bg-white p-6 shadow-xl sm:p-8 dark:border-slate-700 dark:bg-slate-800"
    >
      {#if errorMessage}
        <AccountAlert>{errorMessage}</AccountAlert>
      {/if}

      <fieldset class="space-y-5">
        <legend class="mb-4 text-xs font-semibold uppercase tracking-wider text-slate-400">
          Organization
        </legend>

        <AccountField for="name" label="Organization name" error={fieldErrors.name}>
          <AccountInput
            type="text"
            id="name"
            name="name"
            placeholder="ACME Corp"
            autocomplete="organization"
            bind:value={formData.name}
            oninput={onNameInput}
            invalid={!!fieldErrors.name}
            required
          />
        </AccountField>

        <AccountField
          for="subdomain"
          label="Subdomain"
          error={fieldErrors.subdomain}
          hintId="subdomainHint"
          hint="Lowercase letters, numbers and hyphens. It can't be changed later."
        >
          <!-- The input and its domain suffix share one border. -->
          <div
            class="flex overflow-hidden rounded-xl border bg-white focus-within:border-cyan-500 focus-within:ring-1 focus-within:ring-cyan-500 dark:bg-slate-900 {fieldErrors.subdomain
              ? 'border-red-400 dark:border-red-500'
              : 'border-slate-300 dark:border-slate-600'}"
          >
            <input
              type="text"
              id="subdomain"
              name="subdomain"
              class="min-w-0 flex-1 border-0 bg-transparent px-4 py-3 text-sm text-slate-900 placeholder-slate-400 focus:outline-none focus:ring-0 dark:text-white"
              placeholder="acme"
              autocomplete="off"
              autocapitalize="off"
              spellcheck="false"
              maxlength="15"
              value={formData.subdomain}
              oninput={onSubdomainInput}
              aria-invalid={!!fieldErrors.subdomain}
              aria-describedby="subdomainHint"
              required
            />
            <span
              class="flex items-center border-l border-slate-200 bg-slate-50 px-3 text-sm text-slate-500 dark:border-slate-700 dark:bg-slate-800 dark:text-slate-400"
            >
              .{publicSipUserRootDomain}
            </span>
          </div>
        </AccountField>
      </fieldset>

      <fieldset class="space-y-5 border-t border-slate-200 pt-8 dark:border-slate-700">
        <legend
          class="float-left mb-4 text-xs font-semibold uppercase tracking-wider text-slate-400"
        >
          You
        </legend>

        <div class="clear-left">
          <SipUsernameField
            bind:value={formData.sipUsername}
            subdomain={formData.subdomain}
            error={fieldErrors.sipUsername}
            oninput={() => (fieldErrors.sipUsername = undefined)}
          />
        </div>
      </fieldset>

      <AccountButton progress={orgCreationInProgress}>Create Organization</AccountButton>
    </form>
  </div>
</section>
