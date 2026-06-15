# Cross-platform desktop workflows for remote-storage.

FLUTTER ?= $(shell if command -v flutter >/dev/null 2>&1; then command -v flutter; elif [ -x /opt/tools/flutter/bin/flutter ]; then printf '%s\n' /opt/tools/flutter/bin/flutter; fi)
HOST ?= 0.0.0.0
PORT ?= 8080
WEB_LISTEN ?= $(HOST):$(PORT)

ifeq ($(OS),Windows_NT)
HOST_PLATFORM := windows
else
OS_NAME := $(shell uname -s)
ifeq ($(OS_NAME),Darwin)
HOST_PLATFORM := macos
else ifeq ($(OS_NAME),Linux)
HOST_PLATFORM := linux
else
HOST_PLATFORM := unknown
endif
endif

BRIDGE_DIR := bin/bridge
CLI_DIR := bin
CLI_OUT := $(CLI_DIR)/cloud-volume-cli
CLI_FULL_OUT := $(CLI_DIR)/cloud-volume-cli-full
MACOS_BRIDGE_OUT := $(BRIDGE_DIR)/libremote_storage_bridge.dylib
LINUX_BRIDGE_OUT := $(BRIDGE_DIR)/libremote_storage_bridge.so
WINDOWS_BRIDGE_OUT := $(BRIDGE_DIR)/remote_storage_bridge.dll
BRIDGE_GO_ENV := CGO_ENABLED=1

ifneq ($(BRIDGE_CC),)
BRIDGE_GO_ENV += CC=$(BRIDGE_CC)
endif

ifneq ($(BRIDGE_CXX),)
BRIDGE_GO_ENV += CXX=$(BRIDGE_CXX)
endif

.PHONY: bridge bridge-macos bridge-linux bridge-windows cli cli-full build-cli build-cli-full cli-release cli-release-full cli-release-linux-amd64 cli-release-linux-arm64 cli-release-darwin-amd64 cli-release-darwin-arm64 cli-release-windows-amd64 cli-release-full-linux-amd64 cli-release-full-linux-arm64 cli-release-full-darwin-amd64 cli-release-full-darwin-arm64 cli-release-full-windows-amd64 run-cli run run-macos run-linux run-web build build-macos build-linux build-windows build-web test analyze clean

bridge:
ifeq ($(HOST_PLATFORM),macos)
	$(MAKE) bridge-macos
else ifeq ($(HOST_PLATFORM),linux)
	$(MAKE) bridge-linux
else ifeq ($(HOST_PLATFORM),windows)
	$(MAKE) bridge-windows
else
	@echo "Unsupported host OS for default bridge target: $(HOST_PLATFORM)"
	@exit 1
endif

bridge-macos:
	@mkdir -p $(BRIDGE_DIR)
	$(BRIDGE_GO_ENV) go build -buildmode=c-shared -o $(MACOS_BRIDGE_OUT) ./bridge

bridge-linux:
	@mkdir -p $(BRIDGE_DIR)
	$(BRIDGE_GO_ENV) go build -buildmode=c-shared -o $(LINUX_BRIDGE_OUT) ./bridge

bridge-windows:
ifeq ($(HOST_PLATFORM),windows)
	@mkdir -p $(BRIDGE_DIR)
	$(BRIDGE_GO_ENV) go build -buildmode=c-shared -o $(WINDOWS_BRIDGE_OUT) ./bridge
else
	@echo "bridge-windows must be run on a Windows host."
	@exit 1
endif

build-cli:
	@mkdir -p $(CLI_DIR)
	go build -o $(CLI_OUT) ./cmd/cloud-volume-cli

build-cli-full:
	@mkdir -p $(CLI_DIR)
	go build -tags cli_full -o $(CLI_FULL_OUT) ./cmd/cloud-volume-cli

cli: build-cli

cli-full: build-web
	./scripts/build_cli_packages.sh --goos $(shell go env GOOS) --goarch $(shell go env GOARCH) --version dev --variant full --output-dir dist/cli-local

cli-release: cli-release-linux-amd64 cli-release-linux-arm64 cli-release-darwin-amd64 cli-release-darwin-arm64 cli-release-windows-amd64

cli-release-full: cli-release-full-linux-amd64 cli-release-full-linux-arm64 cli-release-full-darwin-amd64 cli-release-full-darwin-arm64 cli-release-full-windows-amd64

cli-release-linux-amd64:
	./scripts/build_cli_packages.sh --goos linux --goarch amd64 --version dev --variant lite --output-dir dist/cli

