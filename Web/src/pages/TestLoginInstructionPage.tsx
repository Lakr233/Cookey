import { useEffect, useState } from "react";
import Nav from "../components/Nav";
import Footer from "../components/Footer";
import Container from "../components/Container";
import Badge from "../components/Badge";
import QrCode from "../components/QrCode";
import { Button, ButtonLink } from "../components/Button";

interface DeviceKeys {
  deviceId: string;
  pubkey: string;
}

interface CreateLoginRequestResponse {
  rid: string;
  server_url?: string;
}

interface ApiErrorResponse {
  code?: string;
  message: string;
}

interface LoginRequest {
  rid: string;
  serverUrl: string;
  targetUrl: string;
  deepLink: string;
  monitorUrl: string;
}

type PageState =
  | { status: "loading" }
  | { status: "ready"; request: LoginRequest }
  | { status: "error"; error: string };

const API_BASE = "https://api.cookey.sh";
const TARGET_URL = "https://cookey.sh/test-login-do";
const REQUEST_ID_PATTERN = /^[A-Za-z0-9_-]{6,128}$/;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function isNonEmptyString(value: unknown): value is string {
  return typeof value === "string" && value.trim().length > 0;
}

function isApiErrorResponse(value: unknown): value is ApiErrorResponse {
  return (
    isRecord(value) &&
    isNonEmptyString(value.message) &&
    (value.code === undefined || isNonEmptyString(value.code))
  );
}

function isCreateLoginRequestResponse(
  value: unknown,
): value is CreateLoginRequestResponse {
  return (
    isRecord(value) &&
    isNonEmptyString(value.rid) &&
    (value.server_url === undefined || isNonEmptyString(value.server_url))
  );
}

function toErrorMessage(error: unknown): string {
  if (error instanceof Error && error.message.trim()) {
    return error.message;
  }
  return "Failed to create the Cookey login request.";
}

function normalizeUrl(value: string, label: string): URL {
  try {
    return new URL(value);
  } catch {
    throw new Error(`${label} is not a valid absolute URL.`);
  }
}

function validateHttpsUrl(value: string, label: string): string {
  const url = normalizeUrl(value, label);
  if (url.protocol !== "https:") {
    throw new Error(`${label} must use https.`);
  }
  url.hash = "";
  return url.toString();
}

function validateHttpUrl(value: string, label: string): string {
  const url = normalizeUrl(value, label);
  if (url.protocol !== "https:" && url.protocol !== "http:") {
    throw new Error(`${label} must use http or https.`);
  }
  url.hash = "";
  return url.toString();
}

function validateRequestId(value: string): string {
  const rid = value.trim();
  if (!REQUEST_ID_PATTERN.test(rid)) {
    throw new Error("API returned an invalid request ID.");
  }
  return rid;
}

function withTrailingSlash(value: string): string {
  return value.endsWith("/") ? value : `${value}/`;
}

function generateKeyPair(): DeviceKeys {
  const deviceId = crypto.randomUUID();
  const randomBytes = crypto.getRandomValues(new Uint8Array(32));
  let binary = "";

  for (const byte of randomBytes) {
    binary += String.fromCharCode(byte);
  }

  return { deviceId, pubkey: btoa(binary) };
}

function buildDeepLink(
  rid: string,
  deviceId: string,
  pubkey: string,
  serverUrl: string,
  targetUrl: string,
): string {
  const params = new URLSearchParams({
    device_id: deviceId,
    pubkey,
    request_type: "login",
    rid,
    server: serverUrl,
    target: targetUrl,
  });

  return `cookey://login?${params.toString()}`;
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

async function createLoginRequest(signal: AbortSignal): Promise<LoginRequest> {
  const apiBaseUrl = validateHttpsUrl(API_BASE, "API base URL");
  const targetUrl = validateHttpsUrl(TARGET_URL, "Target URL");
  const endpoint = new URL("v1/requests", withTrailingSlash(apiBaseUrl));
  const { deviceId, pubkey } = generateKeyPair();

  const response = await fetch(endpoint, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      target_url: targetUrl,
      request_type: "login",
      device_id: deviceId,
      pubkey,
    }),
    signal,
  });

  const payload = await readJson(response);

  if (!response.ok) {
    if (isApiErrorResponse(payload)) {
      throw new Error(payload.message);
    }

    throw new Error(
      `Login request failed with status ${response.status}. Please retry.`,
    );
  }

  if (!isCreateLoginRequestResponse(payload)) {
    throw new Error("API returned an unexpected response shape.");
  }

  const rid = validateRequestId(payload.rid);
  const serverUrl = validateHttpUrl(
    payload.server_url ?? apiBaseUrl,
    "Server URL",
  );

  return {
    rid,
    serverUrl,
    targetUrl,
    deepLink: buildDeepLink(rid, deviceId, pubkey, serverUrl, targetUrl),
    monitorUrl: `/test-login-do?rid=${encodeURIComponent(rid)}`,
  };
}

