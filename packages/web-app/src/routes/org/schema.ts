import * as z from 'zod';
import { usernameSchema } from '$lib/schema/username';
// ^(?=.{1,255}$)(?!_)(?!.*_$)[A-Za-z0-9-_]+(\.[A-Za-z0-9-_]+)*\.?[A-Za-z0-9-]+$
const domainRegExp = /^(?=.{1,255}$)([A-Za-z][A-Za-z0-9-_]*)(\.[A-Za-z0-9-_]+)*\.?[A-Za-z0-9-]+$/;

const extensionNumberRegex = /^\d{3,5}$/;

export const createOrgSchema = z
  .object({
    name: z.string().min(3).max(60),
    subdomain: z.string().min(3).max(15),
    useCustomDomain: z.boolean().default(false),
    customDomain: z
      .string()
      .optional()
      .refine((value) => !value || domainRegExp.test(value), {
        message: 'Invalid domain format',
      }),
    // Regex for validating the username, starts with the letter can have number, dot, underscore and plus sign, no at symbol and space allowed
    sipUsername: usernameSchema,
    // Billing-address fields are EE-only. In CE they're sent as empty
    // strings; server skips OrgBillingAddress insert when blank.
    country: z.string().default(''),
    state: z.string().default(''),
    zip: z.string().default(''),
    userName: z.string().default(''),
    city: z.string().default(''),
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
  .refine((data) => !data.assignExtAutomatically || data.autoExtStart, {
    message: 'Auto extension end required when assignExtAutomatically is true',
    path: ['autoExtEnd'],
  });

export type CreateOrgSchema = z.infer<typeof createOrgSchema>;
