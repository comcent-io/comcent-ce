import { createClient, RedisClientType } from 'redis';
import { logger } from '../logger.js';

let redisClient: RedisClientType;

async function initializeRedis() {
  // Create Redis client if it doesn't exist
  if (!redisClient) {
    redisClient = createClient({
      url: process.env.REDIS_URL,
    });

    // Set up event listeners for connection events
    redisClient.on('error', (err) => {
      logger.error(`Redis error: ${err}`);
    });

    redisClient.on('reconnecting', () => {
      logger.info('Attempting to reconnect to Redis...');
    });

    redisClient.on('connect', () => {
      logger.info('Connected to Redis');
    });
  }

  // Try connecting until successful
  while (!redisClient.isOpen) {
    try {
      await redisClient.connect();
    } catch (error: any) {
      logger.error(`Failed to connect to Redis: ${error}`);
      // Wait before retry
      await new Promise((resolve) => setTimeout(resolve, 5000));
      logger.info('Retrying Redis connection...');
    }
  }
}

// Initialize Redis connection
initializeRedis().catch((err) => {
  logger.error(`Redis initialization error: ${err}`);
});

export { redisClient };
