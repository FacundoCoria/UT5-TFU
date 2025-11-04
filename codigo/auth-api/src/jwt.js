import jwt from "jsonwebtoken";
const SECRET = process.env.JWT_SECRET || "supersecret_dev_only";
const EXPIRES = process.env.JWT_EXPIRES || "12h";
const VALET_EXPIRES = process.env.VALET_EXPIRES || "60s";

export function signToken(payload) {
  return jwt.sign(payload, SECRET, { expiresIn: EXPIRES });
}

// Valet key: 
export function signValet(payload) {
  const p = { ...payload, purpose: "valet" };
  return jwt.sign(p, SECRET, { expiresIn: VALET_EXPIRES });
}

export function authMiddleware(req, res, next) {
  try {
    const auth = req.headers.authorization || "";
    const [, token] = auth.split(" ");
    if (!token) return res.status(401).json({ error: "unauthorized" });
    const decoded = jwt.verify(token, SECRET);
    req.user = decoded;
    next();
  } catch {
    return res.status(401).json({ error: "unauthorized" });
  }
}
