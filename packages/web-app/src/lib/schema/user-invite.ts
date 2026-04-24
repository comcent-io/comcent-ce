import { z } from 'zod';

export const inviteValidationSchema = z.object({
  email: z.string().email('Invalid email address').max(255),
  role: z.enum(['MEMBER', 'ADMIN']),
});
