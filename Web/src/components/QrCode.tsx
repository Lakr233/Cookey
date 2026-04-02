import { useEffect, useState } from "react";
import { toString } from "qrcode";

type QrCodeProps = {
  value?: string;
  size?: number;
};

function DecorativeQrCode({ size }: { size: number }) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 21 21"
      shapeRendering="crispEdges"
      xmlns="http://www.w3.org/2000/svg"
      style={{ display: "block" }}
    >
      <rect width="21" height="21" fill="#0d0d0d" />
      <rect x="1" y="1" width="7" height="7" fill="#e8e8e8" />
      <rect x="2" y="2" width="5" height="5" fill="#0d0d0d" />
      <rect x="3" y="3" width="3" height="3" fill="#e8e8e8" />
      <rect x="13" y="1" width="7" height="7" fill="#e8e8e8" />
      <rect x="14" y="2" width="5" height="5" fill="#0d0d0d" />
      <rect x="15" y="3" width="3" height="3" fill="#e8e8e8" />
      <rect x="1" y="13" width="7" height="7" fill="#e8e8e8" />
      <rect x="2" y="14" width="5" height="5" fill="#0d0d0d" />
      <rect x="3" y="15" width="3" height="3" fill="#e8e8e8" />
      <rect x="9" y="1" width="1" height="1" fill="#e8e8e8" />
      <rect x="11" y="1" width="1" height="1" fill="#e8e8e8" />
      <rect x="8" y="3" width="1" height="1" fill="#e8e8e8" />
      <rect x="10" y="3" width="1" height="1" fill="#e8e8e8" />
      <rect x="12" y="3" width="1" height="1" fill="#e8e8e8" />
      <rect x="9" y="5" width="1" height="1" fill="#e8e8e8" />
      <rect x="8" y="8" width="1" height="1" fill="#e8e8e8" />
      <rect x="10" y="8" width="1" height="1" fill="#e8e8e8" />
      <rect x="12" y="8" width="1" height="1" fill="#e8e8e8" />
      <rect x="1" y="9" width="1" height="1" fill="#e8e8e8" />
      <rect x="3" y="9" width="1" height="1" fill="#e8e8e8" />
      <rect x="5" y="9" width="1" height="1" fill="#e8e8e8" />
      <rect x="9" y="9" width="1" height="1" fill="#e8e8e8" />
      <rect x="11" y="9" width="1" height="1" fill="#e8e8e8" />
      <rect x="13" y="9" width="1" height="1" fill="#e8e8e8" />
      <rect x="15" y="9" width="1" height="1" fill="#e8e8e8" />
      <rect x="17" y="9" width="1" height="1" fill="#e8e8e8" />
      <rect x="19" y="9" width="1" height="1" fill="#e8e8e8" />
      <rect x="1" y="11" width="1" height="1" fill="#e8e8e8" />
      <rect x="5" y="11" width="1" height="1" fill="#e8e8e8" />
      <rect x="8" y="11" width="1" height="1" fill="#e8e8e8" />
      <rect x="10" y="11" width="1" height="1" fill="#e8e8e8" />
      <rect x="14" y="11" width="1" height="1" fill="#e8e8e8" />
      <rect x="16" y="11" width="1" height="1" fill="#e8e8e8" />
      <rect x="18" y="11" width="1" height="1" fill="#e8e8e8" />
      <rect x="9" y="13" width="1" height="1" fill="#e8e8e8" />
      <rect x="11" y="13" width="1" height="1" fill="#e8e8e8" />
      <rect x="13" y="13" width="1" height="1" fill="#e8e8e8" />
      <rect x="17" y="13" width="1" height="1" fill="#e8e8e8" />
      <rect x="19" y="13" width="1" height="1" fill="#e8e8e8" />
      <rect x="8" y="15" width="1" height="1" fill="#e8e8e8" />
      <rect x="12" y="15" width="1" height="1" fill="#e8e8e8" />
      <rect x="14" y="15" width="1" height="1" fill="#e8e8e8" />
      <rect x="16" y="15" width="1" height="1" fill="#e8e8e8" />
      <rect x="18" y="15" width="1" height="1" fill="#e8e8e8" />
      <rect x="9" y="17" width="1" height="1" fill="#e8e8e8" />
      <rect x="11" y="17" width="1" height="1" fill="#e8e8e8" />
      <rect x="15" y="17" width="1" height="1" fill="#e8e8e8" />
      <rect x="19" y="17" width="1" height="1" fill="#e8e8e8" />
      <rect x="8" y="19" width="1" height="1" fill="#e8e8e8" />
      <rect x="10" y="19" width="1" height="1" fill="#e8e8e8" />
      <rect x="13" y="19" width="1" height="1" fill="#e8e8e8" />
      <rect x="17" y="19" width="1" height="1" fill="#e8e8e8" />
    </svg>
  );
}

export default function QrCode({ value, size = 120 }: QrCodeProps) {
  const [svgMarkup, setSvgMarkup] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;

    if (!value) {
      setSvgMarkup(null);
      return () => {
        cancelled = true;
      };
    }

    void toString(value, {
      color: {
        dark: "#e8e8e8",
        light: "#0d0d0d",
      },
      margin: 0,
      type: "svg",
      width: size,
    }).then((markup) => {
      if (!cancelled) {
        setSvgMarkup(markup);
      }
    });

    return () => {
      cancelled = true;
    };
  }, [size, value]);

  if (!value || !svgMarkup) {
    return <DecorativeQrCode size={size} />;
  }

  return (
    <div
      aria-label="Cookey login QR code"
      className="flex justify-center"
      dangerouslySetInnerHTML={{ __html: svgMarkup }}
      role="img"
    />
  );
}
