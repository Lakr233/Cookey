import Container from "./Container";

export default function Footer({
  rightLink,
}: {
  rightLink?: { label: string; href: string };
}) {
  return (
    <footer className="border-t border-border py-8">
      <Container>
        <div className="flex flex-col gap-4 xs:flex-row xs:items-center xs:justify-between">
          <p className="text-[13px] text-muted">
            Cookey for humans and agents.
          </p>
          <div className="flex flex-wrap items-center gap-x-5 gap-y-2">
            <a
              href="https://apps.apple.com/app/cookey/id6745136531"
              className="text-[13px] text-muted no-underline transition-colors duration-150 hover:text-ink"
            >
              Get iOS App
            </a>
            <a
              href="https://github.com/Lakr233/Cookey"
              className="text-[13px] text-muted no-underline transition-colors duration-150 hover:text-ink"
            >
              Source Code
            </a>
            <a
              href="/llms.txt"
              className="text-[13px] text-muted no-underline transition-colors duration-150 hover:text-ink"
            >
              llms.txt
            </a>
            {rightLink && (
              <a
                href={rightLink.href}
                className="text-[13px] text-muted no-underline transition-colors duration-150 hover:text-ink"
              >
                {rightLink.label}
              </a>
            )}
          </div>
        </div>
      </Container>
    </footer>
  );
}
