import { useCallback, useState } from "react";
import Footer from "../components/Footer";
import Container from "../components/Container";
import Badge from "../components/Badge";
import { ButtonLink, Button } from "../components/Button";
import Terminal from "../components/Terminal";
import QrCode from "../components/QrCode";
import SectionBlock from "../components/SectionBlock";
import StepCard from "../components/StepCard";
import PropertyCard from "../components/PropertyCard";
import FaqItem from "../components/FaqItem";
import Typewriter from "../components/Typewriter";
import GridBackground from "../components/GridBackground";
import TerminalLines from "../components/TerminalLines";
import Sheet from "../components/Sheet";
import { AGENT_MARKDOWN } from "../data/agentMarkdown";

const HERO_LINES = [
  { text: "Give Your Agents the", className: "text-muted font-normal" },
  { text: "Cookey, Help Them In." },
];

export default function HomePage() {
  const [sheetOpen, setSheetOpen] = useState(false);
  const [copyState, setCopyState] = useState<"idle" | "copied" | "failed">("idle");

  const handleCopy = useCallback(async () => {
    try {
      await navigator.clipboard.writeText(AGENT_MARKDOWN + "\n");
      setCopyState("copied");
    } catch {
      setCopyState("failed");
    }
    setTimeout(() => setCopyState("idle"), 1800);
  }, []);

  return (
    <div className="bg-bg text-ink font-sans leading-[1.6]">
      <main>
        <section className="relative text-center">
          <GridBackground />
          <Container>
            <div className="pt-24 pb-20">
              <div className="mb-8">
                <Badge href="https://github.com/Lakr233/Cookey">Open source &middot; Self-hostable</Badge>
              </div>
              <Typewriter lines={HERO_LINES} />
              <p className="mx-auto mb-10 max-w-[480px] font-mono text-[0.85rem] text-muted">
                Scan a QR code on your phone, log in on mobile,
                <br />
                and your browser session lands encrypted in your terminal
                <br />
                — ready for Playwright and AI agents.
              </p>
              <div className="flex flex-wrap justify-center gap-3">
                <Button variant="primary" onClick={() => setSheetOpen(true)}>
                  Get started &rarr;
                </Button>
                <ButtonLink
                  href="https://apps.apple.com/app/cookey/id6745136531"
                  variant="primary"
                >
                  <svg className="h-[16px] w-[16px] fill-current" viewBox="0 0 24 24" aria-hidden="true">
                    <path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.8-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z" />
                  </svg>
                  Download iOS App
                </ButtonLink>
              </div>

              <Sheet open={sheetOpen} onClose={() => setSheetOpen(false)}>
                <p className="mb-2 text-[15px] font-semibold">
                  Paste this, let your agent handle it.
                </p>
                <p className="mb-5 text-[13px] text-muted">
                  Copy the instructions below, paste it into your terminal agent,
                  and let it install Cookey.
                </p>
                <Button
                  variant="primary"
                  onClick={handleCopy}
                  data-state={copyState === "copied" ? "copied" : ""}
                >
                  {copyState === "copied"
                    ? "Copied"
                    : copyState === "failed"
                      ? "Copy failed"
                      : "Copy for Agents"}
                </Button>
                <div className="mt-5 overflow-hidden rounded-xl border border-border">
                  <div className="overflow-x-auto bg-[#0d0d0d] p-[16px_16px]">
                    <pre className="m-0 whitespace-pre-wrap break-words font-mono text-[12px] leading-[1.8] text-[#888]">
                      {AGENT_MARKDOWN}
                    </pre>
                  </div>
                </div>
              </Sheet>

              <Terminal title="zsh">
                <TerminalLines>
                  <div>
                    <span className="text-code-prompt">❯</span>{" "}
                    <span className="text-ink">
                      cookey request start{" "}
                      <span className="text-code-url">
                        https://github.com/login
                      </span>
                    </span>
                  </div>
                  <div className="text-muted">&nbsp;</div>
                  <div className="text-muted">
                    &nbsp; Registered &nbsp;
                    <span className="text-code-rid">r_8GQx8tY0j8x3Yw2N</span>
                  </div>
                  <div className="text-muted">
                    &nbsp; Target URL &nbsp;
                    <span className="text-code-url">
                      https://github.com/login
                    </span>
                  </div>
                  <div className="text-muted">&nbsp; Expires in &nbsp;5m 00s</div>
                  <div className="text-muted">&nbsp;</div>
                  <QrCode />
                  <div className="text-muted">
                    &nbsp; Scan with the Cookey app. Waiting for session&hellip;
                  </div>
                </TerminalLines>
              </Terminal>
            </div>
          </Container>
        </section>

        <SectionBlock label="How it works" heading="Two steps, that's it.">
          <div className="grid grid-cols-1 gap-4 xs:grid-cols-2">
            <StepCard
              number="01"
              title="Agent installs Cookey"
              position="first"
            >
              Your AI agent installs{" "}
              <code className="rounded border border-border bg-tag-bg px-[6px] py-[1px] font-mono text-[0.88em]">
                cookey
              </code>{" "}
              as a tool. No manual setup &mdash; it&rsquo;s ready to go.
              <div className="group/code relative mt-4 overflow-hidden rounded-lg border border-border">
                <div className="flex items-center justify-between bg-[#1e1e1e] px-4 py-2">
                  <span className="font-mono text-[11px] text-[#888]">agent instructions</span>
                  <button
                    type="button"
                    onClick={handleCopy}
                    className="flex items-center gap-1.5 rounded-md bg-[#f0f0f0] px-3 py-1 font-mono text-[11px] font-semibold text-[#0a0a0a] border-0 cursor-pointer transition-all duration-200 hover:bg-white active:scale-95 opacity-0 group-hover/code:opacity-100"
                  >
                    <svg className="h-3 w-3 fill-current" viewBox="0 0 16 16" aria-hidden="true">
                      {copyState === "copied" ? (
                        <path d="M13.78 4.22a.75.75 0 0 1 0 1.06l-7.25 7.25a.75.75 0 0 1-1.06 0L2.22 9.28a.75.75 0 0 1 1.06-1.06L6 10.94l6.72-6.72a.75.75 0 0 1 1.06 0Z" />
                      ) : (
                        <path d="M0 6.75C0 5.784.784 5 1.75 5h1.5a.75.75 0 0 1 0 1.5h-1.5a.25.25 0 0 0-.25.25v7.5c0 .138.112.25.25.25h7.5a.25.25 0 0 0 .25-.25v-1.5a.75.75 0 0 1 1.5 0v1.5A1.75 1.75 0 0 1 9.25 16h-7.5A1.75 1.75 0 0 1 0 14.25ZM5 1.75C5 .784 5.784 0 6.75 0h7.5C15.216 0 16 .784 16 1.75v7.5A1.75 1.75 0 0 1 14.25 11h-7.5A1.75 1.75 0 0 1 5 9.25Zm1.75-.25a.25.25 0 0 0-.25.25v7.5c0 .138.112.25.25.25h7.5a.25.25 0 0 0 .25-.25v-7.5a.25.25 0 0 0-.25-.25Z" />
                      )}
                    </svg>
                    {copyState === "copied" ? "Copied!" : "Copy"}
                  </button>
                </div>
                <pre className="m-0 whitespace-pre-wrap break-words bg-[#1e1e1e] px-4 pb-4 font-mono text-[12px] leading-[1.8] text-[#bbb]">
                  {AGENT_MARKDOWN}
                </pre>
              </div>
            </StepCard>
            <StepCard number="02" title="Scan when needed" position="last">
              When a login is required, a QR code appears. Scan it with Cookey
              on your phone and log in. The agent receives cookies,
              localStorage, and session data &mdash; end-to-end encrypted.
              <div className="mt-6 flex justify-center">
                <svg width="200" height="160" viewBox="0 0 200 160" fill="none" xmlns="http://www.w3.org/2000/svg" className="text-muted/40">
                  {/* iPhone body */}
                  <rect x="60" y="8" width="80" height="144" rx="12" stroke="currentColor" strokeWidth="1.5" fill="none" />
                  <rect x="88" y="12" width="24" height="6" rx="3" fill="currentColor" opacity="0.4" />
                  <rect x="92" y="146" width="16" height="3" rx="1.5" fill="currentColor" opacity="0.3" />

                  {/* Screen area */}
                  <rect x="66" y="24" width="68" height="112" rx="2" fill="currentColor" opacity="0.05" />

                  {/* QR code on screen */}
                  <g transform="translate(78, 42)">
                    {/* QR corner top-left */}
                    <rect x="0" y="0" width="14" height="14" rx="1" stroke="currentColor" strokeWidth="1.5" fill="none" />
                    <rect x="3.5" y="3.5" width="7" height="7" rx="0.5" fill="currentColor" />

                    {/* QR corner top-right */}
                    <rect x="30" y="0" width="14" height="14" rx="1" stroke="currentColor" strokeWidth="1.5" fill="none" />
                    <rect x="33.5" y="3.5" width="7" height="7" rx="0.5" fill="currentColor" />

                    {/* QR corner bottom-left */}
                    <rect x="0" y="30" width="14" height="14" rx="1" stroke="currentColor" strokeWidth="1.5" fill="none" />
                    <rect x="3.5" y="33.5" width="7" height="7" rx="0.5" fill="currentColor" />

                    {/* QR data dots */}
                    <rect x="17" y="4" width="3" height="3" rx="0.5" fill="currentColor" opacity="0.6" />
                    <rect x="22" y="4" width="3" height="3" rx="0.5" fill="currentColor" opacity="0.6" />
                    <rect x="17" y="10" width="3" height="3" rx="0.5" fill="currentColor" opacity="0.6" />
                    <rect x="4" y="17" width="3" height="3" rx="0.5" fill="currentColor" opacity="0.6" />
                    <rect x="10" y="17" width="3" height="3" rx="0.5" fill="currentColor" opacity="0.6" />
                    <rect x="17" y="17" width="3" height="3" rx="0.5" fill="currentColor" opacity="0.6" />
                    <rect x="24" y="17" width="3" height="3" rx="0.5" fill="currentColor" opacity="0.6" />
                    <rect x="30" y="17" width="3" height="3" rx="0.5" fill="currentColor" opacity="0.6" />
                    <rect x="37" y="17" width="3" height="3" rx="0.5" fill="currentColor" opacity="0.6" />
                    <rect x="24" y="24" width="3" height="3" rx="0.5" fill="currentColor" opacity="0.6" />
                    <rect x="30" y="30" width="3" height="3" rx="0.5" fill="currentColor" opacity="0.6" />
                    <rect x="37" y="30" width="3" height="3" rx="0.5" fill="currentColor" opacity="0.6" />
                    <rect x="30" y="37" width="3" height="3" rx="0.5" fill="currentColor" opacity="0.6" />
                    <rect x="37" y="37" width="3" height="3" rx="0.5" fill="currentColor" opacity="0.6" />
                  </g>

                  {/* Scan lines animation */}
                  <line x1="70" y1="80" x2="130" y2="80" stroke="currentColor" strokeWidth="1" opacity="0.3">
                    <animate attributeName="y1" values="30;130;30" dur="2.5s" repeatCount="indefinite" />
                    <animate attributeName="y2" values="30;130;30" dur="2.5s" repeatCount="indefinite" />
                    <animate attributeName="opacity" values="0.1;0.5;0.1" dur="2.5s" repeatCount="indefinite" />
                  </line>

                  {/* Corner scan brackets */}
                  <g stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" opacity="0.5">
                    <path d="M28 48 L28 36 L40 36" fill="none" />
                    <path d="M172 48 L172 36 L160 36" fill="none" />
                    <path d="M28 112 L28 124 L40 124" fill="none" />
                    <path d="M172 112 L172 124 L160 124" fill="none" />
                  </g>
                </svg>
              </div>
            </StepCard>
          </div>
        </SectionBlock>

        <SectionBlock label="Design" heading="Built to stay out of the way.">
          <div className="grid grid-cols-[repeat(auto-fit,minmax(220px,1fr))] gap-6">
            <PropertyCard index={0} icon={
              <svg width="28" height="28" viewBox="0 0 28 28" fill="none" className="text-muted">
                <rect x="4" y="12" width="20" height="14" rx="3" stroke="currentColor" strokeWidth="1.5" />
                <path className="icon-lock-shackle" d="M9 12V8a5 5 0 0 1 10 0v4" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" style={{ transformOrigin: "14px 8px" }} />
                <circle className="icon-lock-dot" cx="14" cy="19.5" r="2" fill="currentColor" opacity="0.4" />
                <line className="icon-lock-dot" x1="14" y1="21.5" x2="14" y2="23.5" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" opacity="0.4" />
              </svg>
            } title="End-to-end encrypted">
              Session data is encrypted with your CLI public key before it
              leaves your phone. The relay never sees plaintext.
            </PropertyCard>
            <PropertyCard index={1} icon={
              <svg width="28" height="28" viewBox="0 0 28 28" fill="none" className="text-muted">
                <path
                  className="icon-draw"
                  d="M8 22h14a5 5 0 0 0 .5-9.97A7 7 0 0 0 9.1 9.36 5.5 5.5 0 0 0 8 22Z"
                  stroke="currentColor"
                  strokeWidth="1.5"
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  strokeDasharray="60"
                  strokeDashoffset="60"
                  style={{ "--dash-length": 60 } as React.CSSProperties}
                />
                <line className="icon-fade" x1="11" y1="16" x2="17" y2="16" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" opacity="0" style={{ "--target-opacity": 0.5, "--fade-delay": "1s" } as React.CSSProperties} />
              </svg>
            } title="Zero registration">
              No accounts, no device enrollment, no push tokens. The CLI
              generates its own key pair on first run.
            </PropertyCard>
            <PropertyCard index={2} icon={
              <svg width="28" height="28" viewBox="0 0 28 28" fill="none" className="text-muted">
                <rect className="icon-draw" x="3" y="4" width="22" height="16" rx="2" stroke="currentColor" strokeWidth="1.5" strokeDasharray="76" strokeDashoffset="76" style={{ "--dash-length": 76 } as React.CSSProperties} />
                <line className="icon-fade" x1="14" y1="20" x2="14" y2="24" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" opacity="0" style={{ "--fade-delay": "0.8s" } as React.CSSProperties} />
                <line className="icon-fade" x1="9" y1="24" x2="19" y2="24" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" opacity="0" style={{ "--fade-delay": "1s" } as React.CSSProperties} />
                <line className="icon-fade" x1="8" y1="10" x2="13" y2="10" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" opacity="0" style={{ "--target-opacity": 0.5, "--fade-delay": "1.2s" } as React.CSSProperties} />
                <line className="icon-fade" x1="8" y1="13.5" x2="16" y2="13.5" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" opacity="0" style={{ "--target-opacity": 0.3, "--fade-delay": "1.4s" } as React.CSSProperties} />
              </svg>
            } title="Self-hostable relay">
              Run your own relay with a single Docker image. Nothing is stored
              in a database &mdash; memory only, auto-expiring.
            </PropertyCard>
          </div>
        </SectionBlock>

        <SectionBlock label="FAQ" heading="Common questions.">
          <div className="px-0">
            <FaqItem index={0} question="Why can't I use passkeys or security keys in the in-app browser?">
              Cookey uses WKWebView to capture cookies and localStorage after
              you log in. Apple blocks Passkey, WebAuthn, and FIDO2 security key
              APIs in WKWebView &mdash; only Safari and
              ASWebAuthenticationSession are allowed to access them. This is an
              intentional platform restriction: embedded browsers can inject
              JavaScript and intercept requests, so Apple considers them a
              phishing risk for credential operations.
              <br />
              <br />
              <strong>Workaround:</strong> choose an alternative login method
              (password, SMS OTP, email link, etc.) when authenticating inside
              Cookey.
            </FaqItem>
            <FaqItem index={1} question="Can the relay server see my session data?">
              No. Session data is encrypted on your phone with the CLI&rsquo;s
              public key (X25519 ECDH + XSalsa20-Poly1305) before it leaves the
              device. The relay only forwards opaque encrypted blobs and deletes
              them after delivery or expiry.
            </FaqItem>
            <FaqItem index={2} question="What data does Cookey capture?">
              Cookies and localStorage for the site you logged in to. This is
              exported as Playwright-compatible{" "}
              <code className="rounded border border-border bg-tag-bg px-[4px] py-[1px] font-mono text-[0.88em]">
                storageState
              </code>{" "}
              JSON. No passwords, autofill data, or indexedDB content is
              captured.
            </FaqItem>
            <FaqItem index={3} question="Do I need an account to use Cookey?">
              No. The CLI generates its own Ed25519 key pair on first run. There
              is no registration, no device enrollment, and no push tokens
              required.
            </FaqItem>
          </div>
        </SectionBlock>
      </main>

      <Footer
        rightLink={{
          label: "Test Login",
          href: "/test-login-instruction",
        }}
      />
    </div>
  );
}
