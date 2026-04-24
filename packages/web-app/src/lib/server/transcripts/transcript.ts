import type { CallSpan, CallStory, CallTranscript } from '$lib/types/database';
import type { DeepgramResult } from '../types/DeepgramResult.js';
import { logger } from '../logger.js';
import { RecordingMetadata } from '../types/RecordingMetadata.js';
import moment from 'moment';

type Sentence = {
  currentParty: string;
  start: number;
  text: string;
};

type CallStoryWithTranscripts = CallStory & {
  callTranscripts: CallTranscript[];
  callSpans: CallSpan[];
};

function getSortedSentences(callStory: CallStoryWithTranscripts): Sentence[] {
  const sentences = [];
  for (const t of callStory.callTranscripts) {
    const data = t.transcriptData as DeepgramResult;
    const relatedCallSpan = callStory.callSpans.find((span) => {
      const metadata = span.metadata as any as RecordingMetadata;
      return (
        span.currentParty === t.currentParty &&
        span.type === 'RECORDING' &&
        metadata.direction === 'in'
      );
    });
    const startAt = relatedCallSpan?.startAt;
    const paragraphs = data.results.channels[0].alternatives[0]?.paragraphs?.paragraphs;
    if (!paragraphs) {
      logger.info(
        `No paragraphs found in transcript for call story ${t.callStoryId} recordingSpanId ${t.recordingSpanId}`,
      );
      continue;
    }
    for (const paragraph of paragraphs) {
      for (const sentence of paragraph.sentences) {
        sentences.push({
          currentParty: t.currentParty,
          timestamp: moment(startAt).add(sentence.start, 'seconds').unix(),
          ...sentence,
        });
      }
    }
  }
  return sentences.sort((a, b) => a.timestamp - b.timestamp);
}

type Chat = {
  currentParty: string;
  start: number;
  message: string;
};

export function createTranscriptChat(callStory: CallStoryWithTranscripts) {
  const sortedSentences = getSortedSentences(callStory);
  const transcriptMessages = [];
  let currentChat: Chat | null = {
    currentParty: sortedSentences?.[0]?.currentParty,
    start: sortedSentences?.[0]?.start,
    message: '',
  };
  for (const sentence of sortedSentences) {
    if (currentChat?.currentParty !== sentence.currentParty) {
      currentChat.message = currentChat.message.trim();
      transcriptMessages.push(currentChat);
      currentChat = {
        currentParty: sentence.currentParty,
        start: sentence.start,
        message: '',
      };
    }
    currentChat.message += ` ${sentence.text}`;
  }
  currentChat.message = currentChat.message.trim();
  if (currentChat?.message) {
    transcriptMessages.push(currentChat);
  }

  return transcriptMessages;
}
