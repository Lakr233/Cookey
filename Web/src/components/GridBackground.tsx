export default function GridBackground() {
  return (
    <div
      className="pointer-events-none absolute inset-0 overflow-hidden opacity-[0.02]"
      aria-hidden="true"
      style={{
        backgroundImage: "url(/grid-bg.svg)",
        backgroundRepeat: "repeat",
        backgroundSize: "314px",
        backgroundPosition: "-15px -15px",
      }}
    />
  );
}
