import * as winston from 'winston';

const env = process.env.ENV || 'dev';
const format = env === 'dev' ? winston.format.simple() : winston.format.json();

export const logger = winston.createLogger({
  level: 'info',
  format: winston.format.json(),
  transports: [
    new winston.transports.Console({
      format,
    }),
  ],
  defaultMeta: { env },
});
