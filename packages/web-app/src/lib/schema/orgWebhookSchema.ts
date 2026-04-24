import { z } from 'zod';

export const orgWebhookSchema = z
  .object({
    webhookURL: z
      .string()
      .url('Invalid Webhook URL format')
      .regex(/^(http|https):\/\/[a-zA-Z0-9]/), // Validate URL format.
    callUpdate: z.boolean(),
    presenceUpdate: z.boolean(),
    name: z.string().min(3),
  })
  .refine((data) => data.callUpdate || data.presenceUpdate, {
    message: 'Please select at least one event',
    path: ['callUpdate', 'presenceUpdate'], // Optional: specify the path of the fields in the error object
  });

export type OrgWebhookType = z.infer<typeof orgWebhookSchema>;
