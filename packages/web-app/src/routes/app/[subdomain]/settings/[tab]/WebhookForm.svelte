<script>
  import Button from '$lib/components/Button.svelte';
  import { createEventDispatcher } from 'svelte';

  const dispatch = createEventDispatcher();

  export let formData = {
    name: '',
    webhookUrl: '',
    callUpdate: false,
    presenceUpdate: false,
  };

  export let isProgress = false;

  export let buttonText = 'Create';
</script>

<form class="space-y-6" on:submit|preventDefault={() => dispatch('submit', formData)}>
  <div>
    <label for="name" class="block mb-2 text-sm font-medium text-gray-900 dark:text-white">
      Name
    </label>
    <input
      type="text"
      name="name"
      class="bg-gray-50 border border-gray-300 text-gray-900 text-sm rounded-lg focus:ring-blue-500 focus:border-blue-500 block w-full p-2.5 dark:bg-gray-600 dark:border-gray-500 dark:placeholder-gray-400 dark:text-white"
      placeholder="Friendly name"
      required
      bind:value={formData.name}
    />
  </div>
  <div>
    <label for="webhookUrl" class="block mb-2 text-sm font-medium text-gray-900 dark:text-white">
      URL
    </label>
    <input
      type="text"
      name="webhookUrl"
      class="bg-gray-50 border border-gray-300 text-gray-900 text-sm rounded-lg focus:ring-blue-500 focus:border-blue-500 block w-full p-2.5 dark:bg-gray-600 dark:border-gray-500 dark:placeholder-gray-400 dark:text-white"
      placeholder="Webhook URL"
      required
      bind:value={formData.webhookUrl}
    />
  </div>
  <div
    class="bg-gray-50 border border-gray-300 text-gray-900 text-sm rounded-lg focus:ring-blue-500 focus:border-blue-500 block w-full p-2.5 dark:bg-gray-600 dark:border-gray-500 dark:placeholder-gray-400 dark:text-white"
  >
    <div>
      <p class="text-white font-semibold pb-3">Choose events</p>
    </div>
    <div class="flex items-center mb-2">
      <label for="callUpdate" class="block text-sm font-medium text-gray-900 dark:text-white mr-2">
        Call Update Event
      </label>
      <input
        type="checkbox"
        id="callUpdate"
        name="callUpdate"
        class="w-4 h-4 text-blue-600 bg-green-100 border-gray-300 rounded focus:ring-blue-500 dark:focus:ring-blue-600 dark:ring-offset-blue-300 focus:ring-2 dark:bg-blue-300 dark:border-blue-300"
        bind:checked={formData.callUpdate}
      />
    </div>
    <div class="flex items-center">
      <label
        for="presenceUpdate"
        class="block text-sm font-medium text-gray-900 dark:text-white mr-2"
      >
        Presence Update Event
      </label>
      <input
        type="checkbox"
        id="presenceUpdate"
        name="presenceUpdate"
        class="w-4 h-4 text-blue-600 bg-green-100 border-gray-300 rounded focus:ring-blue-500 dark:focus:ring-blue-600 dark:ring-offset-blue-300 focus:ring-2 dark:bg-blue-300 dark:border-blue-300"
        bind:checked={formData.presenceUpdate}
      />
    </div>
  </div>
  <Button type="submit" progress={isProgress}>{buttonText}</Button>
</form>
