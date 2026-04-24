export interface AuthSessionUser {
  sub: string;
  email: string;
  name: string;
  picture?: string;
  email_verified?: boolean;
  auth_provider?: string;
  token_type: string;
  exp: number;
  iat: number;
}
