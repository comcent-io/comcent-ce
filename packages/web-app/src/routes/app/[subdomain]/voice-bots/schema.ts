import * as z from 'zod';

export const voiceBotSchema = z.object({
  id: z.string(),
  name: z.string().min(3),
  instructions: z.string().min(3),
  notToDoInstructions: z.string().min(3),
  greetingInstructions: z.string().min(3),
  mcpServers: z.array(
    z.object({
      url: z.string(),
      token: z.string(),
    }),
  ),
  isHangup: z.boolean(),
  isEnqueue: z.boolean(),
  queues: z.array(z.string()),
  pipeline: z.enum(['DEEPGRAM_AND_OPENAI', 'REALTIME_API']),
});

export type voiceBotData = z.infer<typeof voiceBotSchema>;
