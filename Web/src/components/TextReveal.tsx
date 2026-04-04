import { useState, useEffect, type ReactNode } from "react";

interface TextRevealProps {
  children: ReactNode;
  charDelay?: number;
  startDelay?: number;
}

function flattenText(node: ReactNode): string {
  if (typeof node === "string") return node;
  if (typeof node === "number") return String(node);
  if (!node) return "";
  if (Array.isArray(node)) return node.map(flattenText).join("");
  if (typeof node === "object" && "props" in node) {
    if (node.type === "br") return "\n";
    return flattenText(node.props.children);
  }
  return "";
}

export default function TextReveal({
  children,
  charDelay = 25,
  startDelay = 2200,
}: TextRevealProps) {
  const fullText = flattenText(children);
  const [revealed, setRevealed] = useState(0);

  useEffect(() => {
    const timer = setTimeout(() => {
      let i = 0;
      const interval = setInterval(() => {
        i++;
        setRevealed(i);
        if (i >= fullText.length) clearInterval(interval);
      }, charDelay);
      return () => clearInterval(interval);
    }, startDelay);
    return () => clearTimeout(timer);
  }, [fullText, charDelay, startDelay]);

  let idx = 0;

  function renderNode(node: ReactNode): ReactNode {
    if (typeof node === "string") {
      return node.split("").map((char) => {
        const ci = idx++;
        return (
          <span
            key={ci}
            className="transition-colors duration-300"
            style={{ color: ci < revealed ? undefined : "var(--color-border)" }}
          >
            {char}
          </span>
        );
      });
    }
    if (typeof node === "number") {
      return renderNode(String(node));
    }
    if (!node) return node;
    if (Array.isArray(node)) return node.map(renderNode);
    if (typeof node === "object" && "props" in node) {
      if (node.type === "br") {
        idx++;
        return <br key={`br-${idx}`} />;
      }
      const mapped = renderNode(node.props.children);
      return { ...node, props: { ...node.props, children: mapped } };
    }
    return node;
  }

  return <>{renderNode(children)}</>;
}
