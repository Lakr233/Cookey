import type { ReactNode } from "react";

export default function Terminal({
  title,
  children,
}: {
  title: string;
  children: ReactNode;
}) {
  return (
    <div className="mt-16 overflow-hidden rounded-xl border border-white/[0.08] text-left shadow-2xl">
      <div className="flex items-center gap-2 border-b border-white/[0.08] bg-[#1a1a1a] px-4 py-3">
        <span className="h-[10px] w-[10px] rounded-full bg-dot-red" />
        <span className="h-[10px] w-[10px] rounded-full bg-dot-yellow" />
        <span className="h-[10px] w-[10px] rounded-full bg-dot-green" />
        <span className="flex-1 text-center text-xs text-[#888]">{title}</span>
      </div>
      <div className="overflow-x-auto bg-[#0d0d0d] p-[24px_20px] font-mono text-[13px] leading-[1.8] text-[#f0f0f0] [&_.text-muted]:text-[#888] [&_.text-ink]:text-[#f0f0f0] [&_.text-code-prompt]:text-[#4ade80] [&_.text-code-rid]:text-[#a78bfa] [&_.text-code-url]:text-[#60a5fa]">
        {children}
      </div>
    </div>
  );
}
