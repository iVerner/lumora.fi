envelope_code := U+F0E0
brand_codes := U+F0E1,U+F09B,U+F16D,U+F39E,U+F2C6,U+F189,U+E61B,U+F167
GALLERY_FILES := $(shell ls gallery/*.jpg | sed 's/gallery\///g' | sed 's/.jpg//g')

FINAL_RESOLUTION:=2000x1250
THUMBNAIL_RESOLUTION:= 256x160^
# 360x225^
COPYRIGHT:="(c) Ignat Kudriavtsev"
CONTACT:="ignat@lumora.fi"

.PHONY: install
install:
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
resize:
	rm -f static/gallery/*.jpg
	rm -f static/gallery/*.webp
	rm -f static/gallery/thumbnails/*
	echo $(GALLERY_FILES)
	for p in  $(GALLERY_FILES); \
    do \
      echo $$p ; \
	  $(call prepare_full_image,$$p); \
	  $(call prepare_thumbnail,$$p); \
	exiftool -all= -overwrite_original static/gallery/thumbnails/$$p.jpg; \
	exiftool -all= -Copyright=$(COPYRIGHT) -IPTC:CopyrightNotice=$(COPYRIGHT) -Rights=$(COPYRIGHT) -Credit=$(COPYRIGHT) -Creator=$(COPYRIGHT) -Author=$(COPYRIGHT) -Contact=$(CONTACT) -overwrite_original static/gallery/$$p.jpg; \
    done


.PHONY: build
build: resize
	echo "$$header" > content/_index.md
	ls static/gallery/*.jpg | awk '{printf "\"%s\"",$$1}' | sed 's/""/","/g' | sed 's/static\/gallery\///g' >> content/_index.md
	echo "$$footer" >> content/_index.md

	zola build

.PHONY: minify
minify: build
	cleancss -O2 --output ./public/css/main.min.css ./public/css/main.css
	rm -f public/css/main.css
	sed -i '' 's/css\/main.css/css\/main.min.css/g' ./public/index.html

	$(call subset_font,fa-regular-400,$(envelope_code))

.PHONY: deploy
deploy: minify
	npx wrangler pages deploy public --project-name=lumora-fi

.PHONY: preview
preview: minify
	npx wrangler pages deploy public --project-name=lumora-fi --branch=preview

define header
+++
title="Lumora"
[extra]
references = [
endef
export header
define footer
]
+++
endef
export footer

define prepare_full_image
	magick gallery/$(1).jpg -fill white  -undercolor '#00000080' -gravity SouthEast -annotate +0+5 $(COPYRIGHT) \
		-background white -gravity center -extent $(FINAL_RESOLUTION) \
		static/gallery/$(1).jpg
endef

define prepare_full_image_webp
	magick gallery/$(1).jpg -fill white  -undercolor '#00000080' -gravity SouthEast -annotate +0+5 $(COPYRIGHT) \
		-background white -gravity center -extent $(FINAL_RESOLUTION) \
		-quality 90 -define webp:lossless=false -define webp:method=6 \
		static/gallery/$(1).webp
endef

define prepare_thumbnail
	magick gallery/$(1).jpg -adaptive-resize $(THUMBNAIL_RESOLUTION) \
		-extent $(THUMBNAIL_RESOLUTION) \
		static/gallery/thumbnails/$(1).jpg
endef

define subset_font
	pyftsubset "./static/webfonts/$(1).ttf" --output-file="public/webfonts/$(1).subset.ttf" --layout-features='*' --unicodes=$(2)
	sed -i '' 's/$(1).ttf/$(1).subset.ttf/g' ./public/css/main.min.css
	rm -f public/webfonts/$(1).ttf

	pyftsubset "./static/webfonts/$(1).ttf" --output-file="public/webfonts/$(1).subset.woff2" --layout-features='*' --flavor=woff2 --with-zopfli --unicodes=$(2)
	sed -i '' 's/$(1).woff2/$(1).subset.woff2/g' ./public/css/main.min.css
	rm -f public/webfonts/$(1).woff2
endef
