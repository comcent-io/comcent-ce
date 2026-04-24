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

    // test for IPV6 address
    it('should be valid IPV6 address', () => {
      formData.outboundContact = '2001:0db8:85a3:0000:0000:8a2e:0370:7334';
      let parsedData = sipTrunkCreateSchema.safeParse(formData);
      expect(parsedData.success).toBe(true);

      formData.outboundContact = '2001:db8:85a3::8a2e:370:7334';
      parsedData = sipTrunkCreateSchema.safeParse(formData);
      expect(parsedData.success).toBe(true);

      formData.outboundContact = '::1';
      parsedData = sipTrunkCreateSchema.safeParse(formData);
      expect(parsedData.success).toBe(true);

      formData.outboundContact = '2001:0db8:85a3:0000:0000:8a2e:0370:7334:1234';
      parsedData = sipTrunkCreateSchema.safeParse(formData);
      expect(parsedData.success).toBe(false);
    });

    it('should be valid IPV6 address with four digits in each group and every digit should be in hexadecimal format', () => {
      formData.outboundContact = '2001:0db8:85a3:0000:0000:8a2e:03700:7334';
      let parsedData = sipTrunkCreateSchema.safeParse(formData);
      expect(parsedData.success).toBe(false);

      formData.outboundContact = '2001:0db8:85g3:0000:0000:8a2e:0370:7334';
      parsedData = sipTrunkCreateSchema.safeParse(formData);
      expect(parsedData.success).toBe(false);
    });

    it('should be valid IPV6 address with : as a separator in between', () => {
      formData.outboundContact = '20010db885g3000000008a2e03707334';
      let parsedData = sipTrunkCreateSchema.safeParse(formData);
      expect(parsedData.success).toBe(false);

      formData.outboundContact = '2001:0db8-85a3:0000:0000:8a2e:0370:7334';
      parsedData = sipTrunkCreateSchema.safeParse(formData);
      expect(parsedData.success).toBe(false);

      formData.outboundContact = ':2001:0db8:85a3:0000:0000:8a2e:0370:7334';
      parsedData = sipTrunkCreateSchema.safeParse(formData);
      expect(parsedData.success).toBe(false);

      formData.outboundContact = '2001:0db8:85a3:0000:0000:8a2e:0370:7334:';
      parsedData = sipTrunkCreateSchema.safeParse(formData);
      expect(parsedData.success).toBe(false);
    });

    it('should be valid IPV6 address and valid IPV4 format if present', () => {
      formData.outboundContact = '::ffff:192.0.300.128';
      const parsedData = sipTrunkCreateSchema.safeParse(formData);
      expect(parsedData.success).toBe(false);
    });

    // test for domain name
    it('should be valid domain name not starting with sip: and should have atmost 63 characters in each part', () => {
      formData.outboundContact = 'example.com';
      let parsedData = sipTrunkCreateSchema.safeParse(formData);
      expect(parsedData.success).toBe(true);

      formData.outboundContact = 'sub-domain.example.org';
      parsedData = sipTrunkCreateSchema.safeParse(formData);
      expect(parsedData.success).toBe(true);

      formData.outboundContact = 'test.co.uk';
      parsedData = sipTrunkCreateSchema.safeParse(formData);
      expect(parsedData.success).toBe(true);

      formData.outboundContact = 'sip:example.com';
      parsedData = sipTrunkCreateSchema.safeParse(formData);
      expect(parsedData.success).toBe(false);

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
