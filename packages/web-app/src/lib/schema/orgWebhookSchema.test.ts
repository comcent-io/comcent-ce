import { expect } from 'vitest';
import { orgWebhookSchema } from './orgWebhookSchema';

describe('orgWebhookSchema ', () => {
  it('should have webhookURL property with valid URL format', () => {
    const formData = {
      name: 'name',
      webhookURL: 'https://example.com',
      callUpdate: true,
      presenceUpdate: true,
    };
    let parsedData = orgWebhookSchema.safeParse(formData);
    expect(parsedData.success).toBe(true);

    formData.webhookURL = 'example.com';
    parsedData = orgWebhookSchema.safeParse(formData);
    expect(parsedData.success).toBe(false);

    formData.webhookURL = 'http://example.com:5000/api/efg';
    parsedData = orgWebhookSchema.safeParse(formData);
    expect(parsedData.success).toBe(true);

    formData.webhookURL = 'http://3.4.2.3:5000/api/efg';
    parsedData = orgWebhookSchema.safeParse(formData);
    expect(parsedData.success).toBe(true);

    formData.webhookURL = 'abc:/3.4.2.3:5000/api/efg';
    parsedData = orgWebhookSchema.safeParse(formData);
    expect(parsedData.success).toBe(false);

    formData.webhookURL = 'http:///3.4.2.3:5000/api/efg';
    parsedData = orgWebhookSchema.safeParse(formData);
    expect(parsedData.success).toBe(false);

    formData.webhookURL = 'http://3.4.2.3:5000/api/efg';
    parsedData = orgWebhookSchema.safeParse(formData);
    expect(parsedData.success).toBe(true);

    formData.webhookURL = 'https://3.4.2.3:5000/api/efg';
    parsedData = orgWebhookSchema.safeParse(formData);
    expect(parsedData.success).toBe(true);

    formData.webhookURL = 'http://167.172.20.64:8088/api/vcons';
    parsedData = orgWebhookSchema.safeParse(formData);
    expect(parsedData.success).toBe(true);
  });
});
