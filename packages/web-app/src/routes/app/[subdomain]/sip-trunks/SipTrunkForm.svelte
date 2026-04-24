<script lang="ts">
  import { page } from '$app/stores';
  import { goto } from '$app/navigation';
  import { postJson, putJson } from '$lib/http';
  import { sipTrunkCreateSchema } from './schema';
  import ErrorMessage from '$lib/components/ErrorMessage.svelte';

  type FormError = { message: string; formErrors: { message: string; path: string[] }[] };
  export let formData: any = {};
  export let isUpdate = false;
  export let showCredentialFields = false;
  export let error: FormError | null = null;
  let isLoading = false;

  async function handleSubmit(event: Event) {
    event.preventDefault();
    isLoading = true;
    const inputModified = {
      ...formData,
      inboundIps: String(formData.inboundIps ?? '')
        .split(',')
        .map((s) => s.trim())
        .filter(Boolean),
    };

    try {
      const parsed = sipTrunkCreateSchema.parse(inputModified);
      const payload = {
        name: parsed.name,
        outboundUsername: showCredentialFields ? (parsed.outboundUsername ?? null) : null,
        outboundPassword: showCredentialFields ? (parsed.outboundPassword ?? null) : null,
        outboundContact: parsed.outboundContact,
        inboundIps: parsed.inboundIps,
      };

      const result = isUpdate
        ? await putJson(`/api/v2/${$page.params.subdomain}/sip-trunks/${formData.id}`, payload)
        : await postJson(`/api/v2/${$page.params.subdomain}/sip-trunks`, payload);

      if (!result.ok) {
        error = { message: result.error, formErrors: [] };
        isLoading = false;
        return;
      }

      error = null;
      await goto(`/app/${$page.params.subdomain}/sip-trunks`, { invalidateAll: true });
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

<form on:submit|preventDefault={handleSubmit}>
  <div class="mb-6">
    <div
      class="p-4 mb-4 text-sm text-blue-800 rounded-lg bg-blue-50 dark:bg-gray-800 dark:text-blue-400"
      role="alert"
    >
      <h5 class="text-lg">Settings</h5>
      <div>
        <span class="font-bold">Whitelist IP:</span>
        We send SIP request from IP address
        <span class="italic">34.194.225.59/32</span>
        . Please configure this IP in your SIP Trunk provider.
      </div>
      <div>
        <span class="font-bold">SIP Server:</span>
        Our sip server can be reached at
        <span class="italic">sip-server.example.com</span>
        (preferred) or at ip
        <span class="italic">34.194.225.59</span>
        . Please configure this in your SIP Trunk. provider.
      </div>
    </div>
    {#if error}
      <ErrorMessage {error} />
    {/if}
    <label for="name" class="block mb-2 text-sm font-medium text-gray-900 dark:text-white">
      Name
    </label>
    <input
      type="text"
      id="name"
      name="name"
      class="bg-gray-50 border border-gray-300 text-gray-900 text-sm rounded-lg focus:ring-blue-500 focus:border-blue-500 block w-full p-2.5 dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500"
      placeholder="Your Name"
      required
      bind:value={formData.name}
    />
  </div>
  <fieldset>
    <legend class="block mb-2 text-lg font-medium text-gray-900 dark:text-white">
      Outbound Configuration
    </legend>

    <div class="mb-6">
      <label for="showCredentialFields" class="flex items-center mb-4">
        <input
          type="checkbox"
          id="showCredentialFields"
          name="showCredentialFields"
          class="mr-2"
          bind:checked={showCredentialFields}
        />
        <span class="text-sm font-medium text-gray-900 dark:text-white">
          Provide Outbound Credentials
        </span>
      </label>
    </div>

    <!-- Conditional rendering of username and password fields -->
    {#if showCredentialFields}
      <div class="mb-6">
        <label
          for="outboundUsername"
          class="block mb-2 text-sm font-medium text-gray-900 dark:text-white"
        >
          Username
        </label>
        <input
          type="text"
          id="outboundUsername"
          name="outboundUsername"
          class="bg-gray-50 border border-gray-300 text-gray-900 text-sm rounded-lg focus:ring-blue-500 focus:border-blue-500 block w-full p-2.5 dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500"
          placeholder="your username"
          required
          bind:value={formData.outboundUsername}
        />
      </div>
      <div class="mb-6">
        <label
          for="outboundPassword"
          class="block mb-2 text-sm font-medium text-gray-900 dark:text-white"
        >
          Password
        </label>
        <input
          type="password"
          id="outboundPassword"
          name="outboundPassword"
          class="bg-gray-50 border border-gray-300 text-gray-900 text-sm rounded-lg focus:ring-blue-500 focus:border-blue-500 block w-full p-2.5 dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500"
          placeholder="Password"
          required
          bind:value={formData.outboundPassword}
        />
      </div>
    {/if}

    <div class="mb-6">
      <label
        for="outboundContact"
        class="block mb-2 text-sm font-medium text-gray-900 dark:text-white"
      >
        SIP Proxy Address
      </label>
      <input
        type="text"
        id="outboundContact"
        name="outboundContact"
        class="bg-gray-50 border border-gray-300 text-gray-900 text-sm rounded-lg focus:ring-blue-500 focus:border-blue-500 block w-full p-2.5 dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500"
        placeholder="provider.example.com"
        required
        bind:value={formData.outboundContact}
      />
    </div>
  </fieldset>
  <fieldset>
    <legend class="block mb-2 text-lg font-medium text-gray-900 dark:text-white">
      Inbound Configuration
    </legend>
    <div class="mb-6">
      <label for="inboundIps" class="block mb-2 text-sm font-medium text-gray-900 dark:text-white">
        Inbound IPs to whitelist (comma seperated IP/domain)
      </label>
      <!-- prettier-ignore -->
      <textarea
        id="inboundIps"
        name="inboundIps"
        class="bg-gray-50 border border-gray-300 text-gray-900 text-sm rounded-lg focus:ring-blue-500 focus:border-blue-500 block w-full p-2.5 dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500"
        placeholder="2.2.2.0/24"
        rows="4"
        required
      bind:value={formData.inboundIps}></textarea
      >
    </div>
  </fieldset>
  <button
    type="submit"
    disabled={isLoading}
    class="text-white bg-blue-700 hover:bg-blue-800 focus:ring-4 focus:outline-none focus:ring-blue-300 font-medium rounded-lg text-sm w-full sm:w-auto px-5 py-2.5 text-center dark:bg-blue-600 dark:hover:bg-blue-700 dark:focus:ring-blue-800"
  >
    {`${isUpdate ? 'Update' : 'Create'}`}
  </button>
</form>
