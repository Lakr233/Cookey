import { useEffect, useState } from "react";
import Nav from "../components/Nav";
import Footer from "../components/Footer";
import Container from "../components/Container";

type RequestStatus = "pending" | "ready" | "delivered" | "expired";

type WSMessage =
  | { type: "status"; payload: { status: RequestStatus; timestamp: string } }
  | { type: "session"; payload: { delivered_at: string } }
  | { type: "error"; payload: { code: string; message: string } };

export default function TestLoginDoPage() {
  const [status, setStatus] = useState<RequestStatus>("pending");
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const rid = new URLSearchParams(window.location.search).get("rid");
    if (!rid) {
      setError("Missing request ID");
      return;
    }

    let disposed = false;
    let pollTimer: number | undefined;

    const redirect = () => {
      window.location.assign(`/test-login-result?rid=${encodeURIComponent(rid)}`);
    };

    const startPolling = () => {
      if (pollTimer) return;
      pollTimer = window.setInterval(async () => {
        try {
          const response = await fetch(`https://api.cookey.sh/v1/requests/${encodeURIComponent(rid)}`);
          if (response.status === 410) {
            setError("Request expired");
            window.clearInterval(pollTimer);
            return;
          }
          if (!response.ok) return;
          const data: { status: RequestStatus } = await response.json();
          setStatus(data.status);
          if (data.status === "ready" || data.status === "delivered") {
            window.clearInterval(pollTimer);
            redirect();
          }
        } catch {
          // Ignore polling errors
        }
      }, 2000);
    };

    const ws = new WebSocket(`wss://api.cookey.sh/v1/requests/${encodeURIComponent(rid)}/ws`);
    
    ws.onmessage = (event) => {
      try {
        const msg: WSMessage = JSON.parse(event.data);
        if (msg.type === "status") setStatus(msg.payload.status);
        if (msg.type === "session") redirect();
        if (msg.type === "error") setError(msg.payload.message);
      } catch {
        // Ignore parse errors
      }
    };
    
    ws.onerror = () => {
      // Start polling on error
      startPolling();
    };
    
    ws.onclose = () => {
      if (!disposed) startPolling();
    };

    return () => {
      disposed = true;
      ws.close();
      if (pollTimer) window.clearInterval(pollTimer);
    };
  }, []);

  const getStatusMessage = () => {
    switch (status) {
      case "pending":
        return "Waiting for device login...";
      case "ready":
        return "Session ready, redirecting...";
      case "delivered":
        return "Complete! Redirecting...";
      case "expired":
        return "Request expired";
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
              <div className="rounded-xl border border-border bg-surface px-6 py-4 text-ink max-w-md mx-auto">
                <p className="font-medium">{error}</p>
              </div>
            ) : (
              <>
                <div className="flex justify-center mb-6">
                  <div className="h-12 w-12 animate-spin rounded-full border-[3px] border-border border-t-accent" />
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