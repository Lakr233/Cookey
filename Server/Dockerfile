FROM swift:6.0-jammy AS build

WORKDIR /app

COPY Package.swift ./
RUN swift package resolve

COPY Sources ./Sources
RUN swift build -c release --product Server

FROM swift:6.0-jammy

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /app/.build/release/Server /usr/local/bin/Server

ENV COOKEY_HOST=0.0.0.0
ENV COOKEY_PORT=5800
ENV COOKEY_PUBLIC_URL=https://api.cookey.sh

EXPOSE 5800

ENTRYPOINT ["/usr/local/bin/Server"]
