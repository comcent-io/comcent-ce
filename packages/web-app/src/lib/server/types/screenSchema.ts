import * as z from 'zod';

export const screenSchema = z
  .object({
    tx: z.number(),
    ty: z.number(),
  })
  .optional();
