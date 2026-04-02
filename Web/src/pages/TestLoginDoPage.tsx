import { useEffect, useState } from "react";
import Nav from "../components/Nav";
import Footer from "../components/Footer";
import Container from "../components/Container";
import Badge from "../components/Badge";
import { ButtonLink } from "../components/Button";
import {
  REQUEST_POLL_INTERVAL_MS,
  fetchRequestStatus,
  type RequestStatus,
  validateRequestId,
} from "../lib/testLogin";

type PageState =
  | { kind: "loading" }
  | { kind: "ready"; rid: string; status: RequestStatus; detail: string }
  | { kind: "error"; message: string };

function getStatusDetail(status: RequestStatus): string {
  switch (status) {
    case "pending":
      return "Waiting for the mobile device to finish logging in.";
    case "ready":
      return "The encrypted session reached the relay successfully. Redirecting to the result page.";
    case "delivered":
      return "The relay marked the session as delivered. Redirecting to the result page.";
    case "expired":
      return "This request expired before the upload completed.";
  }
}

export default function TestLoginDoPage() {
  const [state, setState] = useState<PageState>({ kind: "loading" });
  const [resultUrl, setResultUrl] = useState<string | null>(null);

  useEffect(() => {
    let pollTimer: number | undefined;
    let redirectTimer: number | undefined;
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

    const nextResultUrl = `/test-login-result?rid=${encodeURIComponent(rid)}`;
    setResultUrl(nextResultUrl);

    const stopPolling = () => {
      if (pollTimer !== undefined) {
        window.clearInterval(pollTimer);
        pollTimer = undefined;
      }
    };

    const redirectToResult = () => {
      if (redirectTimer !== undefined) {
        return;
      }
      redirectTimer = window.setTimeout(() => {
        window.location.assign(nextResultUrl);
      }, 600);
    };

    const applyStatus = (status: RequestStatus) => {
      setState({
        kind: "ready",
        detail: getStatusDetail(status),
        rid,
        status,
      });

      if (status !== "pending") {
        stopPolling();
        redirectToResult();
      }
    };

    const loadStatus = async () => {
      activeController?.abort();
      const controller = new AbortController();
      activeController = controller;

      try {
        const response = await fetchRequestStatus(rid, controller.signal);
        if (!disposed) {
          applyStatus(response.status);
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
          message: error instanceof Error ? error.message : "Unable to read request status.",
        });
        stopPolling();
      } finally {
        if (activeController === controller) {
          activeController = null;
        }
      }
    };

    applyStatus("pending");
    void loadStatus();
    pollTimer = window.setInterval(() => {
      void loadStatus();
    }, REQUEST_POLL_INTERVAL_MS);

    return () => {
      disposed = true;
      activeController?.abort();
      stopPolling();
      if (redirectTimer !== undefined) {
        window.clearTimeout(redirectTimer);
      }
    };
  }, []);

  const status = state.kind === "ready" ? state.status : null;

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
                This page polls the relay status without consuming the one-shot session payload.
              </p>
            </div>

            <div className="mx-auto max-w-[620px] rounded-xl border border-border bg-surface p-6 text-center sm:p-7">
              {state.kind === "error" ? (
                <>
                  <h2 className="text-xl font-semibold tracking-tight">Unable to monitor request</h2>
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
                      {state.kind === "loading" || status === "pending"
                        ? "Waiting for device login"
                        : status === "ready"
                          ? "Session uploaded"
                          : status === "delivered"
                            ? "Session delivered"
                            : "Request expired"}
                    </h2>
                    <p className="mt-3 text-sm text-muted">
                      {state.kind === "loading" ? "Preparing the request monitor." : state.detail}
                    </p>
                  </div>

                  {state.kind === "ready" && (
                    <dl className="mt-6 space-y-4 rounded-xl border border-border bg-terminal-bg p-5 text-left text-sm">
                      <div>
                        <dt className="text-[11px] uppercase tracking-[0.18em] text-muted">Request ID</dt>
                        <dd className="mt-1 font-mono break-all text-ink">{state.rid}</dd>
                      </div>
                      <div>
                        <dt className="text-[11px] uppercase tracking-[0.18em] text-muted">Status</dt>
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
