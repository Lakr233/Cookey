import { useEffect, useState } from "react";
import Nav from "../components/Nav";
import Footer from "../components/Footer";
import Container from "../components/Container";
import Badge from "../components/Badge";
import { ButtonLink } from "../components/Button";

type RequestStatus = "pending" | "ready" | "delivered" | "expired";

interface RequestResult {
  rid: string;
  status: RequestStatus;
  created_at: string;
  expires_at: string;
  target_url: string;
  delivered_at?: string;
}

type PageState =
  | { kind: "loading" }
  | { kind: "ready"; result: RequestResult }
  | { kind: "error"; message: string };

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
    throw new Error("Request ID not found in URL.");
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

function isRequestResult(value: unknown): value is RequestResult {
  return (
    isRecord(value) &&
    isNonEmptyString(value.rid) &&
    isRequestStatus(value.status) &&
    isNonEmptyString(value.created_at) &&
    isNonEmptyString(value.expires_at) &&
    isNonEmptyString(value.target_url) &&
    (value.delivered_at === undefined || isNonEmptyString(value.delivered_at))
  );
}

function formatDateTime(value: string): string {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return value;
  }
  return date.toLocaleString();
}

function getStatusBadgeCopy(status: RequestStatus): string {
  switch (status) {
    case "pending":
      return "Waiting for Device";
    case "ready":
      return "Session Uploaded";
    case "delivered":
      return "Relay Complete";
    case "expired":
      return "Timed Out";
  }
}

function getStatusHeading(status: RequestStatus): string {
  switch (status) {
    case "pending":
      return "Login still in progress";
    case "ready":
      return "Session ready on the relay";
    case "delivered":
      return "Test login completed";
    case "expired":
      return "Request expired";
  }
}

function getStatusDetail(status: RequestStatus): string {
  switch (status) {
    case "pending":
      return "The mobile login is still in progress. Keep the page open or retry after the device finishes.";
    case "ready":
      return "The encrypted session reached the relay and is waiting to be claimed.";
    case "delivered":
      return "The relay marked the session as delivered successfully.";
    case "expired":
      return "The request expired before the full delivery flow completed.";
  }
}

