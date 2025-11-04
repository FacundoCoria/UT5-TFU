import jwt from "jsonwebtoken";
const SECRET = process.env.JWT_SECRET || "supersecret_dev_only";

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
