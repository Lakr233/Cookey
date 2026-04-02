import { useEffect, useState } from "react";
import Nav from "../components/Nav";
import Footer from "../components/Footer";
import Container from "../components/Container";
import Badge from "../components/Badge";

interface RequestResult {
  rid: string;
  status: string;
  created_at: string;
  target_url: string;
  expires_at?: string;
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
              <div className="rounded-xl border border-red-200 bg-red-50 px-6 py-8 text-red-700 max-w-md mx-auto">
                <div className="text-4xl mb-4">⚠️</div>
                <h1 className="text-xl font-bold mb-3">Error</h1>
                <p>{error}</p>
              </div>
            )}

            {!loading && !error && result && (
              <div className="max-w-lg mx-auto">
                <div className="inline-flex items-center justify-center w-16 h-16 rounded-full bg-green-100 text-green-600 text-3xl mb-6">
                  ✓
                </div>

                <h1 className="text-3xl font-bold tracking-tight mb-4">
                  Test Login Successful
                </h1>
                
                <div className="mb-8">
                  <Badge>App Store Review Complete</Badge>
                </div>

                <div className="rounded-xl border border-border bg-surface p-6 text-left">
                  <div className="mb-4">
                    <label className="text-xs font-medium text-muted uppercase tracking-wide">
                      Request ID
                    </label>
                    <p className="font-mono text-sm text-ink break-all mt-1">
                      {result.rid}
                    </p>
                  </div>

                  <div className="mb-4">
                    <label className="text-xs font-medium text-muted uppercase tracking-wide">
                      Status
                    </label>
                    <p className="text-green-600 font-medium mt-1 capitalize">
                      {result.status}
                    </p>
                  </div>

                  <div className="mb-4">
                    <label className="text-xs font-medium text-muted uppercase tracking-wide">
                      Created At
                    </label>
                    <p className="text-ink mt-1">
                      {new Date(result.created_at).toLocaleString()}
                    </p>
                  </div>

                  <div>
                    <label className="text-xs font-medium text-muted uppercase tracking-wide">
                      Target URL
                    </label>
                    <p className="font-mono text-sm text-ink break-all mt-1">
                      {result.target_url}
                    </p>
                  </div>
                </div>

                <p className="mt-8 text-muted text-sm">
                  Your test login has been completed successfully. The session has been securely relayed.
                </p>

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