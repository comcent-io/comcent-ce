<script lang="ts">
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import { env } from '$env/dynamic/public';
  import Card from '$lib/components/Card.svelte';
  import H3 from '$lib/components/html/H3.svelte';
  import Button from '$lib/components/Button.svelte';
  import { getJson, postJson } from '$lib/http';
  import type { CreateOrgSchema } from '../schema';

  const { PUBLIC_SIP_DOMAIN } = env;

  type CountryState = {
    name: string;
    code: string;
  };

  type Country = {
    code: string;
    name: string;
    states: CountryState[];
  };

  let countries: Country[] = [];
  let countryStatesMap: Record<string, CountryState[]> = {};
  let formData: CreateOrgSchema = {
    name: '',
    subdomain: '',
    useCustomDomain: false,
    customDomain: '',
    sipUsername: '',
    userExt: '',
    assignExtAutomatically: false,
    autoExtStart: '1000',
    autoExtEnd: '9999',
    userName: '',
    country: '',
    state: '',
    city: '',
    zip: '',
  };

  let errorMessage = '';
  let loading = false;
  let orgCreationInProgress = false;

  onMount(() => {
    void loadContext();
  });

  async function loadContext() {
    // CE: billing address is not collected at org creation time. No context
    // fetch needed.
    loading = false;
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
      userName: '',
      country: '',
      state: '',
      city: '',
      zip: '',
    };
  }

  async function handleOrgCreation(event: SubmitEvent) {
    event.preventDefault();
    if (orgCreationInProgress) return;

    orgCreationInProgress = true;
    errorMessage = '';

    try {
      const payload = buildFormData();
      const result = await postJson('/api/v2/user/orgs', payload);
      if (!result.ok) {
        if (result.status === 401) {
          await goto('/login');
          return;
        }
        errorMessage = result.error;
        return;
      }

      await goto('/org', { invalidateAll: true });
    } finally {
      orgCreationInProgress = false;
    }
  }
</script>

