<script lang="ts">
  import { goto } from '$app/navigation';
  import { page } from '$app/stores';
  import toast from 'svelte-french-toast';

  export let isUpdate = false;
  export let queueId = '';
  export let formData = {
    name: '',
    extension: '',
    wrapUpTime: 30,
    rejectDelayTime: 30,
    maxNoAnswers: 2,
  };

  const subdomain = $page.params.subdomain;

  async function handleSubmit(event: any) {
    event.preventDefault();
    try {
      if (isUpdate) {
        const response = await fetch(`/api/v2/${subdomain}/queues/${queueId}`, {
          method: 'PUT',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(formData),
        });
        if (!response.ok) {
          const data = await response.json();
          if (data.code === 'VALIDATION_ERROR' && data.details?.length) {
            throw new Error(`${data.details[0].field}: ${data.details[0].message}`);
          }
          throw new Error(data.error ?? response.statusText);
        }
        toast.success(`Queue updated successfully for org ${subdomain}`);
        goto(`/app/${subdomain}/queues`, { invalidateAll: true });
      } else {
        const response = await fetch(`/api/v2/${subdomain}/queues`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(formData),
        });
        if (!response.ok) {
          const data = await response.json();
          if (data.code === 'VALIDATION_ERROR' && data.details?.length) {
            throw new Error(`${data.details[0].field}: ${data.details[0].message}`);
          }
          throw new Error(data.error ?? response.statusText);
        }
        const {
          message,
          queue: { id },
        } = await response.json();

        toast.success(message);
        goto(`/app/${subdomain}/queues/${id}/edit`, { invalidateAll: true });
      }
    } catch (error: any) {
      toast.error(error.message);
    }
  }
</script>

<form method="POST" on:submit={handleSubmit}>
  <div class="mb-6">
    <label for="name" class="block mb-2 text-sm font-medium text-gray-900 dark:text-white">
      Name
    </label>
    <input
      type="text"
      id="name"
      name="name"
      class="bg-gray-50 border border-gray-300 text-gray-900 text-sm rounded-lg focus:ring-blue-500 focus:border-blue-500 block w-full p-2.5 dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500"
      placeholder="Queue Name (e.g. sales, service)"
      required
      bind:value={formData.name}
    />
  </div>
  <div class="mb-6">
    <label for="extension" class="block mb-2 text-sm font-medium text-gray-900 dark:text-white">
      Extension
    </label>
    <input
      type="text"
      id="extension"
      name="extension"
      class="bg-gray-50 border border-gray-300 text-gray-900 text-sm rounded-lg focus:ring-blue-500 focus:border-blue-500 block w-full p-2.5 dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500"
      placeholder="Optional extension number"
      bind:value={formData.extension}
    />
  </div>
  <div>
    <label for="wrapUpTime" class="block mb-2 text-sm font-medium text-gray-900 dark:text-white">
      Wrap Up Time
    </label>
    <input
      type="number"
      id="wrapUpTime"
      name="wrapUpTime"
      class="bg-gray-50 border border-gray-300 text-gray-900 text-sm rounded-lg focus:ring-blue-500 focus:border-blue-500 block w-full p-2.5 dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500"
      placeholder="Wrap up time in seconds"
      bind:value={formData.wrapUpTime}
    />
  </div>

  <div>
    <label
      for="rejectDelayTime"
      class="block mb-2 text-sm font-medium text-gray-900 dark:text-white"
    >
      Reject Delay Time
    </label>
    <input
      type="number"
      id="rejectDelayTime"
      name="rejectDelayTime"
      class="bg-gray-50 border border-gray-300 text-gray-900 text-sm rounded-lg focus:ring-blue-500 focus:border-blue-500 block w-full p-2.5 dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500"
      placeholder="Reject delay time in seconds"
      bind:value={formData.rejectDelayTime}
    />
  </div>

  <div>
    <label for="maxNoAnswers" class="block mb-2 text-sm font-medium text-gray-900 dark:text-white">
      Max No Answers
    </label>
    <input
      type="number"
      id="maxNoAnswers"
      name="maxNoAnswers"
      class="bg-gray-50 border border-gray-300 text-gray-900 text-sm rounded-lg focus:ring-blue-500 focus:border-blue-500 block w-full p-2.5 dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500"
      placeholder="Max number of unanswered calls"
      bind:value={formData.maxNoAnswers}
    />
  </div>

  <button
    type="submit"
    class="text-white bg-blue-700 mt-4 hover:bg-blue-800 focus:ring-4 focus:outline-none focus:ring-blue-300 font-medium rounded-lg text-sm w-full sm:w-auto px-5 py-2.5 text-center dark:bg-blue-600 dark:hover:bg-blue-700 dark:focus:ring-blue-800"
  >
    {`${isUpdate ? 'Update' : 'Add'}`}
  </button>
</form>
