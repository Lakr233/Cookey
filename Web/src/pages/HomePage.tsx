import Nav from "../components/Nav";
import Footer from "../components/Footer";
import Container from "../components/Container";
import Badge from "../components/Badge";
import { ButtonLink } from "../components/Button";
import Terminal from "../components/Terminal";
import QrCode from "../components/QrCode";
import SectionBlock from "../components/SectionBlock";
import StepCard from "../components/StepCard";
import PropertyCard from "../components/PropertyCard";
import FaqItem from "../components/FaqItem";

const NAV_LINKS = [{ label: "llms.txt", href: "/llms.txt" }];

export default function HomePage() {
  return (
    <div className="bg-bg text-ink font-sans leading-[1.6]">
      <Nav links={NAV_LINKS} />

      <main>
        <section className="text-center">
          <Container>
            <div className="pt-24 pb-20">
              <div className="mb-8">
                <Badge>Open source &middot; Self-hostable</Badge>
              </div>
              <h1 className="mb-5 font-bold tracking-[-0.03em] text-ink leading-[1.1] text-[clamp(2.2rem,6vw,3.6rem)]">
                <span
                  className="text-muted font-normal"
                  style={{ fontStyle: "normal" }}
                >
                  Give Your Agents the
                </span>
                <br />
                Cookey, Help Them In.
              </h1>
              <p className="mx-auto mb-10 max-w-[480px] text-[1.05rem] text-muted">
                Scan a QR code on your phone, log in on mobile, and your browser
                session lands encrypted in your terminal &mdash; ready for
                Playwright and AI agents.
              </p>
              <div className="flex flex-wrap justify-center gap-3">
                <ButtonLink href="/get-started" variant="primary">
                  Get started &rarr;
                </ButtonLink>
                <ButtonLink
                  href="https://github.com/Lakr233/Cookey#readme"
                  variant="secondary"
                >
                  Get source
                </ButtonLink>
              </div>

              <Terminal title="zsh">
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
              </Terminal>
            </div>
          </Container>
        </section>

        <SectionBlock label="How it works" heading="Two steps, that's it.">
          <div className="grid grid-cols-[repeat(auto-fit,minmax(200px,1fr))] gap-[2px]">
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
            </StepCard>
            <StepCard number="02" title="Scan when needed" position="last">
              When a login is required, a QR code appears. Scan it with Cookey
              on your phone and log in. The agent receives cookies,
              localStorage, and session data &mdash; end-to-end encrypted.
            </StepCard>
          </div>
        </SectionBlock>

        <SectionBlock label="Design" heading="Built to stay out of the way.">
          <div className="grid grid-cols-[repeat(auto-fit,minmax(220px,1fr))] gap-6">
            <PropertyCard icon="🔒" title="End-to-end encrypted">
              Session data is encrypted with your CLI public key before it
              leaves your phone. The relay never sees plaintext.
            </PropertyCard>
            <PropertyCard icon="☁️" title="Zero registration">
              No accounts, no device enrollment, no push tokens. The CLI
              generates its own key pair on first run.
            </PropertyCard>
            <PropertyCard icon="🖥" title="Self-hostable relay">
              Run your own relay with a single Docker image. Nothing is stored
              in a database &mdash; memory only, auto-expiring.
            </PropertyCard>
          </div>
        </SectionBlock>

        <SectionBlock label="FAQ" heading="Common questions.">
          <div className="rounded-[10px] border border-border bg-surface px-6">
            <FaqItem question="Why can't I use passkeys or security keys in the in-app browser?">
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
            <FaqItem question="Can the relay server see my session data?">
              No. Session data is encrypted on your phone with the CLI&rsquo;s
              public key (X25519 ECDH + XSalsa20-Poly1305) before it leaves the
              device. The relay only forwards opaque encrypted blobs and deletes
              them after delivery or expiry.
            </FaqItem>
            <FaqItem question="What data does Cookey capture?">
              Cookies and localStorage for the site you logged in to. This is
              exported as Playwright-compatible{" "}
              <code className="rounded border border-border bg-tag-bg px-[4px] py-[1px] font-mono text-[0.88em]">
                storageState
              </code>{" "}
              JSON. No passwords, autofill data, or indexedDB content is
              captured.
            </FaqItem>
            <FaqItem question="Do I need an account to use Cookey?">
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
