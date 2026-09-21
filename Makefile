APP_NAME    := ImageForgeGUI
# NAME is the kebab-case tool/repo name used for the release archive, per the
# org Release Archive Standard (<name>-v<version>-<os>-<arch>.zip). The .app
# bundle inside keeps its CamelCase name ($(APP_NAME).app).
NAME        := image-forge-gui
BUNDLE_ID   := jp.nlink.image-forge-gui
VERSION     := $(shell git describe --tags --always --dirty 2>/dev/null || echo "0.1.0")
BUILD_DIR   := .build/release
DIST_DIR    := dist
APP_BUNDLE  := $(DIST_DIR)/$(APP_NAME).app

# The image-forge CLI is the generation backend: the app drives its resident
# `serve` engine. build-app bundles the binary into Contents/Resources so the
# .app is self-contained. Override CLI_BIN to point at a freshly built binary;
# if it's missing, the app falls back to $IMAGE_FORGE_BIN / ~/bin/image-forge /
# PATH at runtime (see BinaryResolver).
# The release binary first: the CLI's `make package` leaves only
# dist/image-forge-darwin-arm64, `make build` leaves dist/image-forge.
CLI_BIN ?= $(firstword $(wildcard ../image-forge/dist/image-forge-darwin-arm64 ../image-forge/dist/image-forge))

# The CLI version this app must ship. The app's behaviour *is* the CLI's — the
# catalog it shows, the licences it reports, the models it can pull — so a
# bundle built against a stale binary ships stale behaviour with a fresh version
# number. v0.27.0 is the release that corrected a model licence that said
# commercial use was permitted when it was not; a GUI user cannot get that fix
# by updating the CLI, because a release .app resolves its bundled copy first
# and ignores $IMAGE_FORGE_BIN (see BinaryResolver). verify-release therefore
# refuses a bundle whose binary does not report this version. Bump it in the
# same commit that bundles a newer CLI.
CLI_VERSION ?= v0.27.0

# macOS Developer ID signing / notarization (see nlink-jp/.github CONVENTIONS.md
# §Code Signing → GUI apps). Pure SwiftUI/AppKit needs no JIT entitlements —
# Hardened Runtime alone suffices. --deep also signs the bundled CLI binary.
CODESIGN_IDENTITY ?= Developer ID Application
NOTARY_PROFILE    ?= nlink-jp-notary
CODESIGN_SCRIPT := scripts/codesign-darwin-app.sh
NOTARIZE_SCRIPT := scripts/notarize-darwin-app.sh

# App icon: a 1024x1024 source PNG; build-app generates AppIcon.icns into the
# bundle's Resources (sips + iconutil). Missing source → app builds without icon.
ICON_SRC := assets/AppIcon-1024.png

# macOS records the SDK an app was linked against in LC_BUILD_VERSION, and the
# system reads that field to decide which generation of window chrome to draw.
# Since the Xcode 27 / Swift 6.4 toolchain, `swift build` stamps it with the
# deployment target instead of the SDK actually used, so a release built without
# this renders with the previous design — square window corners. Passing
# -platform_version explicitly restores it. MACOS_MIN is read from Package.swift
# so there is one deployment target, not two.
MACOS_MIN := $(shell sed -n -e 's/.*\.macOS(\.v\([0-9][0-9]*\)).*/\1.0/p' \
                            -e 's/.*\.macOS("\([0-9][0-9.]*\)").*/\1/p' Package.swift | head -1)
MACOS_SDK := $(shell xcrun --sdk macosx --show-sdk-version)
SDK_LINK_FLAGS := -Xlinker -platform_version -Xlinker macos -Xlinker $(MACOS_MIN) -Xlinker $(MACOS_SDK)

.PHONY: build build-app package verify-release test clean run

## build: build the release binary
build:
	@mkdir -p $(DIST_DIR)
	@test -n "$(MACOS_MIN)" || { echo "Makefile: no macOS deployment target found in Package.swift"; exit 1; }
	@test -n "$(MACOS_SDK)" || { echo "Makefile: xcrun could not report the macOS SDK version"; exit 1; }
	swift build -c release $(SDK_LINK_FLAGS)

