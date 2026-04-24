import * as z from 'zod';

const usernameRegex = /^[a-zA-Z][a-zA-Z0-9._+]*$/;
export const usernameSchema = z.string().min(3).max(20).regex(usernameRegex);
