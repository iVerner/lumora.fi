latin_font_codes := U+0000-00FF,U+0131,U+0152-0153,U+02BB-02BC,U+02C6,U+02DA,U+02DC,U+0304,U+0308,U+0329,U+2000-206F,U+20AC,U+2122,U+2191,U+2193,U+2212,U+2215,U+FEFF,U+FFFD
GALLERY_SOURCE_DIR := gallery
GALLERY_OUTPUT_DIR := static/gallery
PORTFOLIO_CONTENT_DIR := content/portfolio
ALBUM_DIRS := $(shell find $(GALLERY_SOURCE_DIR) -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
ALBUM_SLUGS := $(notdir $(ALBUM_DIRS))
UNAME_S := $(shell uname -s)

.DEFAULT_GOAL := help

CONTAINER_CLI ?= container
CONTAINER_IMAGE ?= lumora-build
CONTAINER_SERVE_NAME ?= lumora-serve
CONTAINER_PLATFORM ?= linux/amd64
SITE_HOST ?= 127.0.0.1
SITE_PORT ?= 1111
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

FULL_MAX_SIZE:=2000x2000
PREVIEW_MAX_SIZE:=1200x1200
FULL_RESOLUTION:=$(FULL_MAX_SIZE)>
PREVIEW_RESOLUTION:=$(PREVIEW_MAX_SIZE)>
COVER_RESOLUTION:=1000x1250^
FEATURED_SMALL_RESOLUTION:=384x512^
FEATURED_RESOLUTION:=672x896^
HERO_SMALL_RESOLUTION:=1440x960^
# 360x225^
COPYRIGHT:="(c) Ignat Kudriavtsev"
CONTACT:="ignat@lumora.fi"
WRANGLER ?= npx wrangler
PYTHON ?= python3

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
resize: ## Regenerate processed gallery images and derivatives
	@test -n "$(ALBUM_SLUGS)" || { echo "No album directories found under $(GALLERY_SOURCE_DIR)/" >&2; exit 1; }
	@for album in $(ALBUM_DIRS); do \
		test -f "$$album/album.toml" || { echo "Missing album sidecar: $$album/album.toml" >&2; exit 1; }; \
	done
	rm -rf $(GALLERY_OUTPUT_DIR)
	@for album in $(ALBUM_DIRS); do \
		slug=$$(basename "$$album"); \
		mkdir -p "$(GALLERY_OUTPUT_DIR)/$$slug/previews"; \
		python3 scripts/album_image_order.py "$$album" | while IFS='	' read -r source_file seq_stem; do \
			source="$$album/$$source_file"; \
			echo "$$slug/$$seq_stem"; \
			$(call prepare_full_image_webp,$$source,$(GALLERY_OUTPUT_DIR)/$$slug/$$seq_stem.webp); \
			$(call prepare_preview_webp,$$source,$(GALLERY_OUTPUT_DIR)/$$slug/previews/$$seq_stem.webp); \
			exiftool -all= -Copyright=$(COPYRIGHT) -IPTC:CopyrightNotice=$(COPYRIGHT) -Rights=$(COPYRIGHT) -Credit=$(COPYRIGHT) -Creator=$(COPYRIGHT) -Author=$(COPYRIGHT) -Contact=$(CONTACT) -overwrite_original "$(GALLERY_OUTPUT_DIR)/$$slug/$$seq_stem.webp"; \
			exiftool -all= -Copyright=$(COPYRIGHT) -IPTC:CopyrightNotice=$(COPYRIGHT) -Rights=$(COPYRIGHT) -Credit=$(COPYRIGHT) -Creator=$(COPYRIGHT) -Author=$(COPYRIGHT) -Contact=$(CONTACT) -overwrite_original "$(GALLERY_OUTPUT_DIR)/$$slug/previews/$$seq_stem.webp"; \
		done; \
	done
	@python3 scripts/write_album_dimensions.py --gallery $(GALLERY_SOURCE_DIR) --output $(GALLERY_OUTPUT_DIR) --full-size $(FULL_MAX_SIZE) --preview-size $(PREVIEW_MAX_SIZE)
	@python3 scripts/list_album_derivatives.py cover --gallery $(GALLERY_SOURCE_DIR) | while IFS='	' read -r slug file seq_stem; do \
		source="$(GALLERY_SOURCE_DIR)/$$slug/$$file"; \
		output="$(GALLERY_OUTPUT_DIR)/$$slug/covers/$$seq_stem.webp"; \
		mkdir -p "$(GALLERY_OUTPUT_DIR)/$$slug/covers"; \
		echo "$$slug/covers/$$seq_stem"; \
		$(call prepare_cover_webp,$$source,$$output); \
		exiftool -all= -Copyright=$(COPYRIGHT) -IPTC:CopyrightNotice=$(COPYRIGHT) -Rights=$(COPYRIGHT) -Credit=$(COPYRIGHT) -Creator=$(COPYRIGHT) -Author=$(COPYRIGHT) -Contact=$(CONTACT) -overwrite_original "$$output"; \
	done
	@python3 scripts/list_album_derivatives.py featured --gallery $(GALLERY_SOURCE_DIR) | while IFS='	' read -r slug file seq_stem; do \
		source="$(GALLERY_SOURCE_DIR)/$$slug/$$file"; \
		output="$(GALLERY_OUTPUT_DIR)/$$slug/featured/$$seq_stem.webp"; \
		output_small="$(GALLERY_OUTPUT_DIR)/$$slug/featured-small/$$seq_stem.webp"; \
		mkdir -p "$(GALLERY_OUTPUT_DIR)/$$slug/featured" "$(GALLERY_OUTPUT_DIR)/$$slug/featured-small"; \
		echo "$$slug/featured/$$seq_stem"; \
		$(call prepare_featured_small_webp,$$source,$$output_small); \
		$(call prepare_featured_webp,$$source,$$output); \
		exiftool -all= -Copyright=$(COPYRIGHT) -IPTC:CopyrightNotice=$(COPYRIGHT) -Rights=$(COPYRIGHT) -Credit=$(COPYRIGHT) -Creator=$(COPYRIGHT) -Author=$(COPYRIGHT) -Contact=$(CONTACT) -overwrite_original "$$output_small"; \
		exiftool -all= -Copyright=$(COPYRIGHT) -IPTC:CopyrightNotice=$(COPYRIGHT) -Rights=$(COPYRIGHT) -Credit=$(COPYRIGHT) -Creator=$(COPYRIGHT) -Author=$(COPYRIGHT) -Contact=$(CONTACT) -overwrite_original "$$output"; \
	done
	@python3 scripts/list_album_derivatives.py home_hero --gallery $(GALLERY_SOURCE_DIR) | while IFS='	' read -r slug file seq_stem; do \
		source="$(GALLERY_SOURCE_DIR)/$$slug/$$file"; \
		output="$(GALLERY_OUTPUT_DIR)/$$slug/hero/$$seq_stem.webp"; \
		mkdir -p "$(GALLERY_OUTPUT_DIR)/$$slug/hero"; \
		echo "$$slug/hero/$$seq_stem"; \
		$(call prepare_hero_small_webp,$$source,$$output); \
		exiftool -all= -Copyright=$(COPYRIGHT) -IPTC:CopyrightNotice=$(COPYRIGHT) -Rights=$(COPYRIGHT) -Credit=$(COPYRIGHT) -Creator=$(COPYRIGHT) -Author=$(COPYRIGHT) -Contact=$(CONTACT) -overwrite_original "$$output"; \
	done

.PHONY: content
content: ## Regenerate generated portfolio content stubs
	@test -n "$(ALBUM_SLUGS)" || { echo "No album directories found under $(GALLERY_SOURCE_DIR)/" >&2; exit 1; }
	@for album in $(ALBUM_DIRS); do \
		test -f "$$album/album.toml" || { echo "Missing album sidecar: $$album/album.toml" >&2; exit 1; }; \
	done
	# Zola needs route stubs, but album metadata stays in ignored gallery sidecars.
	rm -rf $(PORTFOLIO_CONTENT_DIR)
	mkdir -p $(PORTFOLIO_CONTENT_DIR)
	printf '+++\ntitle = "Portfolio"\ntemplate = "portfolio.html"\n+++\n' > $(PORTFOLIO_CONTENT_DIR)/_index.md
	@for slug in $(ALBUM_SLUGS); do \
		printf '+++\ntemplate = "album.html"\n\n[extra]\nslug = "%s"\n+++\n' "$$slug" > "$(PORTFOLIO_CONTENT_DIR)/$$slug.md"; \
	done

.PHONY: documents
documents: ## Regenerate downloadable document PDFs
	$(PYTHON) scripts/generate_documents.py

.PHONY: build
build: resize content documents ## Regenerate gallery assets, portfolio stubs, documents, and build the Zola site
	zola build

.PHONY: build-fast
build-fast: documents ## Build the Zola site without regenerating images
	zola build

.PHONY: serve
serve: ## Serve the Zola site locally without regenerating images
	zola serve --interface 0.0.0.0 --port $(SITE_PORT) --base-url http://$(SITE_HOST)

.PHONY: minify
minify: build ## Build and minify production assets
	cleancss -O2 --output ./public/css/main.min.css ./public/css/main.css
	rm -f public/css/main.css
	find ./public -name '*.html' -exec \
		$(SED_INPLACE) 's/css\/main.css/css\/main.min.css/g' {} +

	$(call subset_font,jost-normal-400,$(latin_font_codes))
	$(call subset_font,jost-normal-500,$(latin_font_codes))
	$(call subset_font,jost-normal-700,$(latin_font_codes))
	$(call subset_font,gilda-display-normal-400,$(latin_font_codes))

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

.PHONY: docker-documents
docker-documents: docker-image ## Regenerate downloadable document PDFs inside apple/container
	$(CONTAINER_RUN) $(CONTAINER_IMAGE) make documents

.PHONY: docker-serve-stop
docker-serve-stop: ## Stop an existing local serve container on SITE_PORT
	@$(CONTAINER_CLI) stop --time 2 $(CONTAINER_SERVE_NAME) >/dev/null 2>&1 || true
	@$(CONTAINER_CLI) rm --force $(CONTAINER_SERVE_NAME) >/dev/null 2>&1 || true

.PHONY: docker-serve
docker-serve: docker-image docker-serve-stop ## Serve the Zola site locally from apple/container
	@$(CONTAINER_RUN) --detach --name $(CONTAINER_SERVE_NAME) --init --publish $(SITE_PORT):$(SITE_PORT) $(CONTAINER_IMAGE) make SITE_HOST=$(SITE_HOST) SITE_PORT=$(SITE_PORT) serve
	@echo "Serving at http://$(SITE_HOST):$(SITE_PORT). Press Ctrl-C to stop."
	@trap '$(CONTAINER_CLI) stop --time 2 $(CONTAINER_SERVE_NAME) >/dev/null 2>&1 || true; exit 0' INT TERM; \
	while $(CONTAINER_CLI) inspect $(CONTAINER_SERVE_NAME) >/dev/null 2>&1; do \
		sleep 1; \
	done

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
		"$(2)"
endef

define prepare_full_image_webp
	magick "$(1)" -auto-orient -resize "$(FULL_RESOLUTION)" \
		-fill white -undercolor '#00000080' -gravity SouthEast -annotate +0+5 $(COPYRIGHT) \
		-quality 90 -define webp:lossless=false -define webp:method=6 \
		"$(2)"
endef

define prepare_preview_webp
	magick "$(1)" -auto-orient -resize "$(PREVIEW_RESOLUTION)" \
		-quality 88 -define webp:lossless=false -define webp:method=6 \
		"$(2)"
endef

define prepare_cover_webp
	magick "$(1)" -adaptive-resize $(COVER_RESOLUTION) \
		-gravity center -extent $(COVER_RESOLUTION) \
		-quality 88 -define webp:lossless=false -define webp:method=6 \
		"$(2)"
endef

define prepare_featured_small_webp
	magick "$(1)" -adaptive-resize $(FEATURED_SMALL_RESOLUTION) \
		-gravity center -extent $(FEATURED_SMALL_RESOLUTION) \
		-quality 82 -define webp:lossless=false -define webp:method=6 \
		"$(2)"
endef

define prepare_featured_webp
	magick "$(1)" -adaptive-resize $(FEATURED_RESOLUTION) \
		-gravity center -extent $(FEATURED_RESOLUTION) \
		-quality 88 -define webp:lossless=false -define webp:method=6 \
		"$(2)"
endef

define prepare_hero_small_webp
	magick "$(1)" -auto-orient -resize $(HERO_SMALL_RESOLUTION) \
		-gravity center -extent $(HERO_SMALL_RESOLUTION) \
		-quality 88 -define webp:lossless=false -define webp:method=6 \
		"$(2)"
endef

define subset_font
	pyftsubset "./static/webfonts/$(1).ttf" --output-file="public/webfonts/$(1).subset.ttf" --layout-features='*' --unicodes=$(2)
	$(SED_INPLACE) 's/$(1).ttf/$(1).subset.ttf/g' ./public/css/main.min.css
	rm -f public/webfonts/$(1).ttf

	pyftsubset "./static/webfonts/$(1).ttf" --output-file="public/webfonts/$(1).subset.woff2" --layout-features='*' --flavor=woff2 --with-zopfli --unicodes=$(2)
	$(SED_INPLACE) 's/$(1).woff2/$(1).subset.woff2/g' ./public/css/main.min.css
	find ./public -name '*.html' -exec \
		$(SED_INPLACE) 's/$(1).woff2/$(1).subset.woff2/g' {} +
	rm -f public/webfonts/$(1).woff2
endef
