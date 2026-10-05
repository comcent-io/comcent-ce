import * as z from 'zod';
import { usernameSchema } from '$lib/schema/username';
// ^(?=.{1,255}$)(?!_)(?!.*_$)[A-Za-z0-9-_]+(\.[A-Za-z0-9-_]+)*\.?[A-Za-z0-9-]+$
const domainRegExp = /^(?=.{1,255}$)([A-Za-z][A-Za-z0-9-_]*)(\.[A-Za-z0-9-_]+)*\.?[A-Za-z0-9-]+$/;

const extensionNumberRegex = /^\d{3,5}$/;

// It becomes a host name, <subdomain>.<SIP domain>; the server checks the same.
export const subdomainRegExp = /^[a-z][a-z0-9-]*[a-z0-9]$/;

export const createOrgSchema = z
  .object({
    name: z.string().trim().min(3, 'Use at least 3 characters').max(60),
    subdomain: z
      .string()
      .min(3, 'Use at least 3 characters')
      .max(15, 'Use at most 15 characters')
      .regex(subdomainRegExp, 'Lowercase letters, numbers and hyphens, starting with a letter'),
    useCustomDomain: z.boolean().default(false),
    customDomain: z
      .string()
      .optional()
      .refine((value) => !value || domainRegExp.test(value), {
        message: 'Invalid domain format',
      }),
    // Regex for validating the username, starts with the letter can have number, dot, underscore and plus sign, no at symbol and space allowed
    sipUsername: usernameSchema,
    assignExtAutomatically: z.boolean().default(false),
    autoExtStart: z
      .string()
      .min(3)
      .max(5)
      .optional()
      .refine((value) => !value || extensionNumberRegex.test(value)),
    autoExtEnd: z
      .string()
      .min(3)
      .max(5)
      .optional()
      .refine((value) => !value || extensionNumberRegex.test(value)),
    userExt: z
      .string()
      .min(3)
      .max(5)
      .optional()
      .refine((value) => !value || extensionNumberRegex.test(value)),
  })
  .refine((data) => !data.useCustomDomain || data.customDomain, {
    message: 'Custom domain is required when useCustomDomain is true',
    path: ['customDomain'],
  })
  .refine((data) => !data.assignExtAutomatically || data.autoExtStart, {
    message: 'Auto extension start required when assignExtAutomatically is true',
    path: ['autoExtStart'],
  })
  .refine((data) => !data.assignExtAutomatically || data.autoExtEnd, {
    message: 'Auto extension end required when assignExtAutomatically is true',
    path: ['autoExtEnd'],
  });

export type CreateOrgSchema = z.infer<typeof createOrgSchema>;
