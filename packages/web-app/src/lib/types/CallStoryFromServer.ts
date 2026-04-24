import type { CallSpan, CallStory } from '$lib/types/database';

export type CallStoryFromServer = CallStory & { callSpans: CallSpan[] } & {
  recordings: { recordUrl: string; uniqueId: string };
};
