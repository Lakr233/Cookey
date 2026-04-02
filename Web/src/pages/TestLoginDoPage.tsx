import { useEffect, useState } from "react";
import Nav from "../components/Nav";
import Footer from "../components/Footer";
import Container from "../components/Container";
import Badge from "../components/Badge";
import StepProgress from "../components/StepProgress";
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

function getStatusBadge(status: RequestStatus): string {
  switch (status) {
    case "pending":
      return "Scanning";
    case "ready":
      return "Ready";
    case "delivered":
      return "Complete";
    case "expired":
      return "Expired";
  }
}

function StatusIndicator({ status }: { status: RequestStatus | null }) {
  if (status === "expired") {
    return (
      <div className="relative mx-auto h-24 w-24 flex items-center justify-center">
        <div className="absolute inset-0 rounded-full border border-border bg-surface" />
        <div className="relative flex items-center justify-center">
          <svg className="w-8 h-8 text-muted" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
          </svg>
        </div>
      </div>
    );
  }

  if (status === "ready" || status === "delivered") {
    return (
      <div className="relative mx-auto h-24 w-24 flex items-center justify-center">
        <div className="absolute inset-0 rounded-full border-2 border-accent bg-accent/10 shadow-[0_0_32px_rgba(74,222,128,0.12)]" />
        <div className="relative flex items-center justify-center">
          <svg className="w-10 h-10 text-accent" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
          </svg>
        </div>
      </div>
    );
  }

  // Pending / loading - radar pulse
  return (
    <div className="relative mx-auto h-24 w-24">
      <div className="absolute inset-0 rounded-full border border-accent/20 animate-ping-slow" />
      <div className="absolute inset-3 rounded-full border border-accent/30 animate-pulse" />
      <div className="absolute inset-6 rounded-full bg-accent/10 flex items-center justify-center">
        <div className="h-3 w-3 rounded-full bg-accent animate-pulse" />
      </div>
    </div>
  );
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
  const isTerminal = status === "ready" || status === "delivered" || status === "expired";

  return (
    <div className="bg-bg text-ink font-sans leading-[1.6] min-h-screen flex flex-col">
      <Nav />

      <main className="flex-1">
        <Container>
          <section className="pt-20 pb-16">
            <div className="mb-7 text-center animate-[fade-in_0.4s_ease-out_both]">
              <Badge>Live Request Status</Badge>
            </div>

            <div className="mx-auto max-w-[620px] text-center">
              <h1 className="mb-[18px] font-bold tracking-[-0.03em] leading-[1.1] text-[clamp(2.2rem,6vw,3.2rem)] animate-[fade-in_0.4s_ease-out_75ms_both]">
                Monitor the test login request.
              </h1>
              <p className="mx-auto mb-8 max-w-[540px] text-[1.05rem] text-muted animate-[fade-in_0.4s_ease-out_150ms_both]">
                This page polls the relay status without consuming the one-shot session payload.
              </p>
            </div>

            <div className="mb-10 animate-[fade-in_0.4s_ease-out_225ms_both]">
              <StepProgress current={2} />
            </div>

            <div className="mx-auto max-w-[620px] rounded-xl border border-border bg-surface p-6 sm:p-7 animate-[fade-in_0.4s_ease-out_300ms_both]">
              {state.kind === "error" ? (
                <div className="text-center" role="status" aria-live="polite">
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
                </div>
              ) : (
                <div className="flex flex-col items-center gap-5">
                  <div className="animate-[fade-in_0.4s_ease-out_both]">
                    <StatusIndicator status={status} />
                  </div>

                  <div className="text-center" role="status" aria-live="polite">
                    {status && (
                      <div className="mb-3">
                        <Badge>{getStatusBadge(status)}</Badge>
                      </div>
                    )}
                    <h2 className="text-xl font-semibold tracking-tight">
                      {state.kind === "loading" || status === "pending"
                        ? "Waiting for device login"
                        : status === "ready"
                          ? "Session uploaded"
                          : status === "delivered"
                            ? "Session delivered"
                            : "Request expired"}
                    </h2>
                    <p className="mt-3 text-sm text-muted max-w-[400px]">
                      {state.kind === "loading" ? "Preparing the request monitor." : state.detail}
                    </p>
                  </div>

                  {isTerminal && (
                    <div className="mt-4 flex flex-wrap justify-center gap-3 animate-[fade-in_0.4s_ease-out_both]">
                      {resultUrl && (
                        <ButtonLink href={resultUrl} variant="primary">
                          View result →
                        </ButtonLink>
                      )}
                      <ButtonLink href="/test-login-instruction" variant="secondary">
                        New request
                      </ButtonLink>
                    </div>
                  )}
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