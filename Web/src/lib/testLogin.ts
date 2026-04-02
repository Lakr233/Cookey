import nacl from "tweetnacl";

export type RequestStatus = "pending" | "ready" | "delivered" | "expired";

export interface LoginRequestState {
  rid: string;
  serverUrl: string;
  targetUrl: string;
  deepLink: string;
}

export interface RequestStatusResponse {
  created_at: string;
  expires_at: string;
  request_type?: string;
  rid: string;
  status: RequestStatus;
  target_url: string;
}

interface ApiErrorResponse {
  error?: string;
  message?: string;
}

const REQUEST_ID_PATTERN = /^r_[A-Za-z0-9_-]{22}$/;
export const API_BASE = "/api";
export const TARGET_URL = "https://cookey.sh/test-login-site";
export const REQUEST_POLL_INTERVAL_MS = 2000;

function bytesToBinary(bytes: Uint8Array): string {
  let binary = "";
  for (const value of bytes) {
    binary += String.fromCharCode(value);
  }
  return binary;
}

function bytesToBase64(bytes: Uint8Array): string {
  return btoa(bytesToBinary(bytes));
}

function bytesToBase64Url(bytes: Uint8Array): string {
  return bytesToBase64(bytes).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function utcTimestamp(date: Date): string {
  return date.toISOString().replace(/\.\d{3}Z$/, "Z");
}

function requireAbsoluteUrl(value: string, label: string): string {
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    throw new Error(`${label} is not a valid absolute URL.`);
  }

  if (url.protocol !== "https:" && url.protocol !== "http:") {
    throw new Error(`${label} must use http or https.`);
  }

  url.hash = "";
  return url.toString();
}

function futureIsoDate(secondsFromNow: number): string {
  return utcTimestamp(new Date(Date.now() + secondsFromNow * 1000));
}

function generateRequestId(): string {
  return `r_${bytesToBase64Url(crypto.getRandomValues(new Uint8Array(16)))}`;
}

function generateRequestSecret(): string {
  return bytesToBase64Url(crypto.getRandomValues(new Uint8Array(32)));
}

async function generateDeviceFingerprint(
  publicKeyBase64: string,
  deviceId: string,
): Promise<string> {
  const input = new TextEncoder().encode(
    [publicKeyBase64, deviceId, navigator.userAgent].join("|"),
  );
  const digest = await crypto.subtle.digest("SHA-256", input);
  return bytesToBase64Url(new Uint8Array(digest));
}

async function computeRequestProof(params: {
  deviceId: string;
  expiresAt: string;
  pubkey: string;
  rid: string;
  requestSecret: string;
  requestType: string;
  serverUrl: string;
  targetUrl: string;
}): Promise<string> {
  const secret = params.requestSecret.replace(/-/g, "+").replace(/_/g, "/");
  const padding = "=".repeat((4 - (secret.length % 4)) % 4);
  const secretBytes = Uint8Array.from(atob(secret + padding), (char) => char.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "raw",
    secretBytes,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const message = [
    "cookey-request-v1",
    params.rid,
    params.serverUrl,
    params.targetUrl,
    params.pubkey,
    params.deviceId,
    params.requestType,
    params.expiresAt,
  ].join("\n");
  const signature = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message));
  return bytesToBase64Url(new Uint8Array(signature));
}

function buildDeepLink(params: {
  deviceId: string;
  expiresAt: string;
  pubkey: string;
  rid: string;
  requestProof: string;
  requestSecret: string;
  serverUrl: string;
  targetUrl: string;
}): string {
  const query = new URLSearchParams({
    device_id: params.deviceId,
    expires_at: params.expiresAt,
    pubkey: params.pubkey,
    request_proof: params.requestProof,
    request_secret: params.requestSecret,
    request_type: "login",
    rid: params.rid,
    server: params.serverUrl,
    target: params.targetUrl,
  });

  return `cookey://login?${query.toString()}`;
}

async function readJson(response: Response): Promise<unknown> {
  const text = await response.text();
  if (!text.trim()) {
    return null;
  }

  try {
    return JSON.parse(text) as unknown;
  } catch {
    throw new Error("API returned invalid JSON.");
  }
}

