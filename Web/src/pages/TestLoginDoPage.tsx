import { useEffect, useState } from "react";
import Nav from "../components/Nav";
import Footer from "../components/Footer";
import Container from "../components/Container";
import Badge from "../components/Badge";
import { ButtonLink } from "../components/Button";

type RequestStatus = "pending" | "ready" | "delivered" | "expired";

type PageState =
  | { kind: "loading" }
  | { kind: "ready"; rid: string; status: RequestStatus; detail: string }
  | { kind: "error"; message: string };

type RequestStatusResponse = {
  rid?: string;
  status: RequestStatus;
  created_at?: string;
  expires_at?: string;
  target_url?: string;
  delivered_at?: string;
};

type WebSocketStatusMessage = {
  type: "status";
  payload: {
    status: RequestStatus;
    timestamp?: string;
    delivered_at?: string;
    expires_at?: string;
  };
};

type WebSocketSessionMessage = {
  type: "session";
  payload: {
    delivered_at?: string;
    status?: RequestStatus;
  };
};

type WebSocketErrorMessage = {
  type: "error";
  payload: {
    code?: string;
    message: string;
  };
};

type WSMessage =
  | WebSocketStatusMessage
  | WebSocketSessionMessage
  | WebSocketErrorMessage;

const API_BASE = "https://api.cookey.sh";
const REQUEST_ID_PATTERN = /^[A-Za-z0-9_-]{6,128}$/;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function isNonEmptyString(value: unknown): value is string {
  return typeof value === "string" && value.trim().length > 0;
}

function isRequestStatus(value: unknown): value is RequestStatus {
  return (
    value === "pending" ||
    value === "ready" ||
    value === "delivered" ||
    value === "expired"
  );
}

