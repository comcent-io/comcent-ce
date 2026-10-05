import * as z from 'zod';

const usernameRegex = /^[a-zA-Z][a-zA-Z0-9._+]*$/;

// Said wherever a username is asked for (creating an org, accepting an
// invitation), so the rule reads the same.
export const USERNAME_RULE =
  '3 to 20 letters, numbers, dots, underscores or plus signs, starting with a letter';

export const usernameSchema = z
  .string()
  .min(3, USERNAME_RULE)
  .max(20, USERNAME_RULE)
  .regex(usernameRegex, USERNAME_RULE);
