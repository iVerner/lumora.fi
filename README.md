# lumora.fi

Sources for https://lumora.fi site.

The site is generated with [Zola](https://www.getzola.org).

## Containerized build

The normal build can run without installing Zola, ImageMagick, ExifTool,
Ghostscript, Node tooling, or fonttools on the host. The Makefile uses
Apple's `container` CLI and builds the image for `linux/amd64` with Rosetta
enabled at runtime:

```sh
make docker-build
```

Useful container targets:

- `make docker-build` - rebuild generated gallery assets and run `zola build`.
- `make docker-build-fast` - run `zola build` without regenerating images.
- `make docker-minify` - run the full minified production build.
- `make docker-preview` - deploy a Cloudflare Pages preview.
- `make docker-deploy` - deploy production to Cloudflare Pages.

Preview and deploy targets still require an explicit release decision and a
`CLOUDFLARE_API_TOKEN` in the host environment. The token is passed into the
container at runtime and is not baked into the Docker image.
