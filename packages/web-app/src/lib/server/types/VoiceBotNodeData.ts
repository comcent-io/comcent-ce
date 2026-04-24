import * as z from 'zod';
import { screenSchema } from './screenSchema.js';
export const voiceBotNodeDataSchema = z.object({
  id: z.string(),
  type: z.literal('VoiceBot'),
  data: z.object({
    voiceBotId: z.string(),
  }),
  screen: screenSchema,
});

export type VoiceBotNodeData = z.infer<typeof voiceBotNodeDataSchema>;
