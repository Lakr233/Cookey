import { useRef, useEffect, useState, type ReactNode } from "react";

export default function StepCard({
  number,
  title,
  children,
  position,
}: {
  number: string;
  title: string;
  children: ReactNode;
  position: "first" | "last";
}) {
  const ref = useRef<HTMLDivElement>(null);
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const observer = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting) {
          setVisible(true);
          observer.disconnect();
        }
      },
      { threshold: 0.15 },
    );
    observer.observe(el);
    return () => observer.disconnect();
  }, []);

  const delay = position === "first" ? "0ms" : "150ms";

  return (
    <div
      ref={ref}
      className="rounded-xl bg-surface p-[28px_24px] transition-all duration-700 ease-[cubic-bezier(0.22,1,0.36,1)]"
      style={{
        opacity: visible ? 1 : 0,
        transform: visible ? "translateY(0)" : "translateY(24px)",
        transitionDelay: delay,
      }}
    >
      <p className="mb-4 font-mono text-[28px] font-bold tracking-[-0.04em] text-muted/30">
        {number}
      </p>
      <h3 className="mb-2 text-[15px] font-semibold tracking-[-0.01em]">
        {title}
      </h3>
      <p className="text-[13.5px] leading-[1.6] text-muted">{children}</p>
    </div>
  );
}
