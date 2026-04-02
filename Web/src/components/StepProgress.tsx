import React from "react";

interface StepProgressProps {
  current: 1 | 2 | 3;
}

const stepLabels: Record<number, string> = {
  1: "Create",
  2: "Login",
  3: "Result",
};

export default function StepProgress({ current }: StepProgressProps) {
  const steps = [1, 2, 3] as const;

  const getStepClasses = (step: number) => {
    if (step < current) {
      // Completed
      return "border border-accent/50 text-accent bg-transparent";
    } else if (step === current) {
      // Active
      return "bg-accent text-black font-bold shadow-[0_0_16px_rgba(74,222,128,0.25)]";
    } else {
      // Future
      return "border border-border text-muted bg-transparent";
    }
  };

  const getConnectorClasses = (step: number) => {
    if (step < current) {
      return "bg-accent/40";
    }
    return "bg-border";
  };

  return (
    <div className="flex items-center justify-center">
      {steps.map((step, index) => (
        <React.Fragment key={step}>
          <div
            className={`flex items-center justify-center gap-2 px-4 py-2 rounded-full text-sm ${getStepClasses(
              step
            )}`}
          >
            <span className="flex items-center justify-center w-5 h-5 rounded-full text-xs">
              {step < current ? (
                <svg
                  className="w-4 h-4"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    strokeWidth={2}
                    d="M5 13l4 4L19 7"
                  />
                </svg>
              ) : (
                step
              )}
            </span>
            <span className="font-medium">{stepLabels[step]}</span>
          </div>
          {index < steps.length - 1 && (
            <div className={`w-8 sm:w-12 h-px mx-1 ${getConnectorClasses(step)}`} />
          )}
        </React.Fragment>
      ))}
    </div>
  );
}