import { z } from 'zod';

export const aiSettingsSchema = z.object({
  enableTranscription: z.boolean(),
  enableSentimentAnalysis: z.boolean(),
  enableSummary: z.boolean(),
});

export type AiSettingsSchemaType = z.infer<typeof aiSettingsSchema>;
