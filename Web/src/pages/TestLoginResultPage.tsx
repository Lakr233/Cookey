import { useEffect, useState } from "react";
import Nav from "../components/Nav";
import Footer from "../components/Footer";
import Container from "../components/Container";
import Badge from "../components/Badge";
import { ButtonLink } from "../components/Button";
import {
  REQUEST_POLL_INTERVAL_MS,
  fetchRequestStatus,
  formatDateTime,
  type RequestStatus,
  type RequestStatusResponse,
  validateRequestId,
} from "../lib/testLogin";

type PageState =
  | { kind: "loading" }
  | { kind: "ready"; result: RequestStatusResponse }
  | { kind: "error"; message: string };

function getStatusBadgeCopy(status: RequestStatus): string {
  switch (status) {
    case "pending":
      return "Waiting for Device";
    case "ready":
      return "Session Ready";
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
      return "Test login succeeded";
    case "delivered":
      return "Relay delivery completed";
    case "expired":
      return "Request expired";
  }
}

function getStatusDetail(status: RequestStatus): string {
  switch (status) {
    case "pending":
      return "The mobile login is still in progress. Refresh will happen automatically while this page is open.";
    case "ready":
      return "Cookey uploaded the encrypted session to the relay successfully. For App Store review, this is the expected success state.";
    case "delivered":
      return "A consumer claimed the encrypted session and the relay marked the request as delivered.";
    case "expired":
      return "The request expired before the relay reached a successful terminal state.";
  }
}

export default function TestLoginResultPage() {
  const [state, setState] = useState<PageState>({ kind: "loading" });

  useEffect(() => {
    let pollTimer: number | undefined;
    let activeController: AbortController | null = null;
    let disposed = false;

    const rid = (() => {
      try {
        return validateRequestId(new URLSearchParams(window.location.search).get("rid"));
      } catch (error) {
        setState({
          kind: "error",
          message: error instanceof Error ? error.message : "Missing or invalid request ID.",
        });
        return null;
      }
    })();

    if (!rid) {
      return () => undefined;
    }

    const stopPolling = () => {
      if (pollTimer !== undefined) {
        window.clearInterval(pollTimer);
        pollTimer = undefined;
      }
    };

    const loadResult = async () => {
      activeController?.abort();
      const controller = new AbortController();
      activeController = controller;

      try {
        const result = await fetchRequestStatus(rid, controller.signal);
        if (disposed) {
          return;
        }

        setState({ kind: "ready", result });
        if (result.status !== "pending") {
          stopPolling();
        }
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
          message: error instanceof Error ? error.message : "Unable to load request result.",
        });
        stopPolling();
      } finally {
        if (activeController === controller) {
          activeController = null;
        }
      }
    };

    void loadResult();
    pollTimer = window.setInterval(() => {
      void loadResult();
    }, REQUEST_POLL_INTERVAL_MS);

    return () => {
      disposed = true;
      activeController?.abort();
      stopPolling();
    };
  }, []);

  const result = state.kind === "ready" ? state.result : null;

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
                The result page summarizes the relay status returned by the API for this request.
              </p>
            </div>

            <div className="mx-auto max-w-[620px] rounded-xl border border-border bg-surface p-6 sm:p-7">
              {state.kind === "loading" && (
                <div className="text-center" role="status" aria-live="polite">
                  <div className="mb-5 flex justify-center">
                    <div aria-hidden="true" className="h-10 w-10 animate-spin rounded-full border-[3px] border-border border-t-accent" />
                  </div>
                  <h2 className="text-xl font-semibold tracking-tight">Loading request result</h2>
                  <p className="mt-3 text-sm text-muted">Fetching the latest state from the relay.</p>
                </div>
              )}

              {state.kind === "error" && (
                <div className="text-center" role="status" aria-live="polite">
                  <h2 className="text-xl font-semibold tracking-tight">Unable to load request result</h2>
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

              {result && (
                <div className="text-center" role="status" aria-live="polite">
                  <h2 className="text-xl font-semibold tracking-tight">
                    {getStatusHeading(result.status)}
                  </h2>
                  <div className="mt-4">
                    <Badge>{getStatusBadgeCopy(result.status)}</Badge>
                  </div>
                  <p className="mx-auto mt-4 max-w-[520px] text-sm text-muted">
                    {getStatusDetail(result.status)}
                  </p>

                  <dl className="mt-8 space-y-4 rounded-xl border border-border bg-terminal-bg p-5 text-left text-sm">
                    <div>
                      <dt className="text-[11px] uppercase tracking-[0.18em] text-muted">Request ID</dt>
                      <dd className="mt-1 font-mono break-all text-ink">{result.rid}</dd>
                    </div>
                    <div>
                      <dt className="text-[11px] uppercase tracking-[0.18em] text-muted">Status</dt>
                      <dd className="mt-1 text-ink capitalize">{result.status}</dd>
                    </div>
                    <div>
                      <dt className="text-[11px] uppercase tracking-[0.18em] text-muted">Created At</dt>
                      <dd className="mt-1 text-ink">{formatDateTime(result.created_at)}</dd>
                    </div>
                    <div>
                      <dt className="text-[11px] uppercase tracking-[0.18em] text-muted">Expires At</dt>
                      <dd className="mt-1 text-ink">{formatDateTime(result.expires_at)}</dd>
                    </div>
                    <div>
                      <dt className="text-[11px] uppercase tracking-[0.18em] text-muted">Target URL</dt>
                      <dd className="mt-1 font-mono break-all text-ink">{result.target_url}</dd>
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
