<script lang="ts">
  import FormSection from '$lib/components/form/FormSection.svelte';

  interface Props {
    totalPromisesCreated?: number;
    totalPromisesClosed?: number;
  }

  let { totalPromisesCreated = 0, totalPromisesClosed = 0 }: Props = $props();
</script>

<FormSection title="Promises" description="Follow-ups agents committed to.">
  <dl class="grid grid-cols-2 gap-4">
    <div>
      <dt class="text-sm text-gray-500 dark:text-gray-400">Made</dt>
      <dd class="mt-1 text-3xl font-bold text-gray-900 dark:text-white">
        {totalPromisesCreated}
      </dd>
    </div>
    <div>
      <dt class="text-sm text-gray-500 dark:text-gray-400">Closed</dt>
      <dd class="mt-1 text-3xl font-bold text-gray-900 dark:text-white">
        {totalPromisesClosed}
      </dd>
    </div>
  </dl>
</FormSection>
