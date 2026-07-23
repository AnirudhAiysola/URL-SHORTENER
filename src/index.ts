import "dotenv/config";
import express, { Request, Response } from "express";
import { pool, initSchema } from "./db";
import { generateCode } from "./code";

const app = express();
const PORT = process.env.PORT || 3000;
const BASE_URL = process.env.BASE_URL || `http://localhost:${PORT}`;

app.use(express.json());

app.get("/health", async (_req: Request, res: Response) => {
  try {
    await pool.query("SELECT 1");
    res.json({ status: "ok" });
  } catch {
    res.status(503).json({ status: "db_unavailable" });
  }
});

app.post("/shorten", async (req: Request, res: Response) => {
  const { url } = req.body ?? {};

  // Job 1: validate the input
  if (typeof url !== "string") {
    return res.status(400).json({ error: "Body must include a 'url' string." });
  }
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    return res.status(400).json({ error: "Not a valid URL." });
  }
  if (parsed.protocol !== "http:" && parsed.protocol !== "https:") {
    return res.status(400).json({ error: "Only http and https URLs allowed." });
  }

  // Job 2: generate a code
  const code = generateCode();

  // Job 3: store it
  try {
    await pool.query("INSERT INTO links (code, original_url) VALUES ($1, $2)", [
      code,
      url,
    ]);
  } catch (err) {
    console.error("Insert failed:", err);
    return res.status(500).json({ error: "Could not create short link." });
  }

  res.status(201).json({ code, shortUrl: `${BASE_URL}/${code}` });
});

app.get("/:code", async (req: Request, res: Response) => {
  const { code } = req.params;

  const result = await pool.query(
    "SELECT original_url FROM links WHERE code = $1",
    [code],
  );

  if (result.rowCount === 0) {
    return res.status(404).json({ error: "Short link not found." });
  }

  res.redirect(302, result.rows[0].original_url);
});

async function start(): Promise<void> {
  try {
    await initSchema();
    app.listen(PORT, () => {
      console.log(`URL shortener listening on ${BASE_URL}`);
    });
  } catch (err) {
    console.error("Failed to start:", err);
    process.exit(1);
  }
}

start();
