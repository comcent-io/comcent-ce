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
    country: z.string().min(2),
    state: z.string().min(2),
    zip: z.string().min(2),
    userName: z.string().min(2), // TODO: do we need it if dont have stripe now
    city: z.string().min(2),
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
