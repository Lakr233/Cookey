import { useEffect, useState } from "react";
import Nav from "../components/Nav";
import Footer from "../components/Footer";
import Container from "../components/Container";
import Badge from "../components/Badge";

type RequestStatus = "pending" | "ready" | "delivered" | "expired";

interface RequestResult {
  rid: string;
  status: RequestStatus;
  created_at: string;
  expires_at: string;
  target_url: string;
}

export default function TestLoginResultPage() {
  const [result, setResult] = useState<RequestResult | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    const rid = params.get("rid");

    if (!rid) {
      setError("Request ID not found in URL");
      setLoading(false);
      return;
    }

    const fetchResult = async () => {
      try {
        const response = await fetch(`https://api.cookey.sh/v1/requests/${rid}`);
        if (!response.ok) {
          throw new Error(`Failed to fetch request details: ${response.status}`);
        }
        const data = await response.json();
        setResult(data);
      } catch (err) {
        setError(err instanceof Error ? err.message : "An error occurred");
      } finally {
        setLoading(false);
      }
    };

    fetchResult();
  }, []);

  const isComplete = result?.status === "ready" || result?.status === "delivered";
  const isExpired = result?.status === "expired";

  return (
    <div className="bg-bg text-ink font-sans leading-[1.6] min-h-screen flex flex-col">
      <Nav />

      <main className="flex-1">
        <Container>
          <div className="py-16 text-center">
            {loading && (
              <div className="flex justify-center py-12">
                <div className="h-8 w-8 animate-spin rounded-full border-2 border-border border-t-accent" />
              </div>
            )}

            {error && (
              <div className="rounded-xl border border-border bg-surface px-6 py-8 text-ink max-w-md mx-auto">
                <div className="text-4xl mb-4">⚠️</div>
                <h1 className="text-xl font-bold mb-3">Error</h1>
                <p>{error}</p>
              </div>
            )}

            {!loading && !error && result && (
              <div className="max-w-lg mx-auto">
                {isComplete ? (
                  <>
                    <div className="inline-flex items-center justify-center w-16 h-16 rounded-full bg-surface border-2 border-border text-accent text-3xl mb-6">
                      ✓
                    </div>

                    <h1 className="text-3xl font-bold tracking-tight mb-4">
                      Test Login Successful
                    </h1>
                    
                    <div className="mb-8">
                      <Badge>App Store Review Complete</Badge>
                    </div>
                  </>
                ) : isExpired ? (
                  <>
                    <div className="inline-flex items-center justify-center w-16 h-16 rounded-full bg-surface border-2 border-border text-muted text-3xl mb-6">
                      ⏱
                    </div>

                    <h1 className="text-3xl font-bold tracking-tight mb-4">
                      Request Expired
                    </h1>
                    
                    <div className="mb-8">
                      <Badge>Timed Out</Badge>
                    </div>
                  </>
                ) : (
                  <>
                    <div className="inline-flex items-center justify-center w-16 h-16 rounded-full bg-surface border-2 border-border text-accent text-3xl mb-6">
                      ⏳
                    </div>

                    <h1 className="text-3xl font-bold tracking-tight mb-4">
                      Login Pending
                    </h1>
                    
                    <div className="mb-8">
                      <Badge>Waiting for Device</Badge>
                    </div>

                    <div className="flex justify-center mb-8">
                      <div className="h-8 w-8 animate-spin rounded-full border-2 border-border border-t-accent" />
                    </div>
                  </>
                )}

                <div className="rounded-xl border border-border bg-surface p-6 text-left">
                  <dl className="space-y-4">
                    <div>
                      <dt className="text-xs font-medium text-muted uppercase tracking-wide">
                        Request ID
                      </dt>
                      <dd className="font-mono text-sm text-ink break-all mt-1">
                        {result.rid}
                      </dd>
                    </div>

                    <div>
                      <dt className="text-xs font-medium text-muted uppercase tracking-wide">
                        Status
                      </dt>
                      <dd className="text-ink font-medium mt-1 capitalize">
                        {result.status}
                      </dd>
                    </div>

                    <div>
                      <dt className="text-xs font-medium text-muted uppercase tracking-wide">
                        Created At
                      </dt>
                      <dd className="text-ink mt-1">
                        {new Date(result.created_at).toLocaleString()}
                      </dd>
                    </div>

                    <div>
                      <dt className="text-xs font-medium text-muted uppercase tracking-wide">
                        Target URL
                      </dt>
                      <dd className="font-mono text-sm text-ink break-all mt-1">
                        {result.target_url}
                      </dd>
                    </div>
                  </dl>
                </div>

                {isComplete && (
                  <p className="mt-8 text-muted text-sm">
                    Your test login has been completed successfully. The session has been securely relayed.
                  </p>
                )}

                <div className="mt-8">
                  <a
                    href="/test-login-instruction"
                    className="text-accent hover:underline text-sm"
                  >
                    Run another test →
                  </a>
                </div>
              </div>
            )}
          </div>
        </Container>
      </main>

      <Footer rightLink={{ label: "Back to Home", href: "/" }} />
    </div>
  );
}