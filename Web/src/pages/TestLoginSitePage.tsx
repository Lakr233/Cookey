import { useState } from "react";

export default function TestLoginSitePage() {
  const [email, setEmail] = useState("reviewer@example.com");
  const [loggedIn, setLoggedIn] = useState(false);

  const handleCreateAccount = () => {
    const trimmed = email.trim() || "reviewer@example.com";

    document.cookie = `session_token=test_${Date.now()}; path=/; SameSite=Lax`;
    document.cookie = `logged_in=true; path=/; SameSite=Lax`;
    localStorage.setItem(
      "user",
      JSON.stringify({
        email: trimmed,
        name: "Test User",
        logged_in_at: new Date().toISOString(),
      }),
    );

    setEmail(trimmed);
    setLoggedIn(true);
  };

  return (
    <div className="bg-bg text-ink font-sans leading-[1.6] min-h-screen flex items-center justify-center px-5 py-12">
      <div className="w-full max-w-[400px]">
        {!loggedIn ? (
          <div className="animate-[fade-in_0.4s_ease-out_both]">
            <div className="text-center mb-8">
              <div className="inline-flex items-center justify-center w-14 h-14 rounded-2xl bg-surface border border-border mb-5">
                <svg
                  className="w-7 h-7 text-accent"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke="currentColor"
                  strokeWidth={1.5}
                >
                  <path
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    d="M15.75 6a3.75 3.75 0 11-7.5 0 3.75 3.75 0 017.5 0zM4.501 20.118a7.5 7.5 0 0114.998 0A17.933 17.933 0 0112 21.75c-2.676 0-5.216-.584-7.499-1.632z"
                  />
                </svg>
              </div>
              <h1 className="text-2xl font-bold tracking-tight">
                Create an Account
              </h1>
              <p className="mt-3 text-sm text-muted max-w-[340px] mx-auto">
                This is a demo site for testing Cookey. No real account will be
                created. The email you enter is used only for this test session.
              </p>
            </div>

            <div className="rounded-xl border border-border bg-surface p-5">
              <label className="block">
                <span className="text-xs font-medium text-muted uppercase tracking-[0.12em]">
                  Email address
                </span>
                <input
                  type="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  placeholder="you@example.com"
                  className="mt-2 block w-full rounded-lg border border-border bg-terminal-bg px-4 py-3 text-sm text-ink placeholder:text-muted/50 outline-none focus:border-accent/40 focus:ring-1 focus:ring-accent/20 transition-colors"
                />
              </label>
              <button
                type="button"
                onClick={handleCreateAccount}
                className="mt-4 w-full rounded-lg bg-accent px-4 py-3 text-sm font-semibold text-bg transition-opacity hover:opacity-90 active:opacity-80"
              >
                Create Account
              </button>
            </div>
          </div>
        ) : (
          <div className="animate-[fade-in_0.4s_ease-out_both]">
            <div className="text-center mb-8">
              <div className="animate-scale-in inline-flex items-center justify-center w-20 h-20 rounded-full border-2 border-accent bg-accent/10 shadow-[0_0_32px_rgba(74,222,128,0.12)] mb-5">
                <svg
                  className="w-10 h-10 text-accent"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke="currentColor"
                  strokeWidth={2}
                >
                  <path
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    d="M5 13l4 4L19 7"
                  />
                </svg>
              </div>
              <h1 className="text-2xl font-bold tracking-tight">
                You're now logged in
              </h1>
            </div>

            <div className="rounded-xl border border-border bg-surface p-5 mb-5">
              <p className="text-xs font-medium text-muted uppercase tracking-[0.12em] mb-3">
                The agent will have access to
              </p>
              <div className="rounded-lg bg-terminal-bg border border-border px-4 py-3">
                <span className="text-[11px] uppercase tracking-[0.18em] text-muted">
                  Email
                </span>
                <p className="mt-1 text-sm font-mono text-ink break-all">
                  {email}
                </p>
              </div>
            </div>

            <div className="rounded-xl border border-accent/20 bg-accent/5 p-5 text-center">
              <p className="text-sm text-ink">
                Tap the <strong>send button</strong>{" "}
                <span className="inline-block translate-y-[-1px]">
                  <svg
                    className="inline w-4 h-4 text-accent"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke="currentColor"
                    strokeWidth={2}
                  >
                    <path
                      strokeLinecap="round"
                      strokeLinejoin="round"
                      d="M6 12L3.269 3.126A59.768 59.768 0 0121.485 12 59.77 59.77 0 013.27 20.876L5.999 12zm0 0h7.5"
                    />
                  </svg>
                </span>{" "}
                in the top-right corner to deliver your session.
              </p>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
