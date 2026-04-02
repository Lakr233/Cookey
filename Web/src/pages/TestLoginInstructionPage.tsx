import { useEffect, useState } from "react";
import Nav from "../components/Nav";
import Footer from "../components/Footer";
import Container from "../components/Container";
import Badge from "../components/Badge";
import QrCode from "../components/QrCode";
import StepProgress from "../components/StepProgress";
import DetailsDisclosure from "../components/DetailsDisclosure";
import { Button, ButtonLink } from "../components/Button";
import { createLoginRequest, type LoginRequestState } from "../lib/testLogin";

type PageState =
  | { kind: "loading" }
  | { kind: "ready"; request: LoginRequestState }
  | { kind: "error"; message: string };

export default function TestLoginInstructionPage() {
  const [state, setState] = useState<PageState>({ kind: "loading" });
  const [attempt, setAttempt] = useState(0);

  useEffect(() => {
    const controller = new AbortController();
    setState({ kind: "loading" });

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

  return (
    <div className="bg-bg text-ink font-sans leading-[1.6] min-h-screen flex flex-col">
      <Nav />

      <main className="flex-1">
        <Container>
          <section className="pt-20 pb-16">
            <div className="mb-7 text-center animate-[fade-in_0.4s_ease-out]">
              <Badge>App Store Review Test</Badge>
            </div>

            <div className="mx-auto max-w-[620px] text-center">
              <h1 className="mb-[18px] font-bold tracking-[-0.03em] leading-[1.1] text-[clamp(2.2rem,6vw,3.2rem)] animate-[fade-in_0.4s_ease-out] delay-100">
                Start a test login request.
              </h1>
              <p className="mx-auto mb-8 max-w-[540px] text-[1.05rem] text-muted animate-[fade-in_0.4s_ease-out] delay-200">
                This page creates a real relay request, encodes the Cookey deep link
                into a scannable QR code, and gives you a status page for the review flow.
              </p>
            </div>

            <div className="mb-10 animate-[fade-in_0.4s_ease-out] delay-300">
              <StepProgress current={1} />
            </div>

            <div className="mx-auto max-w-[620px] rounded-xl border border-border bg-surface p-6 sm:p-7 animate-[fade-in_0.4s_ease-out] delay-400">
              {state.kind === "loading" && (
                <div className="text-center" role="status" aria-live="polite">
                  <div className="mb-5 flex justify-center">
                    <div aria-hidden="true" className="h-10 w-10 animate-spin rounded-full border-[3px] border-border border-t-accent" />
                  </div>
                  <h2 className="text-xl font-semibold tracking-tight">Creating login request</h2>
                  <p className="mt-3 text-sm text-muted">
                    Generating a request ID, relay payload, and deep link for Cookey.
                  </p>
                </div>
              )}

              {state.kind === "error" && (
                <div className="text-center" role="status" aria-live="polite">
                  <h2 className="text-xl font-semibold tracking-tight">Request setup failed</h2>
                  <p className="mt-3 text-sm text-muted">{state.message}</p>
                  <div className="mt-6 flex flex-wrap justify-center gap-3">
                    <Button variant="primary" onClick={() => setAttempt((current) => current + 1)}>
                      Retry request
                    </Button>
                    <ButtonLink href="/" variant="secondary">
                      Back to home
                    </ButtonLink>
                  </div>
                </div>
              )}

              {state.kind === "ready" && (
                <div className="flex flex-col items-center gap-6">
                  <div className="rounded-2xl border border-accent/20 bg-terminal-bg p-8 shadow-[0_0_32px_rgba(74,222,128,0.08)] animate-[fade-in_0.4s_ease-out] delay-500">
                    <QrCode value={state.request.deepLink} size={200} />
                  </div>

                  <p className="text-sm text-muted text-center animate-[fade-in_0.4s_ease-out] delay-600">
                    Scan with the Cookey app on your review device
                  </p>

                  <div className="flex flex-wrap justify-center gap-3 animate-[fade-in_0.4s_ease-out] delay-700">
                    <ButtonLink href={state.request.deepLink} variant="primary">
                      Open in Cookey
                    </ButtonLink>
                    <ButtonLink href={state.request.monitorUrl} variant="secondary">
                      Continue to status →
                    </ButtonLink>
                  </div>

                  <div className="w-full mt-2 animate-[fade-in_0.4s_ease-out] delay-800">
                    <DetailsDisclosure title="Request Details">
                      <dl className="space-y-4 text-sm">
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
    </div>
  );
}