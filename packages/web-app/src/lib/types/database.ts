export type JsonValue =
  | string
  | number
  | boolean
  | null
  | { [key: string]: JsonValue }
  | JsonValue[];

export interface OrgWebhook {
  id: string;
  orgId: string;
  name: string;
  webhookURL: string;
  events: string[];
}

export interface Org {
  id: string;
  name: string;
  subdomain: string;
}

export interface CallSpan {
  id: string;
  callStoryId: string;
  currentParty: string;
  type: string;
  metadata: JsonValue;
  startAt: string | Date;
  endAt?: string | Date | null;
}

export interface CallTranscript {
  id: string;
  callStoryId: string;
  recordingSpanId: string;
  currentParty: string;
  transcriptData: JsonValue;
}

export interface CallStory {
  id: string;
  orgId: string;
  customerNumber?: string | null;
}
