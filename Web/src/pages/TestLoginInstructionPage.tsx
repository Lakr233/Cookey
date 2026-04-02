import { useEffect, useState } from "react";
import Nav from "../components/Nav";
import Footer from "../components/Footer";
import Container from "../components/Container";
import Badge from "../components/Badge";
import QrCode from "../components/QrCode";
import DetailsDisclosure from "../components/DetailsDisclosure";
import { Button, ButtonLink } from "../components/Button";
import {
  createLoginRequest,
  fetchRequestStatus,
  formatDateTime,
  REQUEST_POLL_INTERVAL_MS,
  type LoginRequestState,
  type RequestStatus,
  type RequestStatusResponse,
} from "../lib/testLogin";

type PageState =
  | { kind: "loading" }
  | { kind: "ready"; request: LoginRequestState }
  | { kind: "error"; message: string };

function getResultHeading(status: RequestStatus): string {
  switch (status) {
    case "ready":
    case "delivered":
      return "Login succeeded";
    case "expired":
      return "Request expired";
    case "pending":
      return "Still waiting";
  }
}

function getResultDetail(status: RequestStatus): string {
  switch (status) {
    case "ready":
    case "delivered":
      return "Session relayed successfully.";
    case "expired":
      return "Expired before the session was uploaded.";
    case "pending":
      return "Still waiting for the device.";
  }
}

function ResultIcon({ status }: { status: RequestStatus }) {
  if (status === "expired") {
    return (
      <div className="mx-auto flex h-20 w-20 items-center justify-center rounded-full border-2 border-border bg-surface">
        <svg className="h-10 w-10 text-muted" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
        </svg>
      </div>
    );
  }

  return (
    <div className="mx-auto flex h-20 w-20 items-center justify-center rounded-full border-2 border-accent bg-accent/10 shadow-[0_0_32px_rgba(74,222,128,0.12)] animate-scale-in">
      <svg className="h-10 w-10 text-accent" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
      </svg>
    </div>
  );
}

function ResultModal({
  result,
  onClose,
}: {
  result: RequestStatusResponse;
  onClose: () => void;
}) {
  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm p-5 animate-[fade-in_0.2s_ease-out_both]"
      onClick={(e) => { if (e.target === e.currentTarget) onClose(); }}
    >
      <div className="w-full max-w-[440px] rounded-2xl border border-border bg-surface p-7 animate-[scale-in_0.3s_ease-out_both]">
        <div className="flex flex-col items-center gap-5">
          <ResultIcon status={result.status} />

          <div className="text-center">
            <h2 className="text-xl font-semibold tracking-tight">
              {getResultHeading(result.status)}
            </h2>
            <p className="mt-2 text-sm text-muted max-w-[360px]">
              {getResultDetail(result.status)}
            </p>
          </div>

          <DetailsDisclosure title="Request Metadata">
            <dl className="space-y-3 text-sm">
              <div>
                <dt className="text-[11px] uppercase tracking-[0.18em] text-muted">Request ID</dt>
                <dd className="mt-1 font-mono break-all text-ink">{result.rid}</dd>
              </div>
              <div>
                <dt className="text-[11px] uppercase tracking-[0.18em] text-muted">Status</dt>
                <dd className="mt-1 text-ink capitalize">{result.status}</dd>
              </div>
              {result.created_at && (
                <div>
                  <dt className="text-[11px] uppercase tracking-[0.18em] text-muted">Created</dt>
                  <dd className="mt-1 text-ink">{formatDateTime(result.created_at)}</dd>
                </div>
              )}
              {result.expires_at && (
                <div>
                  <dt className="text-[11px] uppercase tracking-[0.18em] text-muted">Expires</dt>
                  <dd className="mt-1 text-ink">{formatDateTime(result.expires_at)}</dd>
                </div>
              )}
            </dl>
          </DetailsDisclosure>

          <button
            type="button"
            onClick={onClose}
            className="mt-1 w-full rounded-lg bg-ink px-4 py-3 text-sm font-semibold text-bg transition-opacity hover:opacity-90"
          >
            Close
          </button>
        </div>
      </div>
    </div>
  );
}

