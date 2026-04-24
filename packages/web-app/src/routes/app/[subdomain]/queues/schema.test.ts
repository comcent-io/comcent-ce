import { expect, test } from 'vitest';
import { queueFormSchema } from './schema';

// tests for queue name
// In the below tests when we are testing for name, we can ignore the extension field as it is optional
test('queue name starts with number so invalid', () => {
  const parseData = queueFormSchema.safeParse({ name: '1Queue' });
  expect(parseData.success).toBe(false);
});

test('queue name contains character - so invalid', () => {
  const parseData = queueFormSchema.safeParse({ name: 'Queue-1' });
  expect(parseData.success).toBe(false);
});

test('queue name contains character # so invalid', () => {
  const parseData = queueFormSchema.safeParse({ name: 'Queue#' });
  expect(parseData.success).toBe(false);
});

test('queue name contains @ symbol so invalid', () => {
  const parseData = queueFormSchema.safeParse({ name: 'Queue@Name' });
  expect(parseData.success).toBe(false);
});

test('queue name contains space so invalid', () => {
  const parseData = queueFormSchema.safeParse({ name: 'My Queue' });
  expect(parseData.success).toBe(false);
});

test('queue name is in E.164 format so invalid', () => {
  const parseData = queueFormSchema.safeParse({ name: '+1234567890' });
  expect(parseData.success).toBe(false);
});

test('queue name starts with letter so valid', () => {
  const parseData = queueFormSchema.safeParse({ name: 'Queue1' });
  expect(parseData.success).toBe(true);
});

test('should pass for valid queue name Queue_1.abc', () => {
  const parseData = queueFormSchema.safeParse({ name: 'Queue_1.abc' });
  expect(parseData.success).toBe(true);
});

test('queue name length is between 3 and 20 so valid', () => {
  const validparseData = queueFormSchema.safeParse({ name: 'Queue132' });
  expect(validparseData.success).toBe(true);

  const invalidparseDataWithShortName = queueFormSchema.safeParse({ name: 'qu' });
  expect(invalidparseDataWithShortName.success).toBe(false);

  const invalidparseDataWithLongName = queueFormSchema.safeParse({ name: 'queue12345678910queue' });
  expect(invalidparseDataWithLongName.success).toBe(false);
});

// tests for extension name
// In the below code name is also taken because name is required its not optional
test('extension name is valid E.164 format so invalid', () => {
  const parseData = queueFormSchema.safeParse({ name: 'QueueName', extension: '+91' });
  expect(parseData.success).toBe(false);
});

test('extension name contains characters other than digits so invalid', () => {
  const parseData = queueFormSchema.safeParse({ name: 'QueueName', extension: 'abc@_' });
  expect(parseData.success).toBe(false);
});

test('extension name length is between 2 and 5 so valid', () => {
  const validparseData = queueFormSchema.safeParse({ name: 'QueueName', extension: '100' });
  expect(validparseData.success).toBe(true);

  const invalidparseDataWithShortName = queueFormSchema.safeParse({
    name: 'QueueName',
    extension: '1',
  });
  expect(invalidparseDataWithShortName.success).toBe(false);

  const invalidparseDataWithLongName = queueFormSchema.safeParse({
    name: 'QueueName',
    extension: '1233456',
  });
  expect(invalidparseDataWithLongName.success).toBe(false);
});
