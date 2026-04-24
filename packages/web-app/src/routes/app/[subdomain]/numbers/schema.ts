import * as z from 'zod';

const isE164orUs11 = (value: string) => {
  return /^\+[1-9]\d{1,14}$/.test(value) || /^1\d{10}$/.test(value);
};

// Create the Zod validation schema
export const numberFormSchema = z.object({
  id: z.string().optional(),
  name: z.string().min(3).max(100),
  number: z.string().refine(isE164orUs11, {
    message: 'Invalid E.164 phone number format or US 11-digit phone number format.',
  }),
  sipTrunkId: z.string().min(1), // You can adjust the min length as needed
  allowOutboundRegex: z.string().optional(), // You can adjust the min length as needed
  inboundFlowGraph: z.string().optional(), // You can adjust the min length as needed
});
export type numberData = z.infer<typeof numberFormSchema>;