## build-app: assemble the signed .app bundle (with the CLI bundled in)
build-app: build
	@rm -rf $(APP_BUNDLE)
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS $(APP_BUNDLE)/Contents/Resources
	@cp $(BUILD_DIR)/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/
	@sed 's/$${VERSION}/$(VERSION)/g; s/$${BUNDLE_ID}/$(BUNDLE_ID)/g; s/$${APP_NAME}/$(APP_NAME)/g' \
		Info.plist > $(APP_BUNDLE)/Contents/Info.plist
	@if [ -x "$(CLI_BIN)" ]; then \
		cp "$(CLI_BIN)" $(APP_BUNDLE)/Contents/Resources/image-forge; \
		echo "[bundle] embedded CLI from $(CLI_BIN)"; \
	else \
		echo "[bundle] WARN: CLI binary $(CLI_BIN) not found — app will locate it via \$$IMAGE_FORGE_BIN / ~/bin/image-forge / PATH at runtime"; \
	fi
	@if [ -f "$(ICON_SRC)" ]; then \
		scripts/make-icns.sh "$(ICON_SRC)" $(APP_BUNDLE)/Contents/Resources/AppIcon.icns; \
	else \
		echo "[icon] WARN: $(ICON_SRC) not found — building without an app icon"; \
	fi
	@$(CODESIGN_SCRIPT) $(APP_BUNDLE) "$(CODESIGN_IDENTITY)"
	@echo "Built $(APP_BUNDLE) ($(VERSION))"

## package: build-app, notarize + staple the .app, then zip for release
package: build-app
	@$(NOTARIZE_SCRIPT) $(APP_BUNDLE) "$(NOTARY_PROFILE)"
	@cd $(DIST_DIR) && /usr/bin/ditto -c -k --keepParent $(APP_NAME).app $(NAME)-$(VERSION)-darwin-arm64.zip
	@ls -la $(DIST_DIR)/$(NAME)-$(VERSION)-darwin-arm64.zip

## verify-release: refuse to release an un-notarized build (marker + staple gate)
verify-release:
	@test -f "$(APP_BUNDLE).notarized" || { \
		echo "verify-release: FAIL — $(APP_BUNDLE) has no notarization marker."; \
		echo "  make package must end with '[notarize-app] ...: Accepted and stapled'. Do not upload."; \
		exit 1; }
	@xcrun stapler validate $(APP_BUNDLE)
	@test -f "$(DIST_DIR)/$(NAME)-$(VERSION)-darwin-arm64.zip" || { \
		echo "verify-release: FAIL — release zip missing: $(DIST_DIR)/$(NAME)-$(VERSION)-darwin-arm64.zip"; exit 1; }
	@sdk=$$(otool -l "$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)" | awk '/LC_BUILD_VERSION/{f=1} f && /^ *sdk /{print $$2; exit}'); \
		test "$$sdk" = "$(MACOS_SDK)" || { \
			echo "verify-release: FAIL — linked SDK is $$sdk, expected $(MACOS_SDK)."; \
			echo "  macOS draws an app linked against an old SDK with the previous window chrome."; \
			exit 1; }
	@cli="$(APP_BUNDLE)/Contents/Resources/image-forge"; \
		test -x "$$cli" || { echo "verify-release: FAIL — no bundled CLI at $$cli (build the CLI first; see CLI_BIN)"; exit 1; }; \
		echo "$(CLI_VERSION)" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$$' || { \
			echo "verify-release: FAIL — CLI_VERSION '$(CLI_VERSION)' is not a release tag (vX.Y.Z)."; exit 1; }; \
		v=$$("$$cli" --version 2>/dev/null | head -1 | awk '{print $$NF}'); \
		test "$$v" = "$(CLI_VERSION)" || { \
			echo "verify-release: FAIL — bundled CLI reports '$$v', not $(CLI_VERSION)."; \
			echo "  Bundle the release build of the CLI at its tag (no -dirty, no -N-g<sha>): this app's"; \
			echo "  behaviour is the CLI's, and a stale or development CLI would ship under this version."; exit 1; }; \
		echo "verify-release: bundled CLI $$v"
	@echo "verify-release: OK ($(VERSION) — marker present, ticket stapled, linked against SDK $(MACOS_SDK))"

## test: run tests
test:
	swift test

## run: build and run (debug)
run:
	swift run

## clean: remove build artifacts
clean:
	rm -rf $(DIST_DIR) .build

# Homebrew tap generation (see scripts/release-brew.mk). After `make package`,
# `make brew` generates this cask from the built darwin-arm64 zip into the local
# nlink-jp/homebrew-tap checkout.
BREW_KIND := cask
BREW_DESC := SwiftUI front-end for the image-forge local image generator
BREW_NAME := $(NAME)
BREW_APP := $(APP_NAME).app
BREW_BUNDLE_ID := $(BUNDLE_ID)
# The cask must not advertise an OS the app cannot launch on: the shared template
# defaults to :big_sur, and Package.swift here says macOS 14.
BREW_MACOS_FLOOR := :sonoma
include scripts/release-brew.mk
