import { useEffect, useState } from "react";
import Nav from "../components/Nav";
import Footer from "../components/Footer";
import Container from "../components/Container";

export default function TestLoginDoPage() {
  const [status, setStatus] = useState<string>("pending");
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    const rid = params.get("rid");

    if (!rid) {
      setError("Missing request ID");
      return;
    }

    const ws = new WebSocket(`wss://api.cookey.sh/v1/requests/${rid}/ws`);

    ws.onmessage = (event) => {
      const data = JSON.parse(event.data);
      setStatus(data.status);

      if (data.status === "uploaded") {
        window.location.href = `/test-login-result?rid=${rid}`;
      }
    };

    ws.onerror = () => {
      setError("WebSocket connection failed");
    };

    ws.onclose = () => {
      // Try polling as fallback
      const pollInterval = setInterval(async () => {
        try {
          const response = await fetch(`https://api.cookey.sh/v1/requests/${rid}`);
          if (response.ok) {
            const data = await response.json();
            if (data.status === "uploaded") {
              clearInterval(pollInterval);
              window.location.href = `/test-login-result?rid=${rid}`;
            } else {
              setStatus(data.status);
            }
          }
        } catch {
          // Ignore polling errors
        }
      }, 2000);

      return () => clearInterval(pollInterval);
    };

    return () => {
      ws.close();
    };
  }, []);

  const getStatusMessage = () => {
    switch (status) {
      case "pending":
        return "Waiting for device login...";
      case "uploading":
        return "Receiving session data...";
      case "uploaded":
        return "Complete! Redirecting...";
      default:
        return "Processing...";
    }
  };

  return (
    <div className="bg-bg text-ink font-sans leading-[1.6] min-h-screen flex flex-col">
      <Nav />

      <main className="flex-1">
        <Container>
          <div className="text-center py-20">
            {error ? (
              <div className="rounded-xl border border-red-200 bg-red-50 px-6 py-4 text-red-700 max-w-md mx-auto">
                <p className="font-medium">{error}</p>
              </div>
            ) : (
              <>
                <div className="flex justify-center mb-6">
                  <div className="h-12 w-12 animate-spin rounded-full border-3 border-border border-t-accent" />
                </div>

                <h2 className="text-2xl font-bold tracking-tight mb-3">
                  Login in Progress
                </h2>
                <p className="text-muted max-w-md mx-auto">
                  {getStatusMessage()}
                </p>

                <div className="mt-8 text-sm text-muted">
                  <p>Please complete the login on your device.</p>
                </div>
              </>
            )}
          </div>
        </Container>
      </main>

      <Footer rightLink={{ label: "Back to Home", href: "/" }} />
    </div>
  );
}