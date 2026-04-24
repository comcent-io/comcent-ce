import * as z from 'zod';
import { screenSchema } from './screenSchema.js';
export const dialGroupNodeDataSchema = z.object({
  id: z.string(),
  type: z.literal('DialGroup'),
  data: z.object({
    to: z.array(z.string().min(1)),
    shouldSpoof: z.boolean().optional(),
    timeout: z.number().min(1).max(60).default(20),
  }),
  outlets: z.object({
    timeout: z.string().optional(),
  }),
  screen: screenSchema,
});

export type DialGroupNodeData = z.infer<typeof dialGroupNodeDataSchema>;
