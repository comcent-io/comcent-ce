import * as z from 'zod';
import { screenSchema } from '$lib/types/screenSchema';

export const voiceBotNodeDataSchema = z.object({
  id: z.string(),
  type: z.literal('VoiceBot'),
  data: z.object({
    voiceBotName: z.string().min(1),
    voiceBotId: z.string().min(1),
  }),
  screen: screenSchema,
});

export type VoiceBotNodeData = z.infer<typeof voiceBotNodeDataSchema>;
