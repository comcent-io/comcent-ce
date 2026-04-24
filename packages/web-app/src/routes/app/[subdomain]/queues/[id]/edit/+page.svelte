<script lang="ts">
  import { onMount } from 'svelte';
  import QueueForm from '../../QueueForm.svelte';
  import QueueMember from '../../QueueMember.svelte';
  import { page } from '$app/stores';

  let data: any;
  let formData = {};

  onMount(async () => {
    try {
      const response = await fetch(`/api/v2/${$page.params.subdomain}/queues/${$page.params.id}`);
      if (!response.ok) throw new Error((await response.json()).error ?? response.statusText);
      const responseData = await response.json();
      data = responseData?.queueData;
      formData = data?.queue;
    } catch (error) {
      console.error(error);
    }
  });
</script>

<h3 class="text-3xl font-bold dark:text-white">Edit Queue</h3>

{#if data}
  <div class="mt-6 grid gap-6 xl:grid-cols-[minmax(0,24rem)_minmax(0,1fr)]">
    <div class="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm dark:border-slate-700 dark:bg-slate-900">
      <QueueForm {formData} queueId={data.queue.id} isUpdate={true} />
    </div>
    <QueueMember
      subdomain={data.subdomain}
      queueId={data.queueId}
      queueMembers={data.queueMembers}
    />
  </div>
{/if}
