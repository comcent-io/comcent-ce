import * as z from 'zod';

export const roleSchema = z.enum(['MEMBER', 'ADMIN']);
export type Roles = z.infer<typeof roleSchema>;
