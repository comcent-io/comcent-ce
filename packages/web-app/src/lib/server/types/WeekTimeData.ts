import * as z from 'zod';
import { screenSchema } from './screenSchema.js';
const daySchema = z.object({
  include: z.boolean(),
  timeSlots: z.array(
    z.object({
      from: z.string().regex(/^([01]\d|2[0-3]):([0-5]\d)$/), // Matches HH:MM format (24-hour clock)
      to: z.string().regex(/^([01]\d|2[0-3]):([0-5]\d)$/),
    }),
  ),
});

export const weekTimeSchema = z.object({
  id: z.string(),
  type: z.literal('WeekTime'),
  data: z.object({
    timezone: z.string().default('UTC'),
    mon: daySchema,
    tue: daySchema,
    wed: daySchema,
    thu: daySchema,
    fri: daySchema,
    sat: daySchema,
    sun: daySchema,
  }),
  outlets: z.object({
    true: z.string().default(''),
    false: z.string().default(''),
  }),
  screen: screenSchema,
});

export type WeekTimeData = z.infer<typeof weekTimeSchema>;