export default function TestLoginInstructionPage() {
  const [state, setState] = useState<PageState>({ kind: "loading" });
  const [attempt, setAttempt] = useState(0);
  const [result, setResult] = useState<RequestStatusResponse | null>(null);
  const [showResult, setShowResult] = useState(false);

  // Create request
  useEffect(() => {
    const controller = new AbortController();
    setState({ kind: "loading" });
    setResult(null);
    setShowResult(false);

    void createLoginRequest(controller.signal)
      .then((request) => {
        if (!controller.signal.aborted) {
          setState({ kind: "ready", request });
        }
      })
      .catch((error: unknown) => {
        if (!controller.signal.aborted) {
          setState({
            kind: "error",
            message: error instanceof Error ? error.message : "Failed to create login request.",
          });
        }
      });

    return () => controller.abort();
  }, [attempt]);

  // Poll status once request is ready
  useEffect(() => {
    if (state.kind !== "ready") return;

    const { rid } = state.request;
    let pollTimer: number | undefined;
    let activeController: AbortController | null = null;
    let disposed = false;

    const stopPolling = () => {
      if (pollTimer !== undefined) {
        window.clearInterval(pollTimer);
        pollTimer = undefined;
      }
    };

    const poll = async () => {
      activeController?.abort();
      const controller = new AbortController();
      activeController = controller;

      try {
        const response = await fetchRequestStatus(rid, controller.signal);
        if (disposed) return;

        if (response.status !== "pending") {
          stopPolling();
          setResult(response);
          setShowResult(true);
        }
      } catch (error) {
        if (disposed || (error instanceof DOMException && error.name === "AbortError")) return;
        // Silently retry on next interval
      } finally {
        if (activeController === controller) activeController = null;
      }
    };

    void poll();
    pollTimer = window.setInterval(() => void poll(), REQUEST_POLL_INTERVAL_MS);

    return () => {
      disposed = true;
      activeController?.abort();
      stopPolling();
    };
  }, [state]);

  return (
    <div className="bg-bg text-ink font-sans leading-[1.6] min-h-screen flex flex-col">
      <Nav />

      <main className="flex-1">
        <Container>
          <section className="pt-20 pb-16">
            <div className="mb-7 text-center animate-[fade-in_0.4s_ease-out_both]">
              <Badge>App Store Review Test</Badge>
            </div>

            <div className="mx-auto max-w-[620px] text-center">
              <h1 className="mb-[18px] font-bold tracking-[-0.03em] leading-[1.1] text-[clamp(2.2rem,6vw,3.2rem)] animate-[fade-in_0.4s_ease-out_75ms_both]">
                Test the login flow.
              </h1>
              <p className="mx-auto mb-10 max-w-[540px] text-[1.05rem] text-muted animate-[fade-in_0.4s_ease-out_150ms_both]">
                Scan with Cookey, log in, tap send. Result appears here.
              </p>
            </div>

            <div className="mx-auto max-w-[620px] animate-[fade-in_0.4s_ease-out_225ms_both]">
              {state.kind === "loading" && (
                <div className="text-center" role="status" aria-live="polite">
                  <div className="mb-5 flex justify-center">
                    <div aria-hidden="true" className="h-10 w-10 animate-spin rounded-full border-[3px] border-border border-t-accent" />
                  </div>
                  <p className="text-sm text-muted">Creating a test request.</p>
                </div>
              )}

              {state.kind === "error" && (
                <div className="text-center" role="status" aria-live="polite">
                  <p className="text-sm text-muted">{state.message}</p>
                  <div className="mt-6">
                    <Button variant="primary" onClick={() => setAttempt((c) => c + 1)}>
                      Retry
                    </Button>
                  </div>
                </div>
              )}

              {state.kind === "ready" && (
                <div className="flex flex-col items-center gap-5">
                  <div className="rounded-2xl bg-terminal-bg p-8 animate-[fade-in_0.4s_ease-out_100ms_both]">
                    <QrCode value={state.request.deepLink} size={220} />
                  </div>

                  <p className="text-sm text-muted text-center animate-[fade-in_0.4s_ease-out_175ms_both]">
                    Scan with Cookey on your device
                  </p>

                  <div className="animate-[fade-in_0.4s_ease-out_250ms_both]">
                    <ButtonLink href={state.request.deepLink} variant="secondary">
                      Open in Cookey
                    </ButtonLink>
                  </div>

                  <div className="w-full mt-4 animate-[fade-in_0.4s_ease-out_325ms_both]">
                    <DetailsDisclosure title="Request Details">
                      <dl className="space-y-3 text-sm">
                        <div>
                          <dt className="text-[11px] uppercase tracking-[0.18em] text-muted">Request ID</dt>
                          <dd className="mt-1 font-mono break-all text-ink">{state.request.rid}</dd>
                        </div>
                        <div>
                          <dt className="text-[11px] uppercase tracking-[0.18em] text-muted">Relay server</dt>
                          <dd className="mt-1 font-mono break-all text-ink">{state.request.serverUrl}</dd>
                        </div>
                        <div>
                          <dt className="text-[11px] uppercase tracking-[0.18em] text-muted">Target URL</dt>
                          <dd className="mt-1 font-mono break-all text-ink">{state.request.targetUrl}</dd>
                        </div>
                      </dl>
                    </DetailsDisclosure>
                  </div>
                </div>
              )}
            </div>
          </section>
        </Container>
      </main>

      <Footer rightLink={{ label: "Back to Home", href: "/" }} />

      {showResult && result && (
        <ResultModal result={result} onClose={() => setShowResult(false)} />
      )}
    </div>
  );
}
