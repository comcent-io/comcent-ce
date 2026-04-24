import * as z from 'zod';
import { screenSchema } from './screenSchema.js';
export const queueNodeDataSchema = z.object({
  id: z.string(),
  type: z.literal('Queue'),
  data: z.object({
    queue: z.string().min(1),
  }),
  screen: screenSchema,
});

export type QueueNodeData = z.infer<typeof queueNodeDataSchema>;
