import {
  useState,
  useEffect,
  Children,
  type ReactNode,
  type ReactElement,
} from "react";

export default function TerminalLines({
  children,
  lineDelay = 400,
  startDelay = 0,
}: {
  children: ReactNode;
  lineDelay?: number;
  startDelay?: number;
}) {
  const items = Children.toArray(children) as ReactElement[];
  const [visible, setVisible] = useState(0);

  useEffect(() => {
    let interval: ReturnType<typeof setInterval> | undefined;
    const start = setTimeout(() => {
      let i = 0;
      interval = setInterval(() => {
        i++;
        setVisible(i);
        if (i >= items.length && interval) {
          clearInterval(interval);
          interval = undefined;
        }
      }, lineDelay);
    }, startDelay);

    return () => {
      clearTimeout(start);
      if (interval) clearInterval(interval);
    };
  }, [items.length, lineDelay, startDelay]);

  return (
    <>
      {items.map((child, i) => (
        <div
          key={i}
          className="transition-all duration-300"
          style={{
            opacity: i < visible ? 1 : 0,
            transform: i < visible ? "translateY(0)" : "translateY(4px)",
          }}
        >
          {child}
        </div>
      ))}
    </>
  );
}
