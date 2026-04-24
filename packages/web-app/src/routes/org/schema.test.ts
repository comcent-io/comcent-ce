import { expect } from 'vitest';
import { createOrgSchema } from './schema';

describe('createOrgSchema', () => {
  let formData: any;

  beforeEach(() => {
    formData = {
      name: 'aiet',
      subdomain: 'aiet',
      useCustomDomain: false,
      sipUsername: 'username',
      country: 'US',
      state: 'CA',
      zip: '12345',
      userExt: '1342',
      userName: 'abcdefg',
      city: 'San Francisco',
      assignExtAutomatically: false,
    };
  });
  // test for name
  it('should have name property length between 3 and 60', () => {
    let parsedData = createOrgSchema.safeParse(formData);
    expect(parsedData.success).toBe(true);

    formData.name = 'na';
    parsedData = createOrgSchema.safeParse(formData);
    expect(parsedData.success).toBe(false);

    formData.name = 'ThisIsALongStringExampleThatCertainlyExceedsSixtyCharactersInLength';
    parsedData = createOrgSchema.safeParse(formData);
    expect(parsedData.success).toBe(false);
  });

  // test for subdomain
  it('should have subdomain property length between 3 and 15', () => {
    let parsedData = createOrgSchema.safeParse(formData);
    expect(parsedData.success).toBe(true);

    formData.subdomain = 'ai';
    parsedData = createOrgSchema.safeParse(formData);
    expect(parsedData.success).toBe(false);

    formData.subdomain = 'LongStringExample';
    parsedData = createOrgSchema.safeParse(formData);
    expect(parsedData.success).toBe(false);
  });

  // test for useCustomDomain
  it('should have useCustomDomain property with boolean value', () => {
    let parsedData = createOrgSchema.safeParse(formData);
    expect(parsedData.success).toBe(true);
    expect((parsedData as any).data.useCustomDomain).toBe(false);

    formData.useCustomDomain = false;
    parsedData = createOrgSchema.safeParse(formData);
    expect(parsedData.success).toBe(true);
    expect((parsedData as any).data.useCustomDomain).toBe(false);

    formData.useCustomDomain = true;
    formData.customDomain = 'Example.com';
    parsedData = createOrgSchema.safeParse(formData);
    expect(parsedData.success).toBe(true);
    expect((parsedData as any).data.useCustomDomain).toBe(true);

    formData.useCustomDomain = 'not boolean';
    parsedData = createOrgSchema.safeParse(formData);
    expect(parsedData.success).toBe(false);
  });

  // test for customDomain
  it('should have customDomain with alpha numeric characters with single period, underscores and hiphens, should start with letters and should contain less than 255 characters', () => {
    formData.customDomain = 'example.com';
    let parsedData = createOrgSchema.safeParse(formData);
    expect(parsedData.success).toBe(true);

    formData.customDomain = '12345';
    parsedData = createOrgSchema.safeParse(formData);
    expect(parsedData.success).toBe(false);

    formData.customDomain = 'a.b-c_d.e-f';
    parsedData = createOrgSchema.safeParse(formData);
    expect(parsedData.success).toBe(true);

    formData.customDomain =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ01';
    parsedData = createOrgSchema.safeParse(formData);
    expect(parsedData.success).toBe(false);

    formData.customDomain = 'ExampleDomain..com';
    parsedData = createOrgSchema.safeParse(formData);
    expect(parsedData.success).toBe(false);

    formData.customDomain = '..ExampleDomain';
    parsedData = createOrgSchema.safeParse(formData);
    expect(parsedData.success).toBe(false);

    formData.customDomain = 'ExampleDomain.com_';
    parsedData = createOrgSchema.safeParse(formData);
    expect(parsedData.success).toBe(false);

    formData.customDomain = '_ExampleDomain.com';
    parsedData = createOrgSchema.safeParse(formData);
    expect(parsedData.success).toBe(false);
  });

  // test for sipUsername
  it('should have sipUsername starting with letter and can contain period, underscore, plus sign but not in E.164 format', () => {
    let parsedData = createOrgSchema.safeParse(formData);
    expect(parsedData.success).toBe(true);

    formData.sipUsername = 'a123456';
    parsedData = createOrgSchema.safeParse(formData);
    expect(parsedData.success).toBe(true);

    formData.sipUsername = 'user+name';
    parsedData = createOrgSchema.safeParse(formData);
    expect(parsedData.success).toBe(true);

    formData.sipUsername = 'user_name';
    parsedData = createOrgSchema.safeParse(formData);
    expect(parsedData.success).toBe(true);

    formData.sipUsername = 'user.name';
    parsedData = createOrgSchema.safeParse(formData);
    expect(parsedData.success).toBe(true);

    formData.sipUsername = 'username123';
    parsedData = createOrgSchema.safeParse(formData);
    expect(parsedData.success).toBe(true);

    formData.sipUsername = '+user';
    parsedData = createOrgSchema.safeParse(formData);
    expect(parsedData.success).toBe(false);

    formData.sipUsername = ' user';
    parsedData = createOrgSchema.safeParse(formData);
    expect(parsedData.success).toBe(false);

    formData.sipUsername = 'username@domain.com';
    parsedData = createOrgSchema.safeParse(formData);
    expect(parsedData.success).toBe(false);

    formData.sipUsername = 'user name';
    parsedData = createOrgSchema.safeParse(formData);
    expect(parsedData.success).toBe(false);

    formData.sipUsername = '123username';
    parsedData = createOrgSchema.safeParse(formData);
    expect(parsedData.success).toBe(false);

    formData.sipUsername = '@username';
    parsedData = createOrgSchema.safeParse(formData);
    expect(parsedData.success).toBe(false);

    formData.sipUsername = '+919611828660';
    parsedData = createOrgSchema.safeParse(formData);
    expect(parsedData.success).toBe(false);
  });

  // test for assignExtAutomatically
  it('should have assignExtAutomatically property with boolean value', () => {
    let parsedData = createOrgSchema.safeParse(formData);
    expect(parsedData.success).toBe(true);
    expect((parsedData as any).data.assignExtAutomatically).toBe(false);

    formData.assignExtAutomatically = false;
    parsedData = createOrgSchema.safeParse(formData);
    expect(parsedData.success).toBe(true);
    expect((parsedData as any).data.assignExtAutomatically).toBe(false);

    formData.assignExtAutomatically = true;
    formData.autoExtStart = '1002';
    formData.autoExtEnd = '1003';
    parsedData = createOrgSchema.safeParse(formData);
    expect(parsedData.success).toBe(true);
    expect((parsedData as any).data.assignExtAutomatically).toBe(true);

    formData.assignExtAutomatically = 'non boolean';
    parsedData = createOrgSchema.safeParse(formData);
    expect(parsedData.success).toBe(false);
  });

  // test for autoExtStart
  it('should have autoExtStart property with 3 to 5 digits', () => {
    formData.autoExtStart = '1243';
    let parsedData = createOrgSchema.safeParse(formData);
    expect(parsedData.success).toBe(true);

    formData.autoExtStart = '12';
    parsedData = createOrgSchema.safeParse(formData);
    expect(parsedData.success).toBe(false);

    formData.autoExtStart = '123456';
    parsedData = createOrgSchema.safeParse(formData);
    expect(parsedData.success).toBe(false);

    formData.autoExtStart = 'abc';
    parsedData = createOrgSchema.safeParse(formData);
    expect(parsedData.success).toBe(false);
  });

  // test for autoExtEnd
  it('should have autoExtEnd property with 3 to 5 digits', () => {
    formData.autoExtEnd = '1243';
    let parsedData = createOrgSchema.safeParse(formData);
    expect(parsedData.success).toBe(true);

    formData.autoExtEnd = '12';
    parsedData = createOrgSchema.safeParse(formData);
    expect(parsedData.success).toBe(false);

    formData.autoExtEnd = '123456';
    parsedData = createOrgSchema.safeParse(formData);
    expect(parsedData.success).toBe(false);

    formData.autoExtEnd = 'abc';
    parsedData = createOrgSchema.safeParse(formData);
    expect(parsedData.success).toBe(false);
  });

  // test for userExt
  it('should have userExt property with 3 to 5 digits', () => {
    let parsedData = createOrgSchema.safeParse(formData);
    expect(parsedData.success).toBe(true);

    formData.userExt = '12';
    parsedData = createOrgSchema.safeParse(formData);
    expect(parsedData.success).toBe(false);

    formData.userExt = '123456';
    parsedData = createOrgSchema.safeParse(formData);
    expect(parsedData.success).toBe(false);

    formData.userExt = 'abc';
    parsedData = createOrgSchema.safeParse(formData);
    expect(parsedData.success).toBe(false);
  });
});
