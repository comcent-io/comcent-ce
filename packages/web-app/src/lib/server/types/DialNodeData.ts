import * as z from 'zod';
import { screenSchema } from './screenSchema.js';
export const dialNodeDataSchema = z.object({
  id: z.string(),
  type: z.literal('Dial'),
  data: z.object({
    to: z.string().min(1),
    shouldSpoof: z.boolean().optional(),
    timeout: z.number().min(1).max(60).default(20),
  }),
  outlets: z.object({
    timeout: z.string().optional(),
  }),
  screen: screenSchema,
});

export type DialNodeData = z.infer<typeof dialNodeDataSchema>;
