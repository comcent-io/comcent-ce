<script lang="ts">
  import { page } from '$app/state';
  import { postJson } from '$lib/http';
  import toast from '$lib/toast';
  import { publicSipUserRootDomain } from '$lib/publicConfig';
  import UserAvatar from '$lib/components/UserAvatar.svelte';
  import Button from '$lib/components/Button.svelte';
  import Pill from '$lib/components/Pill.svelte';
  import PageHeader from '$lib/components/form/PageHeader.svelte';
  import FormSection from '$lib/components/form/FormSection.svelte';
  import Field from '$lib/components/form/Field.svelte';
  import Select from '$lib/components/form/Select.svelte';
  let { data } = $props();
  const sipDomain = publicSipUserRootDomain || 'example.com';
  let isLoading = $state(false);
  let hasChanged = $state(false);
  // A local copy the page edits and saves.
  // svelte-ignore state_referenced_locally
  let memberProfile = $state(data.member);
  // svelte-ignore state_referenced_locally
  let selectedNumber = $state(memberProfile.number?.number || '');

  let sipAddress = $derived(`${memberProfile.username}@${page.params.subdomain}.${sipDomain}`);

  async function handleNumberUpdate(event: Event) {
    event.preventDefault();
    isLoading = true;
    const result = await postJson(`/api/v2/${page.params.subdomain}/members/default-number`, {
      number: selectedNumber,
    });

    if (!result.ok) {
      toast.error(result.error || 'Failed to update member default number.');
      isLoading = false;
      return;
    }

    memberProfile = {
      ...memberProfile,
      number: data.numbers.find((number: any) => number.number === selectedNumber) ?? null,
    };
    isLoading = false;
    hasChanged = false;
    toast.success('Default outbound number saved.');
  }
</script>

<PageHeader
  title="My profile"
  description="Who you are in this organisation, and the number people see when you call them."
/>

<div class="max-w-3xl space-y-6">
  <FormSection title="Account">
    <div class="flex flex-wrap items-center gap-5">
      <UserAvatar
        picture={data.user.picture}
        name={data.user.name}
        email={data.user.email}
        size="lg"
      />
      <div class="min-w-0">
        <div class="flex flex-wrap items-center gap-2">
          <p class="text-xl font-semibold text-gray-900 dark:text-white">{data.user.name}</p>
          <Pill tone={memberProfile.role === 'ADMIN' ? 'cyan' : 'gray'}>
            {memberProfile.role === 'ADMIN' ? 'Admin' : 'Member'}
          </Pill>
        </div>
        <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">{data.user.email}</p>
      </div>
    </div>
    <dl
      class="grid gap-4 border-t border-gray-200 pt-5 text-sm sm:grid-cols-2 dark:border-gray-700"
    >
      <div>
        <dt class="text-gray-500 dark:text-gray-400">SIP username</dt>
        <dd class="mt-1 font-medium text-gray-900 dark:text-white">{memberProfile.username}</dd>
      </div>
      <div>
        <dt class="text-gray-500 dark:text-gray-400">SIP address</dt>
        <dd class="mt-1 break-all font-medium text-gray-900 dark:text-white">{sipAddress}</dd>
      </div>
    </dl>
  </FormSection>

  <FormSection
    title="Outbound calls"
    description="The number your outbound calls come from, unless you pick another when dialling."
  >
    <form class="space-y-5" onsubmit={handleNumberUpdate}>
      <Field label="Default outbound number" for="defaultNumber">
        <Select
          id="defaultNumber"
          name="numberId"
          bind:value={selectedNumber}
          onchange={() => (hasChanged = true)}
        >
          <option value="" disabled>Choose a number</option>
          {#each data.numbers as number}
            <option value={number.number}>{number.name} ({number.number})</option>
          {/each}
        </Select>
      </Field>
      <Button type="submit" progress={isLoading} disabled={!hasChanged}>Save</Button>
    </form>
  </FormSection>
</div>
