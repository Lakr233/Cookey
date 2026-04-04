import { useState, useEffect } from "react";

interface TypewriterLine {
  text: string;
  className?: string;
}

function jitter(base: number): number {
  return base + Math.random() * base * 0.8 - base * 0.2;
}

function nextDelay(char: string, base: number): number {
  if (char === " ") return jitter(base * 0.5);
  if (",.:;!?".includes(char)) return jitter(base * 3.5);
  if (char === char.toUpperCase() && char !== char.toLowerCase()) {
    return jitter(base * 1.6);
  }
  if (Math.random() < 0.08) return jitter(base * 3);
  return jitter(base);
}

export default function Typewriter({
  lines,
  charDelay = 55,
  lineDelay = 300,
}: {
  lines: TypewriterLine[];
  charDelay?: number;
  lineDelay?: number;
}) {
  const [displayed, setDisplayed] = useState<string[]>(
    lines.map(() => ""),
  );
  const [cursorLine, setCursorLine] = useState(0);

  useEffect(() => {
    let lineIdx = 0;
    let charIdx = 0;
    let cancelled = false;

    function tick() {
      if (cancelled) return;
      if (lineIdx >= lines.length) {
        setCursorLine(-1);
        return;
      }

      const line = lines[lineIdx].text;

      if (charIdx <= line.length) {
        setDisplayed((prev) => {
          const next = [...prev];
          next[lineIdx] = line.slice(0, charIdx);
          return next;
        });
        setCursorLine(lineIdx);
        const typed = line[charIdx] ?? " ";
        charIdx++;
        setTimeout(tick, nextDelay(typed, charDelay));
      } else {
        lineIdx++;
        charIdx = 0;
        setTimeout(tick, lineDelay);
      }
    }

    const startTimer = setTimeout(tick, 500);
    return () => {
      cancelled = true;
      clearTimeout(startTimer);
    };
  }, [lines, charDelay, lineDelay]);

  return (
    <h1 className="relative mb-5 font-mono font-bold tracking-[-0.06em] text-ink leading-[1.1] text-[clamp(2.2rem,6vw,3.6rem)]" style={{ transform: "scaleY(0.9)" }}>
      <span className="invisible" aria-hidden="true">
        {lines.map((line, i) => (
          <span key={i}>
            {i > 0 && <br />}
            <span className={line.className}>{line.text}</span>
          </span>
        ))}
      </span>
      <span className="absolute inset-0">
        {lines.map((line, i) => (
          <span key={i}>
            {i > 0 && <br />}
            <span className={line.className}>
              {displayed[i]}
              {cursorLine === i && (
                <span className="animate-blink">|</span>
              )}
            </span>
          </span>
        ))}
      </span>
    </h1>
  );
}
