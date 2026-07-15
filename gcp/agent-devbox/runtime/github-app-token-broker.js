#!/usr/bin/env node
"use strict";

const crypto = require("crypto");
const fs = require("fs");
const http = require("http");
const { URL } = require("url");

const config = {
  appId: requireEnv("DEVCLAW_GITHUB_APP_ID"),
  installationId: requireEnv("DEVCLAW_GITHUB_INSTALLATION_ID"),
  owner: requireEnv("DEVCLAW_GITHUB_OWNER"),
  repo: requireEnv("DEVCLAW_GITHUB_REPO"),
  privateKeySecretProject: requireEnv("DEVCLAW_GITHUB_PRIVATE_KEY_SECRET_PROJECT"),
  privateKeySecretId: requireEnv("DEVCLAW_GITHUB_PRIVATE_KEY_SECRET_ID"),
  socketPath: process.env.DEVCLAW_GITHUB_BROKER_SOCKET || "/run/devclaw/github-token-broker.sock",
  permissions: {
    contents: "write",
    issues: "write",
    pull_requests: "write",
    metadata: "read"
  }
};

let cachedInstallationToken = null;

function requireEnv(name) {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

function base64Url(input) {
  return Buffer.from(input)
    .toString("base64")
    .replace(/=/g, "")
    .replace(/\+/g, "-")
    .replace(/\//g, "_");
}

async function fetchJson(url, options = {}) {
  const response = await fetch(url, options);
  const text = await response.text();
  let body = null;
  if (text) {
    try {
      body = JSON.parse(text);
    } catch {
      body = { text };
    }
  }
  if (!response.ok) {
    const message = body?.message || body?.error || response.statusText;
    throw new Error(`HTTP ${response.status} from ${url}: ${message}`);
  }
  return body;
}

async function metadataAccessToken() {
  const body = await fetchJson(
    "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token",
    { headers: { "Metadata-Flavor": "Google" } }
  );
  if (!body?.access_token) {
    throw new Error("Metadata server did not return an access token.");
  }
  return body.access_token;
}

async function accessSecretPayload(project, secretId) {
  const token = await metadataAccessToken();
  const projectPath = encodeURIComponent(project);
  const secretPath = encodeURIComponent(secretId);
  const body = await fetchJson(
    `https://secretmanager.googleapis.com/v1/projects/${projectPath}/secrets/${secretPath}/versions/latest:access`,
    { headers: { Authorization: `Bearer ${token}` } }
  );
  const data = body?.payload?.data;
  if (!data) {
    throw new Error("Secret Manager response did not contain payload data.");
  }
  return Buffer.from(data, "base64").toString("utf8");
}

async function githubJwt() {
  const privateKey = await accessSecretPayload(
    config.privateKeySecretProject,
    config.privateKeySecretId
  );
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "RS256", typ: "JWT" };
  const payload = { iat: now - 60, exp: now + 540, iss: config.appId };
  const signingInput = `${base64Url(JSON.stringify(header))}.${base64Url(JSON.stringify(payload))}`;
  const signature = crypto
    .createSign("RSA-SHA256")
    .update(signingInput)
    .sign(privateKey);
  return `${signingInput}.${base64Url(signature)}`;
}

function tokenFresh(tokenRecord) {
  if (!tokenRecord?.token || !tokenRecord?.expiresAt) {
    return false;
  }
  return Date.parse(tokenRecord.expiresAt) - Date.now() > 5 * 60 * 1000;
}

async function installationToken() {
  if (tokenFresh(cachedInstallationToken)) {
    return cachedInstallationToken;
  }
  const jwt = await githubJwt();
  const body = await fetchJson(
    `https://api.github.com/app/installations/${config.installationId}/access_tokens`,
    {
      method: "POST",
      headers: {
        Accept: "application/vnd.github+json",
        Authorization: `Bearer ${jwt}`,
        "Content-Type": "application/json",
        "User-Agent": "agent-devbox-github-token-broker"
      },
      body: JSON.stringify({
        repositories: [config.repo],
        permissions: config.permissions
      })
    }
  );
  if (!body?.token || !body?.expires_at) {
    throw new Error("GitHub did not return an installation token.");
  }
  cachedInstallationToken = {
    token: body.token,
    expiresAt: body.expires_at,
    permissions: body.permissions || {},
    repositorySelection: body.repository_selection || null
  };
  return cachedInstallationToken;
}

async function githubApi(path) {
  const tokenRecord = await installationToken();
  return fetchJson(`https://api.github.com${path}`, {
    headers: {
      Accept: "application/vnd.github+json",
      Authorization: `Bearer ${tokenRecord.token}`,
      "User-Agent": "agent-devbox-github-token-broker"
    }
  });
}

function sendJson(response, statusCode, body) {
  response.writeHead(statusCode, {
    "Content-Type": "application/json",
    "Cache-Control": "no-store"
  });
  response.end(`${JSON.stringify(body)}\n`);
}

async function handleRequest(request, response) {
  try {
    const url = new URL(request.url, "http://unix");
    if (request.method !== "GET") {
      sendJson(response, 405, { ok: false, error: "method_not_allowed" });
      return;
    }
    if (url.pathname === "/health") {
      sendJson(response, 200, {
        ok: true,
        owner: config.owner,
        repo: config.repo,
        socketPath: config.socketPath
      });
      return;
    }
    if (url.pathname === "/token") {
      const tokenRecord = await installationToken();
      sendJson(response, 200, {
        ok: true,
        token: tokenRecord.token,
        expires_at: tokenRecord.expiresAt,
        owner: config.owner,
        repo: config.repo,
        permissions: tokenRecord.permissions,
        repository_selection: tokenRecord.repositorySelection
      });
      return;
    }
    if (url.pathname === "/repo") {
      const repo = await githubApi(`/repos/${config.owner}/${config.repo}`);
      sendJson(response, 200, {
        ok: true,
        full_name: repo.full_name,
        private: repo.private,
        permissions: repo.permissions || null,
        default_branch: repo.default_branch
      });
      return;
    }
    sendJson(response, 404, { ok: false, error: "not_found" });
  } catch (error) {
    sendJson(response, 500, { ok: false, error: error.message });
  }
}

try {
  fs.rmSync(config.socketPath, { force: true });
} catch {
  // Ignore stale socket removal failures; listen will report a hard error.
}

const server = http.createServer((request, response) => {
  void handleRequest(request, response);
});

server.listen(config.socketPath, () => {
  fs.chmodSync(config.socketPath, 0o660);
  console.log(`GitHub token broker listening on ${config.socketPath}`);
});
