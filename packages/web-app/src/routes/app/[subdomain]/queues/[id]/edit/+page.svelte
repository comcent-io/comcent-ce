<script lang="ts">
  import { onMount } from 'svelte';
  import QueueForm from '../../QueueForm.svelte';
  import QueueMember from '../../QueueMember.svelte';
  import { page } from '$app/state';
  import Card from '$lib/components/Card.svelte';
  import PageHeader from '$lib/components/form/PageHeader.svelte';

  let data: any = $state();
  let formData = $state({});

  onMount(async () => {
    try {
      const response = await fetch(`/api/v2/${page.params.subdomain}/queues/${page.params.id}`);
      if (!response.ok) throw new Error((await response.json()).error ?? response.statusText);
      const responseData = await response.json();
      data = responseData?.queueData;
      formData = data?.queue;
    } catch (error) {
      console.error(error);
    }
  });
</script>

<PageHeader
  title="Edit queue"
  description="How long agents rest between calls, and who takes this queue's calls."
  backHref={`/app/${page.params.subdomain}/queues`}
  backLabel="Queues"
/>

{#if data}
  <div class="grid gap-6 xl:grid-cols-[minmax(0,24rem)_minmax(0,1fr)]">
    <Card>
      <QueueForm {formData} queueId={data.queue.id} isUpdate={true} />
    </Card>
    <QueueMember
      subdomain={data.subdomain}
      queueId={data.queueId}
      queueMembers={data.queueMembers}
    />
  </div>
{/if}