<div class="mx-auto max-w-4xl">
  {#if errorMessage}
    <div
      class="p-4 mb-4 pt-4 text-sm text-red-800 rounded-lg bg-red-50 dark:bg-gray-800 dark:text-red-400"
      role="alert"
    >
      {errorMessage}
    </div>
  {/if}
  {#if loading}
    <div
      class="p-4 mb-4 text-sm text-gray-800 rounded-lg bg-gray-50 dark:bg-gray-800 dark:text-gray-300"
    >
      Loading organization setup...
    </div>
  {/if}
  <form method="POST" on:submit={handleOrgCreation}>
    <div class="mx-auto max-w-xl pt-14">
      <div class="">
        <Card className="mb-4">
          <H3>Your Details</H3>
          <div>
            <label
              for="sipUsername"
              class="block mb-2 text-sm font-medium text-gray-900 dark:text-white"
            >
              Sip username
            </label>
            <input
              type="text"
              id="sipUsername"
              name="sipUsername"
              class="bg-gray-50 border border-gray-300 text-gray-900 text-sm rounded-lg focus:ring-blue-500 focus:border-blue-500 block w-full p-2.5 dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500"
              placeholder="your.name"
              bind:value={formData.sipUsername}
              required
            />
          </div>
        </Card>

        <Card>
          <H3>Organizations Details</H3>
          <div class="mb-4">
            <label for="name" class="block mb-2 text-sm font-medium text-gray-900 dark:text-white">
              Organization Name
            </label>
            <input
              type="text"
              id="name"
              name="name"
              class="bg-gray-50 border border-gray-300 text-gray-900 text-sm rounded-lg focus:ring-blue-500 focus:border-blue-500 block w-full p-2.5 dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500"
              placeholder="ACME Corp"
              bind:value={formData.name}
              required
            />
          </div>

          <div>
            <label
              for="subdomain"
              class="block mb-2 text-sm font-medium text-gray-900 dark:text-white"
            >
              Sub domain (Cannot be changed later)
            </label>
            <input
              type="text"
              id="subdomain"
              name="subdomain"
              class="bg-gray-50 border border-gray-300 text-gray-900 text-sm rounded-lg focus:ring-blue-500 focus:border-blue-500 block w-full p-2.5 dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500"
              placeholder="acme"
              bind:value={formData.subdomain}
              required
            />
          </div>
          {#if formData.subdomain}
            <div
              class="p-4 mb-4 text-sm text-blue-800 rounded-lg bg-blue-50 dark:bg-gray-800 dark:text-blue-400"
              role="alert"
            >
              <span class="font-medium">{formData.subdomain}.{PUBLIC_SIP_DOMAIN}</span>
              will be your domain.
            </div>
          {/if}

          <!--    <div class="flex items-center mb-3">-->
          <!--      <input-->
          <!--        bind:checked={formData.useCustomDomain}-->
          <!--        id="customDomain"-->
          <!--        name="customDomain"-->
          <!--        type="checkbox"-->
          <!--        value="true"-->
          <!--        class="w-4 h-4 text-blue-600 bg-gray-100 border-gray-300 rounded focus:ring-blue-500 dark:focus:ring-blue-600 dark:ring-offset-gray-800 focus:ring-2 dark:bg-gray-700 dark:border-gray-600"-->
          <!--      />-->
          <!--      <label for="customDomain" class="ml-2 text-sm font-medium text-gray-900 dark:text-gray-300">-->
          <!--        Use custom domain-->
          <!--      </label>-->
          <!--    </div>-->

          <!--    {#if formData.useCustomDomain}-->
          <!--      <div-->
          <!--        class="p-4 mb-4 text-sm text-blue-800 rounded-lg bg-blue-50 dark:bg-gray-800 dark:text-blue-400"-->
          <!--        role="alert"-->
          <!--      >-->
          <!--        <span class="font-medium">Coming soon!</span>-->
          <!--        This feature coming soon.-->
          <!--      </div>-->
          <!--    {/if}-->

          <!--      <div class="flex items-center mb-3">-->
          <!--        <input-->
          <!--          bind:checked={formData.assignExtAutomatically}-->
          <!--          id="randomExt"-->
          <!--          name="randomExt"-->
          <!--          type="checkbox"-->
          <!--          value="true"-->
          <!--          class="w-4 h-4 text-blue-600 bg-gray-100 border-gray-300 rounded focus:ring-blue-500 dark:focus:ring-blue-600 dark:ring-offset-gray-800 focus:ring-2 dark:bg-gray-700 dark:border-gray-600"-->
          <!--        />-->
          <!--        <label for="randomExt" class="ml-2 text-sm font-medium text-gray-900 dark:text-gray-300">-->
          <!--          Assign extension automatically-->
          <!--        </label>-->
          <!--      </div>-->

          <!--      {#if formData.assignExtAutomatically}-->
          <!--        <div class="mb-4">-->
          <!--          <label-->
          <!--            for="autoExtStart"-->
          <!--            class="block mb-2 text-sm font-medium text-gray-900 dark:text-white"-->
          <!--          >-->
          <!--            Start Extension for Auto Assignment-->
          <!--          </label>-->
          <!--          <input-->
          <!--            type="text"-->
          <!--            id="autoExtStart"-->
          <!--            name="autoExtStart"-->
          <!--            class="bg-gray-50 border border-gray-300 text-gray-900 text-sm rounded-lg focus:ring-blue-500 focus:border-blue-500 block w-full p-2.5 dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500"-->
          <!--            placeholder="1001"-->
          <!--            bind:value={formData.autoExtStart}-->
          <!--          />-->
          <!--        </div>-->
          <!--        <div class="mb-4">-->
          <!--          <label-->
          <!--            for="autoExtEnd"-->
          <!--            class="block mb-2 text-sm font-medium text-gray-900 dark:text-white"-->
          <!--          >-->
          <!--            End Extension for Auto Assignment-->
          <!--          </label>-->
          <!--          <input-->
          <!--            type="text"-->
          <!--            id="autoExtEnd"-->
          <!--            name="autoExtEnd"-->
          <!--            class="bg-gray-50 border border-gray-300 text-gray-900 text-sm rounded-lg focus:ring-blue-500 focus:border-blue-500 block w-full p-2.5 dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500"-->
          <!--            placeholder="9999"-->
          <!--            bind:value={formData.autoExtEnd}-->
          <!--          />-->
          <!--        </div>-->
          <!--      {:else}-->
          <!--        <div class="mb-8">-->
          <!--          <label for="ext" class="block mb-2 text-sm font-medium text-gray-900 dark:text-white">-->
          <!--            Extension (Optional)-->
          <!--          </label>-->
          <!--          <input-->
          <!--            type="text"-->
          <!--            id="ext"-->
          <!--            name="ext"-->
          <!--            class="bg-gray-50 border border-gray-300 text-gray-900 text-sm rounded-lg focus:ring-blue-500 focus:border-blue-500 block w-full p-2.5 dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500"-->
          <!--            placeholder="1001"-->
          <!--            bind:value={formData.userExt}-->
          <!--          />-->
          <!--        </div>-->
          <!--      {/if}-->
        </Card>
      </div>
      <div class="mb-4">
        <Button type="submit" progress={orgCreationInProgress}>Create Organization</Button>
      </div>
    </div>
  </form>
</div>
