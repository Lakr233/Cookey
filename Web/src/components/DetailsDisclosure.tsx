import React from "react";

interface DetailsDisclosureProps {
  children: React.ReactNode;
  title?: string;
}

export default function DetailsDisclosure({
  children,
  title = "Technical Details",
}: DetailsDisclosureProps) {
  return (
    <details className="rounded-xl border border-border bg-terminal-bg overflow-hidden group">
      <summary className="flex items-center justify-between px-5 py-4 cursor-pointer list-none hover:bg-white/[0.02] transition-colors">
        <span className="text-xs font-medium uppercase tracking-[0.15em] text-muted">
          {title}
        </span>
        <svg
          className="w-4 h-4 text-muted transition-transform duration-200 group-open:rotate-180"
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path
            strokeLinecap="round"
            strokeLinejoin="round"
            strokeWidth={2}
            d="M19 9l-7 7-7-7"
          />
        </svg>
      </summary>
      <div className="px-5 pb-5">{children}</div>
    </details>
  );
}