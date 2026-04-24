import * as z from 'zod';
import { screenSchema } from '$lib/types/screenSchema';
export const menuNodeDataSchema = z.object({
  id: z.string(),
  type: z.literal('Menu'),
  data: z.object({
    promptAudio: z.string().min(5),
    errorAudio: z.string().min(5),
    repeat: z.number().min(1).max(10).default(3),
    afterPromptWaitTime: z.number().min(1).max(10).default(5),
    multiDigitWaitTime: z.number().min(1).max(6).default(2),
  }),
  outlets: z.record(z.string().default('').optional()),
  screen: screenSchema,
});

export type MenuNodeData = z.infer<typeof menuNodeDataSchema>;
