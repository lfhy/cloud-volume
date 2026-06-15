# Cross-platform desktop workflows for remote-storage.

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
MACOS_BRIDGE_OUT := $(BRIDGE_DIR)/libremote_storage_bridge.dylib
LINUX_BRIDGE_OUT := $(BRIDGE_DIR)/libremote_storage_bridge.so
WINDOWS_BRIDGE_OUT := $(BRIDGE_DIR)/remote_storage_bridge.dll

.PHONY: bridge bridge-macos bridge-linux bridge-windows run run-macos run-linux build build-macos build-linux build-windows test analyze clean

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
	go build -buildmode=c-shared -o $(MACOS_BRIDGE_OUT) ./bridge

bridge-linux:
	@mkdir -p $(BRIDGE_DIR)
	go build -buildmode=c-shared -o $(LINUX_BRIDGE_OUT) ./bridge

bridge-windows:
ifeq ($(HOST_PLATFORM),windows)
	@mkdir -p $(BRIDGE_DIR)
	go build -buildmode=c-shared -o $(WINDOWS_BRIDGE_OUT) ./bridge
else
	@echo "bridge-windows must be run on a Windows host."
	@exit 1
endif

run: bridge
ifeq ($(HOST_PLATFORM),macos)
	DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer flutter run -d macos
else ifeq ($(HOST_PLATFORM),linux)
	flutter run -d linux
else ifeq ($(HOST_PLATFORM),windows)
	flutter run -d windows
else
	@echo "Unsupported host OS for default run target: $(HOST_PLATFORM)"
	@exit 1
endif

run-macos: bridge-macos
	DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer flutter run -d macos

run-linux: bridge-linux
ifeq ($(HOST_PLATFORM),linux)
	flutter run -d linux
else
	@echo "run-linux must be run on a Linux host."
	@exit 1
endif

run-windows: bridge-windows
ifeq ($(HOST_PLATFORM),windows)
	flutter run -d windows
else
	@echo "run-windows must be run on a Windows host."
	@exit 1
endif

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
	DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer flutter build macos

build-linux: bridge-linux
ifeq ($(HOST_PLATFORM),linux)
	flutter build linux
else
	@echo "build-linux must be run on a Linux host."
	@exit 1
endif

build-windows: bridge-windows
ifeq ($(HOST_PLATFORM),windows)
	flutter build windows
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

test:
	flutter test

analyze:
	flutter analyze

clean:
	flutter clean
	rm -rf $(BRIDGE_DIR)
