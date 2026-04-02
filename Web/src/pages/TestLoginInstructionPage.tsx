import { useEffect, useState } from "react";
import Nav from "../components/Nav";
import Footer from "../components/Footer";
import Container from "../components/Container";
import Badge from "../components/Badge";
import { Button } from "../components/Button";

interface LoginRequest {
  rid: string;
  server_url: string;
}

const API_BASE = "https://api.cookey.sh";
const TARGET_URL = "https://cookey.sh/test-login-do";

function generateKeyPair(): { deviceId: string; pubkey: string } {
  const deviceId = crypto.randomUUID();
  const randomBytes = new Uint8Array(32);
  crypto.getRandomValues(randomBytes);
  const pubkey = btoa(String.fromCharCode(...randomBytes));
  return { deviceId, pubkey };
}

function buildDeepLink(rid: string, deviceId: string, pubkey: string): string {
  const params = new URLSearchParams({
    device_id: deviceId,
    pubkey: pubkey,
    request_type: "login",
    rid: rid,
    server: API_BASE,
    target: TARGET_URL,
  });
  return `cookey://login?${params.toString()}`;
}

function generateQRText(rid: string): string {
  // Simple ASCII QR placeholder - in production this would be a real QR code
  return `
┌─────────────────┐
│  COOKEY LOGIN   │
│                 │
│   RID: ${rid.slice(0, 8)}   │
│                 │
│  Scan with app  │
└─────────────────┘
  `.trim();
}

export default function TestLoginInstructionPage() {
  const [request, setRequest] = useState<LoginRequest | null>(null);
  const [keys, setKeys] = useState<{ deviceId: string; pubkey: string } | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    async function createLoginRequest() {
      try {
        const { deviceId, pubkey } = generateKeyPair();
        setKeys({ deviceId, pubkey });

        const response = await fetch(`${API_BASE}/v1/requests`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            target_url: TARGET_URL,
            request_type: "login",
            device_id: deviceId,
            pubkey: pubkey,
          }),
        });

        if (!response.ok) {
          throw new Error(`API error: ${response.status}`);
        }

        const data = await response.json();
        setRequest({ rid: data.rid, server_url: data.server_url || API_BASE });
      } catch (err) {
        setError(err instanceof Error ? err.message : "Failed to create login request");
      } finally {
        setLoading(false);
      }
    }

    createLoginRequest();
  }, []);

  return (
    <div className="bg-bg text-ink font-sans leading-[1.6] min-h-screen flex flex-col">
      <Nav />

      <main className="flex-1">
        <Container>
          <section className="pt-20 pb-16 text-center">
            <div className="mb-7">
              <Badge>App Store Review Test</Badge>
            </div>

            <h1 className="mb-[18px] font-bold tracking-[-0.03em] leading-[1.1] text-[clamp(2.2rem,6vw,3.2rem)]">
              Test Login
            </h1>
            <p className="mb-9 max-w-[520px] mx-auto text-[1.05rem] text-muted">
              Scan the QR code with Cookey or tap the button below to test the login flow.
            </p>

            {loading && (
              <div className="flex justify-center py-12">
                <div className="h-8 w-8 animate-spin rounded-full border-2 border-border border-t-accent" />
              </div>
            )}

            {error && (
              <div className="rounded-xl border border-border bg-surface px-6 py-4 text-ink">
                <p className="font-medium">Error: {error}</p>
              </div>
            )}

            {request && keys && (
              <div className="max-w-[420px] mx-auto">
                <div className="mb-8 overflow-hidden rounded-xl border border-border bg-terminal-bg p-6">
                  <pre className="m-0 text-center text-[12px] leading-[1.2] text-ink font-mono whitespace-pre">
                    {generateQRText(request.rid)}
                  </pre>
                </div>

                <div className="flex flex-col items-center gap-4">
                  <Button
                    variant="primary"
                    onClick={() => window.location.href = buildDeepLink(request.rid, keys.deviceId, keys.pubkey)}
                  >
                    Open in Cookey
                  </Button>
                  
                  <p className="text-sm text-muted">
                    Request ID: <code className="font-mono text-ink">{request.rid}</code>
                  </p>
                </div>

                <div className="mt-12 text-left rounded-xl border border-border p-6 bg-surface">
                  <h3 className="font-semibold mb-3">How it works</h3>
                  <ol className="list-decimal list-inside space-y-2 text-muted text-sm">
                    <li>Scan the QR code above with your Cookey app</li>
                    <li>Complete the login on your device</li>
                    <li>Session will be securely relayed back</li>
                    <li>View the result on the confirmation page</li>
                  </ol>
                </div>
              </div>
            )}
          </section>
        </Container>
      </main>

      <Footer rightLink={{ label: "Back to Home", href: "/" }} />
    </div>
  );
}