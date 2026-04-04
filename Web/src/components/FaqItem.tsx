import { useState, useRef, useEffect } from "react";
import type { ReactNode } from "react";

export default function FaqItem({
  question,
  children,
  index = 0,
}: {
  question: string;
  children: ReactNode;
  index?: number;
}) {
  const [open, setOpen] = useState(false);
  const contentRef = useRef<HTMLDivElement>(null);
  const itemRef = useRef<HTMLDivElement>(null);
  const [height, setHeight] = useState(0);
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    if (contentRef.current) {
      setHeight(contentRef.current.scrollHeight);
    }
  }, [open, children]);

  useEffect(() => {
    const el = itemRef.current;
    if (!el) return;
    const observer = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting) {
          setVisible(true);
          observer.disconnect();
        }
      },
      { threshold: 0.1 },
    );
    observer.observe(el);
    return () => observer.disconnect();
  }, []);

  return (
    <div
      ref={itemRef}
      className="border-b border-border last:border-b-0 transition-all duration-600 ease-[cubic-bezier(0.22,1,0.36,1)]"
      style={{
        opacity: visible ? 1 : 0,
        transform: visible ? "translateY(0)" : "translateY(16px)",
        transitionDelay: `${index * 100}ms`,
      }}
    >
      <button
        type="button"
        onClick={() => setOpen(!open)}
        className="flex w-full cursor-pointer items-center justify-between gap-4 border-0 bg-transparent py-5 text-left font-[inherit]"
      >
        <span className="text-[15px] font-medium text-ink">{question}</span>
        <span className="relative flex h-5 w-5 shrink-0 items-center justify-center text-muted">
          <span
            className="absolute h-[1.5px] w-3 rounded-full bg-current transition-transform duration-300 ease-[cubic-bezier(0.4,0,0.2,1)]"
          />
          <span
            className="absolute h-[1.5px] w-3 rounded-full bg-current transition-transform duration-300 ease-[cubic-bezier(0.4,0,0.2,1)]"
            style={{ transform: open ? "rotate(0deg)" : "rotate(90deg)" }}
          />
        </span>
      </button>
      <div
        ref={contentRef}
        className="overflow-hidden transition-all duration-400 ease-[cubic-bezier(0.4,0,0.2,1)]"
        style={{
          maxHeight: open ? `${height}px` : "0px",
          opacity: open ? 1 : 0,
          transform: open ? "translateY(0)" : "translateY(-4px)",
        }}
      >
        <div className="pb-5 text-[13px] leading-[1.6] text-muted">
          {children}
        </div>
      </div>
    </div>
  );
}
