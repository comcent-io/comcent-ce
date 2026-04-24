import type { CallSpan, CallStory, Org, OrgWebhook } from '$lib/types/database';

export type CallStoryAssociation = CallStory & {
  org: Org & { webhooks: OrgWebhook[] };
  callSpans: CallSpan[];
};
