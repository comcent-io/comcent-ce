import { expect } from 'vitest';
import { sipTrunkCreateSchema } from './schema';

describe('sipTrunkCreateSchema ', () => {
  let formData: any;

  beforeEach(() => {
    formData = {
      name: 'name',
      outboundUsername: 'username12',
      outboundPassword: 'password143',
      outboundContact: '23.2.21.5',
      inboundIps: ['2.25.36.1/24', '56.35.75.32/22'],
    };
  });

  // test for name
  it('should have name property length between 3 and 25 characters', () => {
    let parsedData = sipTrunkCreateSchema.safeParse(formData);
    expect(parsedData.success).toBe(true);

    formData.name = 'na';
    parsedData = sipTrunkCreateSchema.safeParse(formData);
    expect(parsedData.success).toBe(false);

    formData.name = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    parsedData = sipTrunkCreateSchema.safeParse(formData);
    expect(parsedData.success).toBe(false);
  });

  // test for outboundUsername
  it('should have outboundUsername which starts with alphabet then can have alphanumeric, dot or underscore', () => {
    let parsedData = sipTrunkCreateSchema.safeParse(formData);
    expect(parsedData.success).toBe(true);

    formData.outboundUsername = 13;
    parsedData = sipTrunkCreateSchema.safeParse(formData);
    expect(parsedData.success).toBe(false);
  });

  // test for outboundPassword
  it('should have outboundPassword which starts with alphabet then can have alphanumeric, dot or underscore', () => {
    let parsedData = sipTrunkCreateSchema.safeParse(formData);
    expect(parsedData.success).toBe(true);

    formData.outboundUsername = 53;
    parsedData = sipTrunkCreateSchema.safeParse(formData);
    expect(parsedData.success).toBe(false);
  });

  // test for outboundContact
  describe('outboundContact', () => {
    // test for IPV4 address
    it('should be valid IPV4 address', () => {
      let parsedData = sipTrunkCreateSchema.safeParse(formData);
      expect(parsedData.success).toBe(true);

      formData.outboundContact = '265.1.0.5';
      parsedData = sipTrunkCreateSchema.safeParse(formData);
      expect(parsedData.success).toBe(false);

      formData.outboundContact = '1.0.5';
      parsedData = sipTrunkCreateSchema.safeParse(formData);
      expect(parsedData.success).toBe(false);
    });

    const parseContact = (value: string) =>
      sipTrunkCreateSchema.safeParse({ ...formData, outboundContact: value });

    it.each([
      ['sip.example.com', 'sip.example.com'],
      ['sip.example.com:5080', 'sip.example.com:5080'],
      ['sip:sip.example.com', 'sip.example.com'],
      ['sip:sip.example.com:5080', 'sip.example.com:5080'],
      ['SIP:sip.example.com:5080', 'sip.example.com:5080'],
      ['www.something.com', 'www.something.com'],
      ['203.0.113.10', '203.0.113.10'],
      ['203.0.113.10:5060', '203.0.113.10:5060'],
      ['sip:203.0.113.10:5080', '203.0.113.10:5080'],
      ['sipp-uas:6351', 'sipp-uas:6351'],
      ['  sip:sip.example.com:5080 ', 'sip.example.com:5080'],
      ['sip.example.com:05080', 'sip.example.com:5080'],
    ])('accepts %j and stores it as %j', (input, stored) => {
      const parsed = parseContact(input);
      expect(parsed.success).toBe(true);
      expect(parsed.success && parsed.data.outboundContact).toBe(stored);
    });

    it.each([
      '',
      '   ',
      'sip.example .com',
      'sip:',
      ':5080',
      'sip:sip:sip.example.com',
      'http://sip.example.com',
      'http:sip.example.com',
      'sip.example.com:0',
      'sip.example.com:65536',
      'sip.example.com:abc',
      'sip.example.com:',
      '2001:db8::1',
      '[2001:db8::1]:5060',
      '::1',
      'sip:sip.example.com:5060:5061',
    ])('rejects %j with the accepted forms in the message', (input) => {
      const parsed = parseContact(input);
      expect(parsed.success).toBe(false);
      expect(!parsed.success && parsed.error.issues[0].message).toContain('sip:host:port');
    });

    it('explains why sips:, URI parameters and a user part are rejected', () => {
      const message = (value: string) => {
        const parsed = parseContact(value);
        return parsed.success ? '' : parsed.error.issues[0].message;
      };

      expect(message('sips:sip.example.com:5061')).toContain('TLS');
      expect(message('sip:sip.example.com;transport=tcp')).toContain(';transport=tcp');
      expect(message('sip:trunk@sip.example.com')).toContain('user@');
      expect(message('http://sip.example.com')).toContain('Only the sip: scheme');
    });

    // test for domain name
    it('should be valid domain name and should have atmost 63 characters in each part', () => {
      formData.outboundContact = 'example.com';
      let parsedData = sipTrunkCreateSchema.safeParse(formData);
      expect(parsedData.success).toBe(true);

      formData.outboundContact = 'sub-domain.example.org';
      parsedData = sipTrunkCreateSchema.safeParse(formData);
      expect(parsedData.success).toBe(true);

      formData.outboundContact = 'test.co.uk';
      parsedData = sipTrunkCreateSchema.safeParse(formData);
      expect(parsedData.success).toBe(true);

      formData.outboundContact =
        '12345678901234567890123456789012345678901234567890123456789012345678901234.com';
      parsedData = sipTrunkCreateSchema.safeParse(formData);
      expect(parsedData.success).toBe(false);
    });

    it('should be valid domain name containing . and - are valid with single . as a separator and should start or end with only letters', () => {
      formData.outboundContact = '-example.com';
      let parsedData = sipTrunkCreateSchema.safeParse(formData);
      expect(parsedData.success).toBe(false);

      formData.outboundContact = 'example-.com';
      parsedData = sipTrunkCreateSchema.safeParse(formData);
      expect(parsedData.success).toBe(false);

      formData.outboundContact = 'example..com';
      parsedData = sipTrunkCreateSchema.safeParse(formData);
      expect(parsedData.success).toBe(false);

      formData.outboundContact = 'exa!mple.com';
      parsedData = sipTrunkCreateSchema.safeParse(formData);
      expect(parsedData.success).toBe(false);
    });
  });

  // test for inboundIps
  it('should have inboundIps with valid IPV4 address in CIDR format and should contain only single / for CIDR notation', () => {
    let parsedData = sipTrunkCreateSchema.safeParse(formData);
    expect(parsedData.success).toBe(true);

    formData.inboundIps = ['255.255.255.255/32'];
    parsedData = sipTrunkCreateSchema.safeParse(formData);
    expect(parsedData.success).toBe(true);

    formData.inboundIps = ['0.0.0.0/0'];
    parsedData = sipTrunkCreateSchema.safeParse(formData);
    expect(parsedData.success).toBe(true);

    formData.inboundIps = ['267.25.36.1/24', '56.35.75.32/42'];
    parsedData = sipTrunkCreateSchema.safeParse(formData);
    expect(parsedData.success).toBe(false);

    formData.inboundIps = ['27.25.36.1/24', '56.35.75.32/42'];
    parsedData = sipTrunkCreateSchema.safeParse(formData);
    expect(parsedData.success).toBe(false);

    formData.inboundIps = ['267.25.36.1/24'];
    parsedData = sipTrunkCreateSchema.safeParse(formData);
    expect(parsedData.success).toBe(false);

    formData.inboundIps = ['67.25.36.1'];
    parsedData = sipTrunkCreateSchema.safeParse(formData);
    expect(parsedData.success).toBe(false);

    formData.inboundIps = ['67.25.36.1/43'];
    parsedData = sipTrunkCreateSchema.safeParse(formData);
    expect(parsedData.success).toBe(false);

    formData.inboundIps = ['67.25.36/43'];
    parsedData = sipTrunkCreateSchema.safeParse(formData);
    expect(parsedData.success).toBe(false);

    formData.inboundIps = ['67.25.36.2//43'];
    parsedData = sipTrunkCreateSchema.safeParse(formData);
    expect(parsedData.success).toBe(false);

    formData.inboundIps = ['ABCD:EF01:2345:6789:ABCD:EF01:2345:6789/24'];
    parsedData = sipTrunkCreateSchema.safeParse(formData);
    expect(parsedData.success).toBe(false);
  });
});
