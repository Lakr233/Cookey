interface StepProgressProps {
  current: 1 | 2 | 3;
}

const steps = [
  { num: 1, label: "Create" },
  { num: 2, label: "Monitor" },
  { num: 3, label: "Result" },
] as const;

export default function StepProgress({ current }: StepProgressProps) {
  return (
    <nav
      aria-label="Test login progress"
      className="flex items-center justify-center"
    >
      {steps.map((step, index) => {
        const isActive = step.num === current;
        const isCompleted = step.num < current;
        const isLast = index === steps.length - 1;

        return (
          <div key={step.num} className="contents">
            <div className="flex flex-col items-center gap-2">
              <div
                aria-current={isActive ? "step" : undefined}
                className={`
                  relative flex h-8 min-w-[2rem] items-center justify-center rounded-full px-3
                  font-mono text-xs font-medium transition-all duration-300
                  ${
                    isActive
                      ? "bg-accent text-bg shadow-[0_0_16px_rgba(74,222,128,0.25)]"
                      : isCompleted
                        ? "bg-accent/20 text-accent border border-accent/30"
                        : "bg-transparent border border-border text-muted"
                  }
                `}
              >
                {isCompleted ? (
                  <svg
                    aria-hidden="true"
                    className="h-4 w-4"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke="currentColor"
                    strokeWidth={2.5}
                  >
                    <path
                      strokeLinecap="round"
                      strokeLinejoin="round"
                      d="M5 13l4 4L19 7"
                    />
                  </svg>
                ) : (
                  <span>{step.num}</span>
                )}
                {isActive && (
                  <span className="absolute inset-0 animate-ping rounded-full bg-accent/20 pointer-events-none" />
                )}
              </div>
              <span
                className={`
                  text-[11px] font-medium tracking-wide transition-colors duration-300
                  ${isActive ? "text-accent" : isCompleted ? "text-ink" : "text-muted"}
                `}
              >
                {step.label}
              </span>
            </div>
            {!isLast && (
              <div
                aria-hidden="true"
                className={`mx-2 h-[2px] w-8 sm:w-12 transition-colors duration-300 ${isCompleted ? "bg-accent/40" : "bg-border"}`}
              />
            )}
          </div>
        );
      })}
    </nav>
  );
}
