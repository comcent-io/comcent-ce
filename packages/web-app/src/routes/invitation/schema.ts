import * as z from 'zod';
import { usernameSchema } from '$lib/schema/username';

export const invitationFormData = z.object({
  username: usernameSchema,
});
