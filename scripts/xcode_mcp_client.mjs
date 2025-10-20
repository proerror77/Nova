#!/usr/bin/env node
// Minimal MCP stdio client for XcodeBuildMCP
// Supports: initialize, resources/list+read, tools/list+call
import { spawn } from 'node:child_process';
import process from 'node:process';

function writeMessage(child, msg) {
  const json = JSON.stringify(msg);
  const payload = `Content-Length: ${Buffer.byteLength(json, 'utf8')}\r\n\r\n${json}`;
  child.stdin.write(payload, 'utf8');
}

function parseHeaders(buf) {
  const s = buf.toString('utf8');
  const idx = s.indexOf('\r\n\r\n');
  if (idx === -1) return null;
  const headers = s.slice(0, idx).split('\r\n');
  const map = {};
  for (const h of headers) {
    const m = h.match(/^(.*?):\s*(.*)$/);
    if (m) map[m[1].toLowerCase()] = m[2];
  }
  const len = parseInt(map['content-length'] || '0', 10);
  const rest = s.slice(idx + 4);
  if (rest.length < len) return null;
  const body = rest.slice(0, len);
  const remaining = Buffer.from(rest.slice(len), 'utf8');
  return { body: JSON.parse(body), remaining };
}

async function run() {
  const args = process.argv.slice(2);
  const opt = {
    workspace: process.env.WORKSPACE || 'ios/NovaSocial/NovaSocial.xcworkspace',
    scheme: process.env.SCHEME || 'NovaSocial',
    deviceName: process.env.DEVICE_NAME || '',
    action: process.env.ACTION || 'doctor', // doctor | list-tools | run | build
  };
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a === '--workspace') opt.workspace = args[++i];
    else if (a === '--scheme') opt.scheme = args[++i];
    else if (a === '--device') opt.deviceName = args[++i];
    else if (a === '--action') opt.action = args[++i];
  }

  const env = { ...process.env, INCREMENTAL_BUILDS_ENABLED: 'true', XCODEBUILDMCP_SENTRY_DISABLED: process.env.XCODEBUILDMCP_SENTRY_DISABLED || 'false' };
  const child = spawn('npx', ['-y', 'xcodebuildmcp@latest'], { env });
  let buf = Buffer.alloc(0);
  let nextId = 1;
  const pending = new Map();
  function request(method, params = {}) {
    const id = nextId++;
    const msg = { jsonrpc: '2.0', id, method, params };
    writeMessage(child, msg);
    return new Promise((resolve, reject) => {
      pending.set(id, { resolve, reject });
    });
  }

  child.stdout.on('data', (chunk) => {
    buf = Buffer.concat([buf, chunk]);
    while (true) {
      const parsed = parseHeaders(buf);
      if (!parsed) break;
      buf = parsed.remaining;
      const msg = parsed.body;
      if (msg.id && pending.has(msg.id)) {
        const { resolve, reject } = pending.get(msg.id);
        pending.delete(msg.id);
        if (msg.error) reject(new Error(msg.error.message || 'MCP error'));
        else resolve(msg.result || msg);
      } else {
        // Notifications; ignore
      }
    }
  });
  child.stderr.on('data', (d) => process.stderr.write(d));
  child.on('exit', (code) => {
    if (code !== 0) process.exit(code || 1);
  });

  // Initialize
  const initRes = await request('initialize', {
    protocolVersion: '2024-11-05',
    clientInfo: { name: 'codex-mcp-helper', version: '0.1.0' },
    capabilities: { experimental: true },
  });
  // console.log('Initialized:', initRes.serverInfo || initRes);

  if (opt.action === 'doctor') {
    const list = await request('resources/list', {});
    const doctor = (list.resources || []).find((r) => r.uri && /doctor/.test(r.uri));
    if (!doctor) {
      console.log('No doctor resource');
    } else {
      const read = await request('resources/read', { uri: doctor.uri });
      console.log(JSON.stringify(read, null, 2));
    }
    child.kill();
    return;
  }

  if (opt.action === 'list-tools') {
    const t = await request('tools/list', {});
    const names = (t.tools || []).map((x) => ({ name: x.name, desc: x.description }));
    console.log(JSON.stringify(names, null, 2));
    child.kill();
    return;
  }

  // Resolve simulator/device if requested
  let selectedDevice = opt.deviceName;
  if (!selectedDevice) {
    try {
      const list = await request('resources/list', {});
      const sims = (list.resources || []).find((r) => r.uri && /simulators/.test(r.uri));
      if (sims) {
        const read = await request('resources/read', { uri: sims.uri });
        const items = read?.resource?.text ? JSON.parse(read.resource.text) : read;
        const devices = items?.devices || items || [];
        const preferred = devices.find((d) => /iPhone 16 Pro|iPhone 16|iPhone 15 Pro|iPhone 15/.test(d.name)) || devices.find((d) => /iPhone/.test(d.name));
        if (preferred) selectedDevice = preferred.name;
      }
    } catch {}
  }

  const tools = await request('tools/list', {});
  const toolList = tools.tools || [];

  // Heuristic: prefer a run tool, then build
  const runTool = toolList.find((t) => /run/i.test(t.name)) || toolList.find((t) => /launch/i.test(t.name));
  const buildTool = toolList.find((t) => /build/i.test(t.name));

  async function callTool(tool, params) {
    const res = await request('tools/call', { name: tool.name, arguments: params || {} });
    console.log(JSON.stringify({ tool: tool.name, result: res }, null, 2));
    return res;
  }

  const common = { workspace: opt.workspace, scheme: opt.scheme };

  if (opt.action === 'run') {
    if (!runTool) throw new Error('No run tool found');
    const p = { ...common };
    if (selectedDevice) p.device = selectedDevice;
    await callTool(runTool, p);
    child.kill();
    return;
  }

  if (opt.action === 'build') {
    if (!buildTool) throw new Error('No build tool found');
    await callTool(buildTool, { ...common });
    child.kill();
    return;
  }

  // Default: doctor
  const list = await request('resources/list', {});
  const doctor = (list.resources || []).find((r) => r.uri && /doctor/.test(r.uri));
  if (doctor) {
    const read = await request('resources/read', { uri: doctor.uri });
    console.log(JSON.stringify(read, null, 2));
  }
  child.kill();
}

run().catch((err) => {
  console.error(err.stack || err.message);
  process.exit(1);
});

