FROM node:22-bookworm

ARG ZOLA_VERSION=0.19.2
ARG TARGETARCH

RUN apt-get update \
	&& apt-get install -y --no-install-recommends \
		ca-certificates \
		curl \
		fonttools \
		ghostscript \
		imagemagick \
		libimage-exiftool-perl \
		python3 \
		python3-reportlab \
		xz-utils \
	&& case "${TARGETARCH:-$(dpkg --print-architecture)}" in \
		amd64) zola_arch="x86_64-unknown-linux-gnu" ;; \
		arm64) zola_arch="aarch64-unknown-linux-gnu" ;; \
		*) echo "Unsupported architecture: ${TARGETARCH:-$(dpkg --print-architecture)}" >&2; exit 1 ;; \
	esac \
	&& curl -fsSL "https://github.com/getzola/zola/releases/download/v${ZOLA_VERSION}/zola-v${ZOLA_VERSION}-${zola_arch}.tar.gz" \
		| tar -xz -C /usr/local/bin zola \
	&& if ! command -v magick >/dev/null; then ln -s /usr/bin/convert /usr/local/bin/magick; fi \
	&& npm install -g wrangler clean-css-cli terser dprint \
	&& apt-get clean \
	&& rm -rf /var/lib/apt/lists/*

WORKDIR /site
