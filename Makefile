envelope_code := U+F0E0
brand_codes := U+F0E1,U+F09B,U+F16D,U+F39E,U+F2C6,U+F189,U+E61B,U+F167
GALLERY_SOURCE_DIR := gallery
GALLERY_OUTPUT_DIR := static/gallery
PORTFOLIO_CONTENT_DIR := content/portfolio
ALBUM_DIRS := $(shell find $(GALLERY_SOURCE_DIR) -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
ALBUM_SLUGS := $(notdir $(ALBUM_DIRS))
UNAME_S := $(shell uname -s)

.DEFAULT_GOAL := help

CONTAINER_CLI ?= container
CONTAINER_IMAGE ?= lumora-build
CONTAINER_PLATFORM ?= linux/amd64
CONTAINER_RUN_PLATFORM_FLAGS ?= --platform $(CONTAINER_PLATFORM) --rosetta
CONTAINER_RUN ?= $(CONTAINER_CLI) run --remove \
	$(CONTAINER_RUN_PLATFORM_FLAGS) \
	--user "$$(id -u):$$(id -g)" \
	-e HOME=/tmp \
	-e npm_config_cache=/tmp/.npm \
	-e CLOUDFLARE_API_TOKEN \
	-v "$$(pwd):/site" \
	-w /site

ifeq ($(UNAME_S),Darwin)
SED_INPLACE ?= sed -i ''
else
SED_INPLACE ?= sed -i
endif

FINAL_RESOLUTION:=2000x1250
THUMBNAIL_RESOLUTION:= 256x160^
# 360x225^
COPYRIGHT:="(c) Ignat Kudriavtsev"
CONTACT:="ignat@lumora.fi"
WRANGLER ?= npx wrangler

.PHONY: help
help:
	@awk -F ':|##' '/^[^\t].+?:.*?##/ {printf "\033[36m%-30s\033[0m %s\n", $$1, $$NF }' $(MAKEFILE_LIST)

.PHONY: install
install: ## Install local host build and deploy dependencies
	brew update
	brew upgrade
	brew install zola
	brew install imagemagick
	brew install ghostscript
	brew install exiftool
	brew install npm
	brew cleanup
	npm install wrangler --save-dev
	npm install terser -g

.PHONY: resize
resize: ## Regenerate processed gallery images and thumbnails
	@test -n "$(ALBUM_SLUGS)" || { echo "No album directories found under $(GALLERY_SOURCE_DIR)/" >&2; exit 1; }
	@for album in $(ALBUM_DIRS); do \
		test -f "$$album/album.toml" || { echo "Missing album sidecar: $$album/album.toml" >&2; exit 1; }; \
	done
	rm -rf $(GALLERY_OUTPUT_DIR)
	@for album in $(ALBUM_DIRS); do \
		slug=$$(basename "$$album"); \
		mkdir -p "$(GALLERY_OUTPUT_DIR)/$$slug/thumbnails"; \
		for source in "$$album"/*.jpg; do \
			test -e "$$source" || continue; \
			name=$$(basename "$$source" .jpg); \
			echo "$$slug/$$name"; \
			$(call prepare_full_image_webp,$$source,$(GALLERY_OUTPUT_DIR)/$$slug/$$name.webp); \
			$(call prepare_thumbnail,$$source,$(GALLERY_OUTPUT_DIR)/$$slug/thumbnails/$$name.jpg); \
			exiftool -all= -overwrite_original "$(GALLERY_OUTPUT_DIR)/$$slug/thumbnails/$$name.jpg"; \
			exiftool -all= -Copyright=$(COPYRIGHT) -IPTC:CopyrightNotice=$(COPYRIGHT) -Rights=$(COPYRIGHT) -Credit=$(COPYRIGHT) -Creator=$(COPYRIGHT) -Author=$(COPYRIGHT) -Contact=$(CONTACT) -overwrite_original "$(GALLERY_OUTPUT_DIR)/$$slug/$$name.webp"; \
		done; \
	done

.PHONY: content
content: ## Regenerate generated portfolio content stubs
	@test -n "$(ALBUM_SLUGS)" || { echo "No album directories found under $(GALLERY_SOURCE_DIR)/" >&2; exit 1; }
	@for album in $(ALBUM_DIRS); do \
		test -f "$$album/album.toml" || { echo "Missing album sidecar: $$album/album.toml" >&2; exit 1; }; \
	done
	rm -rf $(PORTFOLIO_CONTENT_DIR)
	mkdir -p $(PORTFOLIO_CONTENT_DIR)
	printf '+++\ntitle = "Portfolio"\ntemplate = "portfolio.html"\n+++\n' > $(PORTFOLIO_CONTENT_DIR)/_index.md
	@for slug in $(ALBUM_SLUGS); do \
		printf '+++\ntemplate = "album.html"\n\n[extra]\nslug = "%s"\n+++\n' "$$slug" > "$(PORTFOLIO_CONTENT_DIR)/$$slug.md"; \
	done

.PHONY: build
build: resize content ## Regenerate gallery assets, portfolio stubs, and build the Zola site
	zola build

.PHONY: build-fast
build-fast: ## Build the Zola site without regenerating images
	zola build

.PHONY: minify
minify: build ## Build and minify production assets
	cleancss -O2 --output ./public/css/main.min.css ./public/css/main.css
	rm -f public/css/main.css
	$(SED_INPLACE) 's/css\/main.css/css\/main.min.css/g' ./public/index.html

	$(call subset_font,fa-regular-400,$(envelope_code))

.PHONY: format
format: ## Format Markdown, TOML, and JSON files
	dprint fmt

.PHONY: format-check
format-check: ## Check Markdown, TOML, and JSON formatting
	dprint check

.PHONY: deploy
deploy: minify ## Deploy production build to Cloudflare Pages
	$(WRANGLER) pages deploy public --project-name=lumora-fi

.PHONY: preview
preview: minify ## Deploy preview build to Cloudflare Pages preview branch
	$(WRANGLER) pages deploy public --project-name=lumora-fi --branch=preview

.PHONY: docker-image
docker-image: ## Build the local apple/container build image
	$(CONTAINER_CLI) build --platform $(CONTAINER_PLATFORM) -t $(CONTAINER_IMAGE) .

.PHONY: docker-build
docker-build: docker-image ## Build the site inside apple/container
	$(CONTAINER_RUN) $(CONTAINER_IMAGE) make build

.PHONY: docker-build-fast
docker-build-fast: docker-image ## Run zola build inside apple/container without regenerating images
	$(CONTAINER_RUN) $(CONTAINER_IMAGE) make build-fast

.PHONY: docker-minify
docker-minify: docker-image ## Build and minify production assets inside apple/container
	$(CONTAINER_RUN) $(CONTAINER_IMAGE) make minify

.PHONY: docker-format
docker-format: docker-image ## Format Markdown, TOML, and JSON files inside apple/container
	$(CONTAINER_RUN) $(CONTAINER_IMAGE) make format

.PHONY: docker-format-check
docker-format-check: docker-image ## Check Markdown, TOML, and JSON formatting inside apple/container
	$(CONTAINER_RUN) $(CONTAINER_IMAGE) make format-check

.PHONY: docker-preview
docker-preview: docker-image ## Deploy a Cloudflare Pages preview from apple/container
	$(CONTAINER_RUN) $(CONTAINER_IMAGE) make WRANGLER=wrangler preview

.PHONY: docker-deploy
docker-deploy: docker-image ## Deploy production to Cloudflare Pages from apple/container
	$(CONTAINER_RUN) $(CONTAINER_IMAGE) make WRANGLER=wrangler deploy

define prepare_full_image
	magick "$(1)" -fill white  -undercolor '#00000080' -gravity SouthEast -annotate +0+5 $(COPYRIGHT) \
		-background white -gravity center -extent $(FINAL_RESOLUTION) \
		"$(2)"
endef

define prepare_full_image_webp
	magick "$(1)" -fill white  -undercolor '#00000080' -gravity SouthEast -annotate +0+5 $(COPYRIGHT) \
		-background white -gravity center -extent $(FINAL_RESOLUTION) \
		-quality 90 -define webp:lossless=false -define webp:method=6 \
		"$(2)"
endef

define prepare_thumbnail
	magick "$(1)" -adaptive-resize $(THUMBNAIL_RESOLUTION) \
		-extent $(THUMBNAIL_RESOLUTION) \
		"$(2)"
endef

define subset_font
	pyftsubset "./static/webfonts/$(1).ttf" --output-file="public/webfonts/$(1).subset.ttf" --layout-features='*' --unicodes=$(2)
	$(SED_INPLACE) 's/$(1).ttf/$(1).subset.ttf/g' ./public/css/main.min.css
	rm -f public/webfonts/$(1).ttf

	pyftsubset "./static/webfonts/$(1).ttf" --output-file="public/webfonts/$(1).subset.woff2" --layout-features='*' --flavor=woff2 --with-zopfli --unicodes=$(2)
	$(SED_INPLACE) 's/$(1).woff2/$(1).subset.woff2/g' ./public/css/main.min.css
	rm -f public/webfonts/$(1).woff2
endef
