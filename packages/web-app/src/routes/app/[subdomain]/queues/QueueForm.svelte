<script lang="ts">
  import { goto } from '$app/navigation';
  import { page } from '$app/state';
  import toast from '$lib/toast';
  import Button from '$lib/components/Button.svelte';
  import Field from '$lib/components/form/Field.svelte';
  import FormActions from '$lib/components/form/FormActions.svelte';
  import Input from '$lib/components/form/Input.svelte';

  interface Props {
    isUpdate?: boolean;
    queueId?: string;
    formData?: any;
  }

  let {
    isUpdate = false,
    queueId = '',
    formData = $bindable({
      name: '',
      extension: '',
      wrapUpTime: 30,
      rejectDelayTime: 30,
      maxNoAnswers: 2,
    }),
  }: Props = $props();

  const subdomain = page.params.subdomain;

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

<form method="POST" class="space-y-5" onsubmit={handleSubmit}>
  <Field
    for="name"
    label="Name"
    hint="Letters, numbers, dots and underscores, starting with a letter."
  >
    <Input
      type="text"
      id="name"
      name="name"
      placeholder="Queue Name (e.g. sales, service)"
      required
      bind:value={formData.name}
    />
  </Field>

  <Field
    for="extension"
    label="Extension"
    optional
    hint="2 to 5 digits, not used by another queue."
  >
    <Input
      type="text"
      id="extension"
      name="extension"
      inputmode="numeric"
      placeholder="Optional extension number"
      bind:value={formData.extension}
    />
  </Field>

  <Field
    for="wrapUpTime"
    label="Wrap-up time (seconds)"
    hint="After a queue call ends, how long an agent stays in Wrap Up before the next call is offered."
  >
    <Input
      type="number"
      id="wrapUpTime"
      name="wrapUpTime"
      min="0"
      placeholder="Wrap up time in seconds"
      bind:value={formData.wrapUpTime}
    />
  </Field>

  <Field
    for="rejectDelayTime"
    label="Reject delay (seconds)"
    hint="After an agent declines or misses a call, how long they're left Busy before calls are offered again."
  >
    <Input
      type="number"
      id="rejectDelayTime"
      name="rejectDelayTime"
      min="0"
      placeholder="Reject delay time in seconds"
      bind:value={formData.rejectDelayTime}
    />
  </Field>

  <Field
    for="maxNoAnswers"
    label="Missed calls before logout"
    hint="An agent who misses this many offered calls is logged out of the queue."
  >
    <Input
      type="number"
      id="maxNoAnswers"
      name="maxNoAnswers"
      min="0"
      placeholder="Max number of unanswered calls"
      bind:value={formData.maxNoAnswers}
    />
  </Field>

  <FormActions cancelHref={`/app/${subdomain}/queues`}>
    <Button type="submit">{isUpdate ? 'Update' : 'Add'}</Button>
  </FormActions>
</form>
