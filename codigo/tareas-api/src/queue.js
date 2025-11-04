import pool from "./db.js";
import { createClient } from "redis";

// Redis-backed simple queue using a list (RPUSH + BLPOP)
const redisUrl = process.env.REDIS_URL || `redis://redis:6379`;

// Use two separate clients: one for producing (rPush) and one for blocking consume (blPop).
const producer = createClient({ url: redisUrl });
const consumer = createClient({ url: redisUrl });
producer.on("error", (e) => console.error("Redis producer error", e));
consumer.on("error", (e) => console.error("Redis consumer error", e));
let producerStarted = false;
let consumerStarted = false;

async function ensureProducer() {
  if (!producerStarted) { await producer.connect(); producerStarted = true; }
}

async function ensureConsumer() {
  if (!consumerStarted) { await consumer.connect(); consumerStarted = true; }
}

const QUEUE_KEY = process.env.TAREAS_QUEUE_KEY || "tareas:queue";

function sleep(ms) { return new Promise((r) => setTimeout(r, ms)); }

// Retry helper (simple exponential backoff)
async function retryAsync(fn, attempts = 3, delay = 200) {
  let i = 0;
  while (true) {
    try { return await fn(); } catch (e) {
      i++;
      if (i >= attempts) throw e;
      await sleep(delay);
      delay *= 2;
    }
  }
}

async function tryInsertTask(payload) {
  const { proyecto_id, titulo, asignado_a_usuario_id } = payload;
  return await retryAsync(async () => {
    const [r] = await pool.query(
      `INSERT INTO proyectos_db.tareas(proyecto_id, titulo, asignado_a_usuario_id)
       VALUES(?,?,?)`,
      [proyecto_id, titulo, asignado_a_usuario_id ?? null]
    );
    const [rows] = await pool.query(
      `SELECT id, proyecto_id, titulo, estado, asignado_a_usuario_id, creado_en
       FROM proyectos_db.tareas WHERE id = ?`,
      [r.insertId]
    );
    return rows[0];
  }, 3, 200);
}

// Worker loop that blocks on the Redis list
async function workerLoop() {
  await ensureConsumer();
  while (true) {
    try {
      // BLPOP returns { key, element } shape in node-redis v4
      const res = await consumer.blPop(QUEUE_KEY, 0);
      if (!res) continue;
      const payload = JSON.parse(res.element);
      try {
        const created = await tryInsertTask(payload);
        // Optionally: push result to a results list or pub/sub; for now just log
        console.log("queue: processed task", created.id);
      } catch (e) {
        console.error("queue: failed to process payload", e?.message || e);
      }
    } catch (e) {
      console.error("queue worker loop error", e?.message || e);
      await sleep(1000);
    }
  }
}

// Start worker if env says so
if (process.env.START_TAREAS_WORKER === "1") {
  // start consumer connection and worker loop
  (async () => {
    try {
      await ensureConsumer();
      workerLoop().catch((e) => console.error("workerLoop crashed", e));
    } catch (e) {
      console.error("Could not start tareas worker", e);
    }
  })();
}

export async function enqueueTask(payload) {
  await ensureProducer();
  const s = JSON.stringify(payload);
  await producer.rPush(QUEUE_KEY, s);
  // In this minimal design we don't return the created item synchronously.
  // The caller can poll or we could implement a result channel; for simplicity
  // return a small ack object.
  return { enqueued: true };
}

export default { enqueueTask };