function validateRequestId(value: string | null): string {
  const rid = value?.trim() ?? "";
  if (!REQUEST_ID_PATTERN.test(rid)) {
    throw new Error("Missing or invalid request ID.");
  }
  return rid;
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

function isRequestStatusResponse(value: unknown): value is RequestStatusResponse {
  return (
    isRecord(value) &&
    isRequestStatus(value.status) &&
    (value.rid === undefined || isNonEmptyString(value.rid)) &&
    (value.created_at === undefined || isNonEmptyString(value.created_at)) &&
    (value.expires_at === undefined || isNonEmptyString(value.expires_at)) &&
    (value.target_url === undefined || isNonEmptyString(value.target_url)) &&
    (value.delivered_at === undefined || isNonEmptyString(value.delivered_at))
  );
}

function isWebSocketStatusMessage(value: unknown): value is WebSocketStatusMessage {
  return (
    isRecord(value) &&
    value.type === "status" &&
    isRecord(value.payload) &&
    isRequestStatus(value.payload.status) &&
    (value.payload.timestamp === undefined ||
      isNonEmptyString(value.payload.timestamp)) &&
    (value.payload.delivered_at === undefined ||
      isNonEmptyString(value.payload.delivered_at)) &&
    (value.payload.expires_at === undefined ||
      isNonEmptyString(value.payload.expires_at))
  );
}

function isWebSocketSessionMessage(
  value: unknown,
): value is WebSocketSessionMessage {
  return (
    isRecord(value) &&
    value.type === "session" &&
    isRecord(value.payload) &&
    (value.payload.delivered_at === undefined ||
      isNonEmptyString(value.payload.delivered_at)) &&
    (value.payload.status === undefined || isRequestStatus(value.payload.status))
  );
}

function isWebSocketErrorMessage(value: unknown): value is WebSocketErrorMessage {
  return (
    isRecord(value) &&
    value.type === "error" &&
    isRecord(value.payload) &&
    isNonEmptyString(value.payload.message) &&
    (value.payload.code === undefined || isNonEmptyString(value.payload.code))
  );
}

function parseWebSocketMessage(value: unknown): WSMessage | null {
  if (isWebSocketStatusMessage(value)) {
    return value;
  }
  if (isWebSocketSessionMessage(value)) {
    return value;
  }
  if (isWebSocketErrorMessage(value)) {
    return value;
  }
  return null;
}

function getStatusDetail(status: RequestStatus): string {
  switch (status) {
    case "pending":
      return "Waiting for the mobile device to finish logging in.";
    case "ready":
      return "The encrypted session reached the relay. Redirecting to the result page.";
    case "delivered":
      return "The session was delivered successfully. Redirecting to the result page.";
    case "expired":
      return "This request expired before delivery completed.";
  }
}

export default function TestLoginDoPage() {
  const [state, setState] = useState<PageState>({ kind: "loading" });
  const [resultUrl, setResultUrl] = useState<string | null>(null);

  useEffect(() => {
    let pollTimer: number | undefined;
    let disposed = false;
    let latestStatus: RequestStatus = "pending";

    const activeFetchControllers = new Set<AbortController>();
    let redirectTimer: number | undefined;

    const cleanupPolling = () => {
      if (pollTimer !== undefined) {
        window.clearInterval(pollTimer);
        pollTimer = undefined;
      }
    };

    const abortActiveFetches = () => {
      for (const controller of activeFetchControllers) {
        controller.abort();
      }
      activeFetchControllers.clear();
    };

    const rid = (() => {
      try {
        return validateRequestId(
          new URLSearchParams(window.location.search).get("rid"),
        );
      } catch (error) {
        setState({
          kind: "error",
          message:
            error instanceof Error ? error.message : "Invalid request ID.",
        });
        return null;
      }
    })();

    if (!rid) {
      return () => {
        cleanupPolling();
        abortActiveFetches();
        if (redirectTimer !== undefined) {
          window.clearTimeout(redirectTimer);
        }
      };
    }

    const nextResultUrl = `/test-login-result?rid=${encodeURIComponent(rid)}`;
    setResultUrl(nextResultUrl);

    const redirectToResult = () => {
      if (redirectTimer !== undefined) {
        return;
      }
      redirectTimer = window.setTimeout(() => {
        window.location.assign(nextResultUrl);
      }, 450);
    };

    const applyStatus = (nextStatus: RequestStatus) => {
      latestStatus = nextStatus;
      setState({
        kind: "ready",
        rid,
        status: nextStatus,
        detail: getStatusDetail(nextStatus),
      });

      if (nextStatus === "ready" || nextStatus === "delivered" || nextStatus === "expired") {
        cleanupPolling();
        redirectToResult();
      }
    };

    const fetchStatus = async () => {
      const controller = new AbortController();
      activeFetchControllers.add(controller);

      try {
        const response = await fetch(
          `${API_BASE}/v1/requests/${encodeURIComponent(rid)}`,
          { signal: controller.signal },
        );

        if (response.status === 410) {
          applyStatus("expired");
          return;
        }

        const payload = await readJson(response);

        if (!response.ok) {
          throw new Error(`Failed to refresh request status (${response.status}).`);
        }

        if (!isRequestStatusResponse(payload)) {
          throw new Error("API returned an unexpected response shape.");
        }

        applyStatus(payload.status);
      } catch (error) {
        if (
          controller.signal.aborted ||
          disposed ||
          (error instanceof DOMException && error.name === "AbortError")
        ) {
          return;
        }

        setState({
          kind: "error",
          message:
            error instanceof Error
              ? error.message
              : "Unable to read the current request status.",
        });
      } finally {
        activeFetchControllers.delete(controller);
      }
    };

    const startPolling = () => {
      if (pollTimer !== undefined || disposed) {
        return;
      }

      pollTimer = window.setInterval(() => {
        void fetchStatus();
      }, 2000);
    };

    applyStatus("pending");
    void fetchStatus();

    const ws = new WebSocket(
      `wss://api.cookey.sh/v1/requests/${encodeURIComponent(rid)}/ws`,
    );

    ws.onmessage = (event) => {
      let rawMessage: unknown;

      try {
        rawMessage = JSON.parse(String(event.data)) as unknown;
      } catch {
        return;
      }

      const message = parseWebSocketMessage(rawMessage);
      if (!message) {
        return;
      }

      if (message.type === "status") {
        applyStatus(message.payload.status);
        return;
      }

      if (message.type === "session") {
        applyStatus(message.payload.status ?? "delivered");
        return;
      }

      setState({ kind: "error", message: message.payload.message });
    };

    ws.onerror = () => {
      if (latestStatus === "pending") {
        startPolling();
      }
    };

    ws.onclose = () => {
      if (!disposed && latestStatus === "pending") {
        startPolling();
      }
    };

    return () => {
      disposed = true;
      cleanupPolling();
      abortActiveFetches();
      ws.close();
      if (redirectTimer !== undefined) {
        window.clearTimeout(redirectTimer);
      }
    };
  }, []);

  const status = state.kind === "ready" ? state.status : null;
  const detail = state.kind === "ready" ? state.detail : null;

  return (
    <div className="bg-bg text-ink font-sans leading-[1.6] min-h-screen flex flex-col">
      <Nav />

      <main className="flex-1">
        <Container>
          <section className="pt-20 pb-16">
            <div className="mb-7 text-center">
              <Badge>Live Request Status</Badge>
            </div>

            <div className="mx-auto max-w-[620px] text-center">
              <h1 className="mb-[18px] font-bold tracking-[-0.03em] leading-[1.1] text-[clamp(2.2rem,6vw,3.2rem)]">
                Monitor the test login request.
              </h1>
              <p className="mx-auto mb-10 max-w-[540px] text-[1.05rem] text-muted">
                This page listens for relay updates in real time and falls back
                to polling if the socket drops.
              </p>
            </div>

            <div className="mx-auto max-w-[620px] rounded-xl border border-border bg-surface p-6 text-center sm:p-7">
              {state.kind === "error" ? (
                <>
                  <h2 className="text-xl font-semibold tracking-tight">
                    Unable to monitor request
                  </h2>
                  <p className="mt-3 text-sm text-muted">{state.message}</p>
                  <div className="mt-6 flex flex-wrap justify-center gap-3">
                    <ButtonLink href="/test-login-instruction" variant="primary">
                      Start another request
                    </ButtonLink>
                    <ButtonLink href="/" variant="secondary">
                      Back to home
                    </ButtonLink>
                  </div>
                </>
              ) : (
                <>
                  <div className="mb-5 flex justify-center">
                    <div
                      aria-hidden="true"
                      className={`h-10 w-10 rounded-full border-[3px] ${
                        status === "expired"
                          ? "border-border"
                          : "animate-spin border-border border-t-accent"
                      }`}
                    />
                  </div>

                  <div role="status" aria-live="polite">
                    <h2 className="text-xl font-semibold tracking-tight">
                      {status === "pending" || state.kind === "loading"
                        ? "Waiting for device login"
                        : status === "ready"
                          ? "Session uploaded"
                          : status === "delivered"
                            ? "Session delivered"
                            : "Request expired"}
                    </h2>

                    <p className="mt-3 text-sm text-muted">
                      {state.kind === "loading"
                        ? "Preparing the request monitor."
                        : detail}
                    </p>
                  </div>

                  {state.kind === "ready" && (
                    <dl className="mt-6 space-y-4 rounded-xl border border-border bg-terminal-bg p-5 text-left text-sm">
                      <div>
                        <dt className="text-[11px] uppercase tracking-[0.18em] text-muted">
                          Request ID
                        </dt>
                        <dd className="mt-1 font-mono break-all text-ink">
                          {state.rid}
                        </dd>
                      </div>
                      <div>
                        <dt className="text-[11px] uppercase tracking-[0.18em] text-muted">
                          Status
                        </dt>
                        <dd className="mt-1 text-ink capitalize">{state.status}</dd>
                      </div>
                    </dl>
                  )}

                  <div className="mt-6 flex flex-wrap justify-center gap-3">
                    {resultUrl && (
                      <ButtonLink href={resultUrl} variant="secondary">
                        Result page
                      </ButtonLink>
                    )}
                    <ButtonLink href="/test-login-instruction" variant="secondary">
                      New request
                    </ButtonLink>
                  </div>
                </>
              )}
            </div>
          </section>
        </Container>
      </main>

      <Footer rightLink={{ label: "Back to Home", href: "/" }} />
    </div>
  );
}
