import Redis from "ioredis";

const redisUrl = process.env.REDIS_URL;

export const redis = redisUrl
  ? new Redis(redisUrl, {
      maxRetriesPerRequest: 2,
      enableOfflineQueue: false,
      lazyConnect: false,
    })
  : null;

if (redis) {
  redis.on("error", (err) => {
    console.error("Redis error:", err.message);
  });
}

const TTL_SECONDS = 60 * 60 * 24; // 24 hours

export async function getCachedUrl(code: string): Promise<string | null> {
  if (!redis) return null;
  try {
    return await redis.get(`link:${code}`);
  } catch {
    return null;
  }
}

export async function setCachedUrl(code: string, url: string): Promise<void> {
  if (!redis) return;
  try {
    await redis.set(`link:${code}`, url, "EX", TTL_SECONDS);
  } catch {
    // caching is best-effort; a failure here must not break the request
  }
}
