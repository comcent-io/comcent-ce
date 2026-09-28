// The Terms of Use and Privacy Policy as the session endpoint reports them.
// The server owns the decision: it is null when the deployment has no terms
// (TERMS_URL unset), and says whether this user has yet to accept the
// current version.
export type SessionTerms = {
  termsUrl: string;
  privacyUrl: string;
  version: string;
  acceptanceRequired: boolean;
  previouslyAccepted: boolean;
};

// The terms this user must accept before using the app, or null if none.
export function termsToAccept(terms: SessionTerms | null | undefined): SessionTerms | null {
  return terms?.acceptanceRequired ? terms : null;
}
