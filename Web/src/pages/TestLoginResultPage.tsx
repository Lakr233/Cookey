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
      return "Scanning";
    case "ready":
      return "Success";
    case "delivered":
      return "Complete";
    case "expired":
      return "Expired";
  }
}

function getStatusHeading(status: RequestStatus): string {
  switch (status) {
    case "pending":
      return "Login still in progress";
    case "ready":
    case "delivered":
      return "Test login completed";
    case "expired":
      return "Request expired";
  }
}

function getStatusDetail(status: RequestStatus): string {
  switch (status) {
    case "pending":
      return "The mobile login is still in progress. This page will update automatically.";
    case "ready":
    case "delivered":
      return "Cookey successfully relayed the encrypted session. This confirms the App Store review flow works end-to-end.";
    case "expired":
      return "The request expired before completion. You can start a new test.";
  }
}

function ResultIcon({ status }: { status: RequestStatus | null }) {
  if (status === "expired") {
    return (
      <div className="relative flex items-center justify-center">
        <div className="w-20 h-20 rounded-full border-2 border-border bg-surface flex items-center justify-center">
          <svg
            className="w-10 h-10 text-muted"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
          >
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              strokeWidth={2}
              d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"
            />
          </svg>
        </div>
      </div>
    );
  }

  if (status === "ready" || status === "delivered") {
    return (
      <div className="relative flex items-center justify-center animate-scale-in">
        <div className="w-20 h-20 rounded-full border-2 border-accent bg-accent/10 shadow-[0_0_32px_rgba(74,222,128,0.12)] flex items-center justify-center">
          <svg
            className="w-10 h-10 text-accent"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
          >
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              strokeWidth={2}
              d="M5 13l4 4L19 7"
            />
          </svg>
        </div>
      </div>
    );
  }

  // Pending - radar pulse
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

export default function TestLoginResultPage() {
  const [state, setState] = useState<PageState>({ kind: "loading" });

  useEffect(() => {
    let pollTimer: number | undefined;
    let activeController: AbortController | null = null;
    let disposed = false;

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
              : "Missing or invalid request ID.",
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
          message:
            error instanceof Error
              ? error.message
              : "Unable to load request result.",
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
  const status = result?.status ?? null;

  return (
    <div className="bg-bg text-ink font-sans leading-[1.6] min-h-screen flex flex-col">
      <Nav />

      <main className="flex-1">
        <Container>
          <section className="pt-20 pb-16">
            <div className="mb-7 text-center animate-[fade-in_0.4s_ease-out_both]">
              <Badge>Test Login Result</Badge>
            </div>

            <div className="mx-auto max-w-[620px] text-center">
              <h1 className="mb-[18px] font-bold tracking-[-0.03em] leading-[1.1] text-[clamp(2.2rem,6vw,3.2rem)] animate-[fade-in_0.4s_ease-out_75ms_both]">
                {status
                  ? getStatusHeading(status)
                  : "Review the final request state."}
              </h1>
              <p className="mx-auto mb-8 max-w-[540px] text-[1.05rem] text-muted animate-[fade-in_0.4s_ease-out_150ms_both]">
                {status
                  ? getStatusDetail(status)
                  : "Loading the relay status for this request."}
              </p>
            </div>

            <div className="mb-10 animate-[fade-in_0.4s_ease-out_225ms_both]">
              <StepProgress current={3} />
            </div>

            <div className="mx-auto max-w-[620px] rounded-xl border border-border bg-surface p-6 sm:p-7 animate-[fade-in_0.4s_ease-out_300ms_both]">
              {state.kind === "loading" && (
                <div className="text-center" role="status" aria-live="polite">
                  <div className="mb-5 flex justify-center">
                    <div
                      aria-hidden="true"
                      className="h-10 w-10 animate-spin rounded-full border-[3px] border-border border-t-accent"
                    />
                  </div>
                  <h2 className="text-xl font-semibold tracking-tight">
                    Loading request result
                  </h2>
                  <p className="mt-3 text-sm text-muted">
                    Fetching the latest state from the relay.
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
                    <ButtonLink
                      href="/test-login-instruction"
                      variant="primary"
                    >
                      Start another request
                    </ButtonLink>
                    <ButtonLink href="/" variant="secondary">
                      Back to home
                    </ButtonLink>
                  </div>
                </div>
              )}

              {result && (
                <div
                  className="flex flex-col items-center gap-5"
                  role="status"
                  aria-live="polite"
                >
                  <ResultIcon status={status} />

                  <div className="text-center">
                    {status && (
                      <div className="mb-3">
                        <Badge>{getStatusBadgeCopy(status)}</Badge>
                      </div>
                    )}
                  </div>

                  <div className="mt-4 flex flex-wrap justify-center gap-3">
                    <ButtonLink
                      href="/test-login-instruction"
                      variant="primary"
                    >
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
