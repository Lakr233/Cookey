import type { ReactNode } from "react";
import Container from "./Container";

export default function SectionBlock({
  label,
  heading,
  children,
}: {
  label: string;
  heading: string;
  children: ReactNode;
}) {
  return (
    <section className="border-t border-border py-24">
      <Container>
        <p className="mb-4 text-xs font-semibold uppercase tracking-[0.1em] text-muted">
          {label}
        </p>
        <h2 className="mb-8 font-mono font-bold tracking-[-0.06em] text-[clamp(1.6rem,4vw,2.2rem)] leading-tight" style={{ transform: "scaleY(0.9)" }}>
          {heading}
        </h2>
        {children}
      </Container>
    </section>
  );
}