export default function TestLoginInstructionPage() {
  const [state, setState] = useState<PageState>({ status: "loading" });
  const [attempt, setAttempt] = useState(0);

  useEffect(() => {
    const controller = new AbortController();
    setState({ status: "loading" });

    void (async () => {
      try {
        const request = await createLoginRequest(controller.signal);
        if (!controller.signal.aborted) {
          setState({ status: "ready", request });
        }
      } catch (error) {
        if (!controller.signal.aborted) {
          setState({
            status: "error",
            error: toErrorMessage(error),
          });
        }
      }
    })();

    return () => {
      controller.abort();
    };
  }, [attempt]);

  const request = state.status === "ready" ? state.request : null;
  const errorMessage = state.status === "error" ? state.error : null;
  const isLoading = state.status === "loading";
  const isError = errorMessage !== null;

  return (
    <div className="bg-bg text-ink font-sans leading-[1.6] min-h-screen flex flex-col">
      <Nav />

      <main className="flex-1">
        <Container>
          <section className="pt-20 pb-16">
            <div className="mb-7 text-center">
              <Badge>App Store Review Test</Badge>
            </div>

            <div className="mx-auto max-w-[620px] text-center">
              <h1 className="mb-[18px] font-bold tracking-[-0.03em] leading-[1.1] text-[clamp(2.2rem,6vw,3.2rem)]">
                Start a test login request.
              </h1>
              <p className="mx-auto mb-10 max-w-[540px] text-[1.05rem] text-muted">
                Create a fresh Cookey request, open it in the app, then continue
                to the live status page to confirm the relay flow works end to
                end.
              </p>
            </div>

            <div className="mx-auto max-w-[620px] rounded-xl border border-border bg-surface p-6 sm:p-7">
              {isLoading && (
                <div className="text-center" role="status" aria-live="polite">
                  <div className="mb-5 flex justify-center">
                    <div aria-hidden="true" className="h-10 w-10 animate-spin rounded-full border-[3px] border-border border-t-accent" />
                  </div>
                  <h2 className="text-xl font-semibold tracking-tight">
                    Creating login request
                  </h2>
                  <p className="mt-3 text-sm text-muted">
                    Generating device keys, validating configuration, and
                    requesting a fresh session from the relay.
                  </p>
                </div>
              )}

              {isError && (
                <div className="text-center" role="status" aria-live="polite">
                  <h2 className="text-xl font-semibold tracking-tight">
                    Request setup failed
                  </h2>
                  <p className="mt-3 text-sm text-muted">{errorMessage}</p>
                  <div className="mt-6 flex flex-wrap justify-center gap-3">
                    <Button
                      variant="primary"
                      onClick={() => setAttempt((current) => current + 1)}
                    >
                      Retry request
                    </Button>
                    <ButtonLink href="/" variant="secondary">
                      Back to home
                    </ButtonLink>
                  </div>
                </div>
              )}

              {request && (
                <div className="flex flex-col gap-8 md:flex-row md:items-start">
                  <div className="mx-auto w-full max-w-[210px] rounded-xl border border-border bg-terminal-bg p-5 md:mx-0">
                    <div className="flex justify-center">
                      <QrCode />
                    </div>
                    <p className="mt-3 text-center text-xs text-muted">
                      Open Cookey on the review device, then continue to the
                      request status page.
                    </p>
                  </div>

                  <div className="flex-1">
                    <h2 className="text-xl font-semibold tracking-tight">
                      Request ready
                    </h2>
                    <p className="mt-3 text-sm text-muted">
                      Use the Cookey deep link first. After switching to the
                      app, open the status page below to watch the request
                      complete.
                    </p>

                    <div className="mt-6 flex flex-wrap gap-3">
                      <ButtonLink href={request.deepLink} variant="primary">
                        Open in Cookey
                      </ButtonLink>
                      <ButtonLink href={request.monitorUrl} variant="secondary">
                        Continue to status page
                      </ButtonLink>
                    </div>

                    <dl className="mt-6 space-y-4 rounded-xl border border-border bg-terminal-bg p-5 text-sm">
                      <div>
                        <dt className="text-[11px] uppercase tracking-[0.18em] text-muted">
                          Request ID
                        </dt>
                        <dd className="mt-1 font-mono break-all text-ink">
                          {request.rid}
                        </dd>
                      </div>
                      <div>
                        <dt className="text-[11px] uppercase tracking-[0.18em] text-muted">
                          Relay server
                        </dt>
                        <dd className="mt-1 font-mono break-all text-ink">
                          {request.serverUrl}
                        </dd>
                      </div>
                      <div>
                        <dt className="text-[11px] uppercase tracking-[0.18em] text-muted">
                          Target URL
                        </dt>
                        <dd className="mt-1 font-mono break-all text-ink">
                          {request.targetUrl}
                        </dd>
                      </div>
                    </dl>

                    <div className="mt-6 rounded-xl border border-border p-5">
                      <h3 className="font-semibold">Flow</h3>
                      <ol className="mt-3 list-decimal space-y-2 pl-5 text-sm text-muted">
                        <li>Open Cookey with the primary button above.</li>
                        <li>Complete the login on the mobile device.</li>
                        <li>Open the status page to verify delivery.</li>
                      </ol>
                    </div>
                  </div>
                </div>
              )}
            </div>
          </section>
        </Container>
      </main>

      <Footer rightLink={{ label: "Back to Home", href: "/" }} />
    </div>
  );
}
