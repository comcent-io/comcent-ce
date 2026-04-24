import jsonwebtoken from 'jsonwebtoken';
import type { AuthSessionUser } from './types/AuthSessionUser.js';

const { SIGNING_KEY } = process.env;

export async function verifyToken(token: string): Promise<AuthSessionUser | undefined> {
  try {
    const decoded = jsonwebtoken.verify(token, SIGNING_KEY!) as AuthSessionUser;

    if (decoded.token_type !== 'session') {
      return undefined;
    }

    return decoded;
  } catch {
    return undefined;
  }
}