function toApiErrorMessage(payload: unknown, fallback: string): string {
  if (payload && typeof payload === "object") {
    const errorPayload = payload as ApiErrorResponse;
    if (typeof errorPayload.error === "string" && errorPayload.error.trim()) {
      return errorPayload.error;
    }
    if (typeof errorPayload.message === "string" && errorPayload.message.trim()) {
      return errorPayload.message;
    }
  }

  return fallback;
}

export async function createLoginRequest(signal: AbortSignal): Promise<LoginRequestState> {
  const serverUrl = API_BASE;
  const relayServerUrl = "https://api.cookey.sh";
  const targetUrl = requireAbsoluteUrl(TARGET_URL, "Target URL");
  const rid = generateRequestId();
  const deviceId = crypto.randomUUID();
  const keyPair = nacl.box.keyPair();
  const pubkey = bytesToBase64(keyPair.publicKey);
  const deviceFingerprint = await generateDeviceFingerprint(pubkey, deviceId);
  const expiresAt = futureIsoDate(300);
  const requestSecret = generateRequestSecret();
  const requestProof = await computeRequestProof({
    deviceId,
    expiresAt,
    pubkey,
    rid,
    requestSecret,
    requestType: "login",
    serverUrl: relayServerUrl,
    targetUrl,
  });

  const response = await fetch(`${serverUrl}/v1/requests`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      cli_public_key: pubkey,
      device_fingerprint: deviceFingerprint,
      device_id: deviceId,
      expires_at: expiresAt,
      request_proof: requestProof,
      request_secret: requestSecret,
      request_type: "login",
      rid,
      target_url: targetUrl,
    }),
    signal,
  });

  const payload = await readJson(response);

  if (!response.ok) {
    throw new Error(
      toApiErrorMessage(payload, `Login request failed with status ${response.status}.`),
    );
  }

  if (!isRequestStatusResponse(payload)) {
    throw new Error("API returned an unexpected response shape.");
  }

  return {
    rid: payload.rid,
    serverUrl: relayServerUrl,
    targetUrl,
    deepLink: buildDeepLink({
      deviceId,
      expiresAt,
      pubkey,
      rid: payload.rid,
      requestProof,
      requestSecret,
      serverUrl: relayServerUrl,
      targetUrl,
    }),
  };
}

export function isRequestStatus(value: unknown): value is RequestStatus {
  return value === "pending" || value === "ready" || value === "delivered" || value === "expired";
}

export function isRequestStatusResponse(value: unknown): value is RequestStatusResponse {
  if (!value || typeof value !== "object") {
    return false;
  }

  const candidate = value as Partial<RequestStatusResponse>;
  return (
    typeof candidate.rid === "string" &&
    REQUEST_ID_PATTERN.test(candidate.rid) &&
    typeof candidate.created_at === "string" &&
    typeof candidate.expires_at === "string" &&
    typeof candidate.target_url === "string" &&
    isRequestStatus(candidate.status)
  );
}

export function validateRequestId(value: string | null): string {
  const rid = value?.trim() ?? "";
  if (!REQUEST_ID_PATTERN.test(rid)) {
    throw new Error("Missing or invalid request ID.");
  }
  return rid;
}

export async function fetchRequestStatus(
  rid: string,
  signal?: AbortSignal,
): Promise<RequestStatusResponse> {
  const response = await fetch(`${API_BASE}/v1/requests/${encodeURIComponent(rid)}`, {
    signal,
  });

  if (response.status === 410) {
    return {
      created_at: "",
      expires_at: "",
      rid,
      status: "expired",
      target_url: TARGET_URL,
    };
  }

  const payload = await readJson(response);

  if (!response.ok) {
    throw new Error(
      toApiErrorMessage(payload, `Request lookup failed with status ${response.status}.`),
    );
  }

  if (!isRequestStatusResponse(payload)) {
    throw new Error("API returned an unexpected response shape.");
  }

  return payload;
}

export function formatDateTime(value: string): string {
  if (!value) {
    return "Unavailable";
  }

  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return value;
  }
  return date.toLocaleString();
}
