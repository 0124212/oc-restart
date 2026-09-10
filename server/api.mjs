import http from "node:http";
import { WebSocketServer } from "ws";
import { execSync } from "node:child_process";

const TOKEN = "d204f2016b28c0c50c793df833c9be3d370662a5dcfc5c8ebedf110e034388a9";
const PORT = 4099;
const TAILSCALE_IP = "100.115.178.90";

function shell(cmd) {
  try {
    return execSync(cmd, { timeout: 10000, encoding: "utf8" }).trim();
  } catch {
    return null;
  }
}

function getStatus() {
  const uptime = shell("uptime -p");
  const memRaw = shell("free -m | awk '/Mem:/{printf \"%d/%d\", $3, $2}'");
  const diskRaw = shell("df -h / | awk 'NR==2{printf \"%s/%s (%s)\", $3, $2, $5}'");
  const load = shell("cat /proc/loadavg | awk '{print $1}'");
  const temp = shell("cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null");
  const tempC = temp ? `${Math.round(temp / 1000)}°C` : "n/a";
  const opencode = shell("systemctl is-active opencode-serve");
  return { uptime, mem: memRaw, disk: diskRaw, load, temp: tempC, opencode };
}

function getServices() {
  const raw = shell(
    `docker ps --format '{{.Names}}\\t{{.Status}}\\t{{.Ports}}\\t{{.State}}'`
  );
  if (!raw) return [];
  return raw.split("\n").map((line) => {
    const [name, status, ports, state] = line.split("\t");
    return { name, status, ports, state };
  });
}

function buildSnapshot() {
  return JSON.stringify({ type: "snapshot", status: getStatus(), services: getServices(), ts: Date.now() });
}

// ─── HTTP server (REST for one-off calls) ────────────────
const server = http.createServer((req, res) => {
  if (req.method === "OPTIONS") {
    res.writeHead(204, {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
      "Access-Control-Allow-Headers": "Authorization, Content-Type",
    });
    return res.end();
  }

  const authHeader = req.headers.authorization || "";
  if (authHeader !== `Bearer ${TOKEN}`) {
    res.writeHead(401, { "Content-Type": "application/json" });
    return res.end(JSON.stringify({ error: "unauthorized" }));
  }

  const url = new URL(req.url, `http://${req.headers.host}`);
  const cors = { "Access-Control-Allow-Origin": "*", "Content-Type": "application/json" };

  if (url.pathname === "/api/status" && req.method === "GET") {
    res.writeHead(200, cors);
    return res.end(JSON.stringify(getStatus()));
  }
  if (url.pathname === "/api/services" && req.method === "GET") {
    res.writeHead(200, cors);
    return res.end(JSON.stringify(getServices()));
  }
  if (url.pathname === "/api/restart/opencode" && req.method === "POST") {
    shell("sudo systemctl restart opencode-serve");
    res.writeHead(200, cors);
    return res.end(JSON.stringify({ restarted: "opencode-serve" }));
  }
  const svcMatch = url.pathname.match(/^\/api\/restart\/(.+)$/);
  if (svcMatch && req.method === "POST") {
    const name = svcMatch[1];
    shell(`docker restart ${name}`);
    res.writeHead(200, cors);
    return res.end(JSON.stringify({ restarted: name }));
  }

  res.writeHead(404, cors);
  res.end(JSON.stringify({ error: "not found" }));
});

// ─── WebSocket (real-time sync) ──────────────────────────
const wss = new WebSocketServer({ server });

wss.on("connection", (ws, req) => {
  // Auth via first message or query param
  const url = new URL(req.url, `http://${req.headers.host}`);
  const qToken = url.searchParams.get("token");

  let authenticated = false;

  ws.on("message", (data) => {
    const msg = data.toString();

    if (!authenticated) {
      if (msg === TOKEN || qToken === TOKEN) {
        authenticated = true;
        ws.send(buildSnapshot());
      } else {
        ws.send(JSON.stringify({ type: "error", message: "unauthorized" }));
        ws.close();
      }
      return;
    }

    try {
      const parsed = JSON.parse(msg);
      if (parsed.type === "restart" && parsed.target === "opencode") {
        shell("sudo systemctl restart opencode-serve");
        ws.send(JSON.stringify({ type: "restarted", target: "opencode" }));
      } else if (parsed.type === "restart" && parsed.target) {
        shell(`docker restart ${parsed.target}`);
        ws.send(JSON.stringify({ type: "restarted", target: parsed.target }));
      } else if (parsed.type === "ping") {
        ws.send(JSON.stringify({ type: "pong", ts: Date.now() }));
      }
    } catch {}
  });

  // Push snapshot every 5s while connected
  const interval = setInterval(() => {
    if (ws.readyState === 1 && authenticated) {
      ws.send(buildSnapshot());
    }
  }, 5000);

  ws.on("close", () => clearInterval(interval));
});

server.listen(PORT, TAILSCALE_IP, () => {
  console.log(`mgmt-api + ws on ${TAILSCALE_IP}:${PORT}`);
});
