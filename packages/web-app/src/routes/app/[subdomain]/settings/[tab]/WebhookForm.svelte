<script lang="ts">
  import Button from '$lib/components/Button.svelte';
  import CheckboxRow from '$lib/components/form/CheckboxRow.svelte';
  import Field from '$lib/components/form/Field.svelte';
  import Input from '$lib/components/form/Input.svelte';
  import Label from '$lib/components/form/Label.svelte';

  type WebhookFormData = {
    name: string;
    webhookUrl: string;
    callUpdate: boolean;
    presenceUpdate: boolean;
  };

  let {
    formData = $bindable({
      name: '',
      webhookUrl: '',
      callUpdate: false,
      presenceUpdate: false,
    }),
    isProgress = false,
    buttonText = 'Create',
    onSubmit,
  }: {
    formData?: WebhookFormData;
    isProgress?: boolean;
    buttonText?: string;
    onSubmit?: (formData: WebhookFormData) => void;
  } = $props();
</script>

<form
  class="space-y-5"
  onsubmit={(e) => {
    e.preventDefault();
    onSubmit?.(formData);
  }}
>
  <Field for="webhookName" label="Name" hint="For you to tell your webhooks apart.">
    <Input
      type="text"
      id="webhookName"
      name="name"
      placeholder="Friendly name"
      required
      bind:value={formData.name}
    />
  </Field>

  <Field
    for="webhookUrl"
    label="URL"
    hint="Where we POST the events, e.g. https://example.com/comcent/webhook. Use https so the token travels encrypted."
  >
    <Input
      type="text"
      id="webhookUrl"
      name="webhookUrl"
      inputmode="url"
      autocomplete="off"
      placeholder="Webhook URL"
      required
      bind:value={formData.webhookUrl}
    />
  </Field>

  <fieldset>
    <Label tag="legend">Events</Label>
    <div class="space-y-2">
      <CheckboxRow
        id="callUpdate"
        label="Call update event"
        description="Sent when a call ends and its call story is ready: type NEW_CALL_STORY, with the call's details as data."
        bind:checked={formData.callUpdate}
      />
      <CheckboxRow
        id="presenceUpdate"
        label="Presence update event"
        description="Sent when a member's presence changes (e.g. Available to On Break): type PRESENCE_UPDATE, with the member and their previous and new presence as data."
        bind:checked={formData.presenceUpdate}
      />
    </div>
  </fieldset>

  <Button type="submit" progress={isProgress}>{buttonText}</Button>
</form>
