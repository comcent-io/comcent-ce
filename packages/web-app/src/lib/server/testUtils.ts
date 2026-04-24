export const isIntegrationEnv = process.env.INTEGRATION_ENV === 'true';

export const integrationDescribe = isIntegrationEnv ? describe : describe.skip;
export const unitDescribe = isIntegrationEnv ? describe.skip : describe;