cli-release-linux-arm64:
	./scripts/build_cli_packages.sh --goos linux --goarch arm64 --version dev --variant lite --output-dir dist/cli

cli-release-darwin-amd64:
	./scripts/build_cli_packages.sh --goos darwin --goarch amd64 --version dev --variant lite --output-dir dist/cli

cli-release-darwin-arm64:
	./scripts/build_cli_packages.sh --goos darwin --goarch arm64 --version dev --variant lite --output-dir dist/cli

cli-release-windows-amd64:
	./scripts/build_cli_packages.sh --goos windows --goarch amd64 --version dev --variant lite --output-dir dist/cli

cli-release-full-linux-amd64:
	./scripts/build_cli_packages.sh --goos linux --goarch amd64 --version dev --variant full --output-dir dist/cli

cli-release-full-linux-arm64:
	./scripts/build_cli_packages.sh --goos linux --goarch arm64 --version dev --variant full --output-dir dist/cli

cli-release-full-darwin-amd64:
	./scripts/build_cli_packages.sh --goos darwin --goarch amd64 --version dev --variant full --output-dir dist/cli

cli-release-full-darwin-arm64:
	./scripts/build_cli_packages.sh --goos darwin --goarch arm64 --version dev --variant full --output-dir dist/cli

cli-release-full-windows-amd64:
	./scripts/build_cli_packages.sh --goos windows --goarch amd64 --version dev --variant full --output-dir dist/cli

run-cli: build-cli
	./$(CLI_OUT)

run: bridge
ifeq ($(HOST_PLATFORM),macos)
	DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer $(FLUTTER) run -d macos --dart-define=APP_VERSION_LABEL=dev
else ifeq ($(HOST_PLATFORM),linux)
	$(FLUTTER) run -d linux --dart-define=APP_VERSION_LABEL=dev
else ifeq ($(HOST_PLATFORM),windows)
	$(FLUTTER) run -d windows --dart-define=APP_VERSION_LABEL=dev
else
	@echo "Unsupported host OS for default run target: $(HOST_PLATFORM)"
	@exit 1
endif

run-macos: bridge-macos
	DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer $(FLUTTER) run -d macos --dart-define=APP_VERSION_LABEL=dev

run-linux: bridge-linux
ifeq ($(HOST_PLATFORM),linux)
	$(FLUTTER) run -d linux --dart-define=APP_VERSION_LABEL=dev
else
	@echo "run-linux must be run on a Linux host."
	@exit 1
endif

run-windows: bridge-windows
ifeq ($(HOST_PLATFORM),windows)
	$(FLUTTER) run -d windows --dart-define=APP_VERSION_LABEL=dev
else
	@echo "run-windows must be run on a Windows host."
	@exit 1
endif

run-web: build-web
	go run ./cmd/web --listen $(WEB_LISTEN) --static-root build/web

build:
ifeq ($(HOST_PLATFORM),macos)
	$(MAKE) build-macos
else ifeq ($(HOST_PLATFORM),linux)
	$(MAKE) build-linux
else ifeq ($(HOST_PLATFORM),windows)
	$(MAKE) build-windows
else
	@echo "Unsupported host OS for default build target: $(HOST_PLATFORM)"
	@exit 1
endif

build-macos: bridge-macos
	DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer $(FLUTTER) build macos --dart-define=APP_VERSION_LABEL=dev

build-linux: bridge-linux
ifeq ($(HOST_PLATFORM),linux)
	$(FLUTTER) build linux --dart-define=APP_VERSION_LABEL=dev
else
	@echo "build-linux must be run on a Linux host."
	@exit 1
endif

build-windows: bridge-windows
ifeq ($(HOST_PLATFORM),windows)
	$(FLUTTER) build windows --dart-define=APP_VERSION_LABEL=dev
else
	@echo "build-windows must be run on a Windows host."
	@exit 1
endif
# Convenient one-click script (auto-detects platform).
run-script:
	./scripts/run.sh

run-script-release:
	./scripts/run.sh --release
appimage:
ifeq ($(HOST_PLATFORM),linux)
	./scripts/build_appimage.sh
else
	@echo "appimage must be run on a Linux host."
	@exit 1
endif

build-web:
	$(FLUTTER) build web --dart-define=APP_VERSION_LABEL=dev

test:
	$(FLUTTER) test

analyze:
	$(FLUTTER) analyze

clean:
	$(FLUTTER) clean
	rm -rf $(BRIDGE_DIR)