export default function TestLoginResultPage() {
  const [state, setState] = useState<PageState>({ kind: "loading" });

  useEffect(() => {
    let pollTimer: number | undefined;
    let disposed = false;
    let activeController: AbortController | null = null;
    let latestStatus: RequestStatus | null = null;

    const rid = (() => {
      try {
        return validateRequestId(
          new URLSearchParams(window.location.search).get("rid"),
        );
      } catch (error) {
        setState({
          kind: "error",
          message:
            error instanceof Error
              ? error.message
              : "Request ID not found in URL.",
        });
        return null;
      }
    })();

    if (!rid) {
      return () => {
        disposed = true;
        activeController?.abort();
        if (pollTimer !== undefined) {
          window.clearInterval(pollTimer);
        }
      };
    }

    const loadResult = async () => {
      activeController?.abort();
      const controller = new AbortController();
      activeController = controller;

      try {
        const response = await fetch(
          `${API_BASE}/v1/requests/${encodeURIComponent(rid)}`,
          { signal: controller.signal },
        );

        if (response.status === 410) {
          latestStatus = "expired";
          setState({
            kind: "ready",
            result: {
              rid,
              status: "expired",
              created_at: "",
              expires_at: "",
              target_url: "",
            },
          });
          return;
        }

        const payload = await readJson(response);

        if (!response.ok) {
          throw new Error(`Failed to fetch request details (${response.status}).`);
        }

        if (!isRequestResult(payload)) {
          throw new Error("API returned an unexpected response shape.");
        }

        latestStatus = payload.status;
        setState({ kind: "ready", result: payload });
      } catch (error) {
        if (
          disposed ||
          controller.signal.aborted ||
          (error instanceof DOMException && error.name === "AbortError")
        ) {
          return;
        }

        setState({
          kind: "error",
          message:
            error instanceof Error ? error.message : "An error occurred.",
        });
      } finally {
        if (activeController === controller) {
          activeController = null;
        }
      }
    };

    void loadResult();

    pollTimer = window.setInterval(() => {
      if (disposed) {
        return;
      }

      if (latestStatus === "delivered" || latestStatus === "expired") {
        if (pollTimer !== undefined) {
          window.clearInterval(pollTimer);
        }
        return;
      }

      void loadResult();
    }, 3000);

    return () => {
      disposed = true;
      activeController?.abort();
      if (pollTimer !== undefined) {
        window.clearInterval(pollTimer);
      }
    };
  }, []);

  const result = state.kind === "ready" ? state.result : null;
  const status = result?.status ?? null;

  return (
    <div className="bg-bg text-ink font-sans leading-[1.6] min-h-screen flex flex-col">
      <Nav />

      <main className="flex-1">
        <Container>
          <section className="pt-20 pb-16">
            <div className="mb-7 text-center">
              <Badge>Test Login Result</Badge>
            </div>

            <div className="mx-auto max-w-[620px] text-center">
              <h1 className="mb-[18px] font-bold tracking-[-0.03em] leading-[1.1] text-[clamp(2.2rem,6vw,3.2rem)]">
                Review the final request state.
              </h1>
              <p className="mx-auto mb-10 max-w-[540px] text-[1.05rem] text-muted">
                The result page summarizes the relay status and the request
                metadata returned by the API.
              </p>
            </div>

            <div className="mx-auto max-w-[620px] rounded-xl border border-border bg-surface p-6 sm:p-7">
              {state.kind === "loading" && (
                <div className="text-center" role="status" aria-live="polite">
                  <div className="mb-5 flex justify-center">
                    <div aria-hidden="true" className="h-10 w-10 animate-spin rounded-full border-[3px] border-border border-t-accent" />
                  </div>
                  <h2 className="text-xl font-semibold tracking-tight">
                    Loading request result
                  </h2>
                  <p className="mt-3 text-sm text-muted">
                    Fetching the latest relay state and request metadata.
                  </p>
                </div>
              )}

              {state.kind === "error" && (
                <div className="text-center" role="status" aria-live="polite">
                  <h2 className="text-xl font-semibold tracking-tight">
                    Unable to load request result
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
                </div>
              )}

              {result && status && (
                <div className="text-center" role="status" aria-live="polite">
                  <h2 className="text-xl font-semibold tracking-tight">
                    {getStatusHeading(status)}
                  </h2>
                  <div className="mt-4">
                    <Badge>{getStatusBadgeCopy(status)}</Badge>
                  </div>
                  <p className="mx-auto mt-4 max-w-[520px] text-sm text-muted">
                    {getStatusDetail(status)}
                  </p>

                  <dl className="mt-8 space-y-4 rounded-xl border border-border bg-terminal-bg p-5 text-left text-sm">
                    <div>
                      <dt className="text-[11px] uppercase tracking-[0.18em] text-muted">
                        Request ID
                      </dt>
                      <dd className="mt-1 font-mono break-all text-ink">
                        {result.rid}
                      </dd>
                    </div>
                    <div>
                      <dt className="text-[11px] uppercase tracking-[0.18em] text-muted">
                        Status
                      </dt>
                      <dd className="mt-1 text-ink capitalize">{result.status}</dd>
                    </div>
                    <div>
                      <dt className="text-[11px] uppercase tracking-[0.18em] text-muted">
                        Created At
                      </dt>
                      <dd className="mt-1 text-ink">
                        {result.created_at ? formatDateTime(result.created_at) : "Unavailable"}
                      </dd>
                    </div>
                    <div>
                      <dt className="text-[11px] uppercase tracking-[0.18em] text-muted">
                        Expires At
                      </dt>
                      <dd className="mt-1 text-ink">
                        {result.expires_at ? formatDateTime(result.expires_at) : "Unavailable"}
                      </dd>
                    </div>
                    <div>
                      <dt className="text-[11px] uppercase tracking-[0.18em] text-muted">
                        Delivered At
                      </dt>
                      <dd className="mt-1 text-ink">
                        {result.delivered_at
                          ? formatDateTime(result.delivered_at)
                          : "Not delivered yet"}
                      </dd>
                    </div>
                    <div>
                      <dt className="text-[11px] uppercase tracking-[0.18em] text-muted">
                        Target URL
                      </dt>
                      <dd className="mt-1 font-mono break-all text-ink">
                        {result.target_url || "Unavailable"}
                      </dd>
                    </div>
                  </dl>

                  <div className="mt-6 flex flex-wrap justify-center gap-3">
                    <ButtonLink href="/test-login-instruction" variant="primary">
                      Run another test
                    </ButtonLink>
                    <ButtonLink href="/" variant="secondary">
                      Back to home
                    </ButtonLink>
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
