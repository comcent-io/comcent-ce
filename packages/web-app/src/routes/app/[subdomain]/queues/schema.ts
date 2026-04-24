import * as z from 'zod';

// Create the Zod validation schema
export const queueFormSchema = z.object({
  // Starts with letter, can have number, dot and underscore. No at symbol allowed and no spaces
  name: z
    .string()
    .min(3)
    .max(20)
    .regex(/^[A-Za-z][A-Za-z0-9_.]*$/),
  // the below regex accepts 2 to 5 digits
  extension: z
    .string()
    .regex(/^(\d{2,5})?$/)
    .optional(),
});
