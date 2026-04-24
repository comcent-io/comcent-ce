import { Presence } from './Presence.js';

export interface PresenceEvent {
  type: 'presence';
  data: {
    subdomain: string;
    userId: string;
    presence: Presence;
  };
}

export interface NewCallStoryEvent {
  type: 'NEW_CALL_STORY';
  data: {
    subdomain: string;
    callStoryId: string;
  };
}

export interface DeleteCallStoryEvent {
  type: 'DELETE_CALL_STORY';
  data: {
    subdomain: string;
    callStoryIds: string[];
    complianceTaskId: string;
  };
}

export interface DownloadCallStoryEvent {
  type: 'DOWNLOAD_CALL_STORY';
  data: {
    subdomain: string;
    callStoryIds: string[];
    complianceTaskId: string;
  };
}

export interface AnonymiseCallStoryEvent {
  type: 'ANONYMISE_CALL_STORY';
  data: {
    subdomain: string;
    callStoryIds: string[];
    complianceTaskId: string;
    customerNumber: string;
  };
}

export type ComcentEvent =
  | PresenceEvent
  | NewCallStoryEvent
  | DeleteCallStoryEvent
  | DownloadCallStoryEvent
  | AnonymiseCallStoryEvent;
