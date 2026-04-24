import * as z from 'zod';
import { screenSchema } from '$lib/types/screenSchema';
export const playNodeDataSchema = z.object({
  id: z.string(),
  type: z.literal('Play'),
  data: z.object({
    media: z.string().min(1),
  }),
  screen: screenSchema,
});

export type PlayNodeData = z.infer<typeof playNodeDataSchema>;
