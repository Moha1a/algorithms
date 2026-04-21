import {logger} from 'firebase-functions';

export function logInfo(message: string, data: Record<string, unknown> = {}): void {
  logger.info(message, data);
}

export function logWarn(message: string, data: Record<string, unknown> = {}): void {
  logger.warn(message, data);
}

export function logError(message: string, data: Record<string, unknown> = {}): void {
  logger.error(message, data);
}
