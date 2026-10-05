<script>
  import { page } from '$app/state';
  import Card from '$lib/components/Card.svelte';
  import PageHeader from '$lib/components/form/PageHeader.svelte';
  import QueueForm from '../QueueForm.svelte';
</script>

<PageHeader
  title="Add queue"
  description="Callers wait in a queue and are offered, in turn, to its members who are available."
  backHref={`/app/${page.params.subdomain}/queues`}
  backLabel="Queues"
/>

<Card className="max-w-xl">
  <QueueForm />
  <p
    class="mt-6 border-t border-gray-200 pt-4 text-xs text-gray-500 dark:border-gray-700 dark:text-gray-400"
  >
    You add members once the queue is created.
  </p>
</Card>
