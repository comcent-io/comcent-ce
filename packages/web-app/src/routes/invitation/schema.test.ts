import { expect, test } from 'vitest';
import { invitationFormData } from './schema';

test('username in E.164 format is invalid', () => {
  const parseData = invitationFormData.safeParse({ username: '+1234567890' });
  expect(parseData.success).toBe(false);
});

test('username starting with @ symbol is invalid', () => {
  const parseData = invitationFormData.safeParse({ username: '@username' });
  expect(parseData.success).toBe(false);
});

test('username starting with number is invalid', () => {
  const parseData = invitationFormData.safeParse({ username: '123username' });
  expect(parseData.success).toBe(false);
});

test('username with space is invalid', () => {
  const parseData = invitationFormData.safeParse({ username: 'user name' });
  expect(parseData.success).toBe(false);
});

test('username with @ symbol is invalid', () => {
  const parseData = invitationFormData.safeParse({ username: 'user.name@domain.com' });
  expect(parseData.success).toBe(false);
});

test('username starting with space is invalid', () => {
  const parseData = invitationFormData.safeParse({ username: ' user' });
  expect(parseData.success).toBe(false);
});

test('username starting with plus sign is invalid', () => {
  const parseData = invitationFormData.safeParse({ username: '+user' });
  expect(parseData.success).toBe(false);
});

test('username starting with letter is valid', () => {
  const parseData = invitationFormData.safeParse({ username: 'username123' });
  expect(parseData.success).toBe(true);
});

test('username starting with letter and containing dot is valid', () => {
  const parseData = invitationFormData.safeParse({ username: 'user.name' });
  expect(parseData.success).toBe(true);
});

test('username starting with letter and containing underscore is valid', () => {
  const parseData = invitationFormData.safeParse({ username: 'user_name' });
  expect(parseData.success).toBe(true);
});

test('username starting with letter and containing plus sign but not in E.164 format is valid', () => {
  const parseData = invitationFormData.safeParse({ username: 'user+name' });
  expect(parseData.success).toBe(true);
});

test('username starting with letter and followed by numbers is valid', () => {
  const parseData = invitationFormData.safeParse({ username: 'a123456' });
  expect(parseData.success).toBe(true);
});

test('username starting with letter and mix of upper and lower case is valid', () => {
  const parseData = invitationFormData.safeParse({ username: 'UserName' });
  expect(parseData.success).toBe(true);
});
