// Redis-backed cache-aside minimal wrapper (async)
import { createClient } from "redis";

const redisUrl = process.env.REDIS_URL || `redis://redis:6379`;
const client = createClient({ url: redisUrl });
client.on("error", (err) => console.error("Redis Client Error", err));
let connected = false;
async function ensure() {
  if (!connected) {
    await client.connect();
    connected = true;
  }
}

export async function get(key) {
  try {
    await ensure();
    const v = await client.get(key);
    return v ? JSON.parse(v) : undefined;
  } catch (e) {
    console.error("cache.get error", e?.message || e);
    return undefined;
  }
}

export async function set(key, value, ttlMs = 60_000) {
  try {
    await ensure();
    const s = JSON.stringify(value);
    if (ttlMs) {
      await client.set(key, s, { PX: ttlMs });
    } else {
      await client.set(key, s);
    }
  } catch (e) {
    console.error("cache.set error", e?.message || e);
  }
}

export async function del(key) {
  try { await ensure(); await client.del(key); } catch (e) { console.error(e); }
}

export async function clearAll() { try { await ensure(); await client.flushDb(); } catch (e) { console.error(e); } }

export default { get, set, del, clearAll };
