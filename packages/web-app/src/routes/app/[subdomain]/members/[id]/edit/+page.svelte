<script lang="ts">
  import { untrack } from 'svelte';
  import { page } from '$app/state';
  import { getJson, postJson, putJson } from '$lib/http';
  import ErrorMessage from '$lib/components/ErrorMessage.svelte';
  import Button from '$lib/components/Button.svelte';
  import Pill from '$lib/components/Pill.svelte';
  import Field from '$lib/components/form/Field.svelte';
  import FormActions from '$lib/components/form/FormActions.svelte';
  import FormSection from '$lib/components/form/FormSection.svelte';
  import Input from '$lib/components/form/Input.svelte';
  import Label from '$lib/components/form/Label.svelte';
  import PageHeader from '$lib/components/form/PageHeader.svelte';
  import SecondaryButton from '$lib/components/form/SecondaryButton.svelte';
  import Select from '$lib/components/form/Select.svelte';
  import type { Roles } from '../../roleSchema';
  import { formatEnum } from '$lib/format';

  type PageError = { message: string; formErrors: { message: string; path: string[] }[] };
  let member: any = $state(null);
  let role: Roles = $state('MEMBER');
  let error: PageError | null = $state(null);
  let isLoading = $state(false);
  let lastFetchKey = '';

  async function fetchMember() {
    const result = await getJson<any>(
      `/api/v2/${page.params.subdomain}/admin/members/${page.params.id}`,
    );
    if (!result.ok) {
      error = { message: result.error, formErrors: [] };
      member = null;
      return;
    }

    member = result.data;
    role = result.data.role;
    error = null;
  }

  async function regeneratePassword() {
    isLoading = true;
    const result = await postJson<any>(
      `/api/v2/${page.params.subdomain}/admin/members/${page.params.id}/regenerate-password`,
      {},
    );

    if (!result.ok) {
      error = { message: result.error, formErrors: [] };
      isLoading = false;
      return;
    }

    await fetchMember();
    error = null;
    isLoading = false;
  }

  async function updateRole() {
    isLoading = true;
    const result = await putJson<any>(
      `/api/v2/${page.params.subdomain}/admin/members/${page.params.id}/role`,
      { role },
    );

    if (!result.ok) {
      error = { message: result.error, formErrors: [] };
      isLoading = false;
      return;
    }

    member = { ...member, role };
    error = null;
    isLoading = false;
  }

  // Refetch when the URL or the org changes. The fetch itself is untracked,
  // so the state it reads and writes does not re-run this.
  $effect(() => {
    const nextFetchKey = `${page.params.subdomain}|${page.params.id}`;
    if (nextFetchKey !== lastFetchKey) {
      lastFetchKey = nextFetchKey;
      untrack(() => fetchMember());
    }
  });
</script>

<PageHeader
  title="Edit member"
  description="This member's phone login, and what they may manage in Comcent."
  backHref={`/app/${page.params.subdomain}/members`}
  backLabel="Members"
/>

<div class="max-w-3xl space-y-6">
  {#if error}
    <ErrorMessage {error} />
  {/if}

  {#if member}
    <FormSection title={member.user.name} description={member.user.email}>
      {#snippet aside()}
        <span data-testid="member-role">
          <Pill tone={member.role === 'ADMIN' ? 'cyan' : 'gray'}>{formatEnum(member.role)}</Pill>
        </span>
      {/snippet}
    </FormSection>

    <FormSection
      title="Phone login"
      description="What this member's softphone or desk phone signs in with."
    >
      <div>
        <Label tag="p">SIP username</Label>
        <code
          class="block truncate rounded-lg border border-gray-200 bg-gray-50 px-3 py-2.5 text-sm text-gray-900 dark:border-gray-600 dark:bg-gray-700 dark:text-white"
        >
          {member.username}
        </code>
      </div>
      <Field
        for="sipPassword"
        label="SIP password"
        hint="Regenerating it signs out every phone using the old one."
      >
        <div class="flex items-center gap-2">
          <Input
            type="password"
            id="sipPassword"
            autocomplete="off"
            readonly
            class="min-w-0 flex-1"
            value={member.sipPassword}
          />
          <SecondaryButton onclick={() => navigator.clipboard.writeText(member.sipPassword)}>
            Copy
          </SecondaryButton>
        </div>
      </Field>
      <SecondaryButton disabled={isLoading} onclick={regeneratePassword}>
        Regenerate password
      </SecondaryButton>
    </FormSection>

    <form
      class="space-y-6"
      onsubmit={(e) => {
        e.preventDefault();
        updateRole();
      }}
    >
      <FormSection title="Role" description="What this member may manage in this organization.">
        <Field
          for="role"
          label="Role"
          hint="Admins can manage members, numbers, billing and settings."
        >
          <Select id="role" name="role" bind:value={role}>
            <option value="ADMIN">Admin</option>
            <option value="MEMBER">Member</option>
          </Select>
        </Field>
      </FormSection>
      <FormActions cancelHref={`/app/${page.params.subdomain}/members`}>
        <Button type="submit" progress={isLoading}>Update</Button>
      </FormActions>
    </form>
  {/if}
</div>
