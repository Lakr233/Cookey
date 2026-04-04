import { useRef, useEffect, useState, type ReactNode } from "react";

export default function PropertyCard({
  icon,
  title,
  children,
  index = 0,
}: {
  icon: ReactNode;
  title: string;
  children: ReactNode;
  index?: number;
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

  return (
    <div
      ref={ref}
      data-visible={visible}
      className="group/card rounded-[10px] border border-border bg-surface p-6 transition-all duration-700 ease-[cubic-bezier(0.22,1,0.36,1)] hover:border-ink/15 hover:shadow-lg hover:-translate-y-0.5"
      style={{
        opacity: visible ? 1 : 0,
        transform: visible ? "translateY(0)" : "translateY(24px)",
        transitionDelay: `${index * 120}ms`,
      }}
    >
      <div className="mb-3 text-[22px]">{icon}</div>
      <h3 className="mb-[6px] text-sm font-semibold">{title}</h3>
      <p className="text-[13px] leading-[1.55] text-muted">{children}</p>
    </div>
  );
}
