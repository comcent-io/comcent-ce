import * as amqplib from 'amqplib';
import type { ComcentEvent } from '../types/ComcentEvent.ts';
import { logger } from '../logger.js';

async function sendToExchange(exchange: string, routingKey: string, message: string) {
  const conn = await amqplib.connect(process.env.RABBITMQ_URL!);
  const channel = await conn.createChannel();
  logger.info(`Sending to exchange ${exchange}`);
  channel.publish(exchange, routingKey, Buffer.from(message));
  await channel.close();
  await conn.close();
}

export async function sendToComcentEvents(topic: string, message: ComcentEvent) {
  await sendToExchange('Comcent.Events', topic, JSON.stringify(message));
}
