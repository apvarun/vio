APP_NAME = Vio
APP = build/$(APP_NAME).app
SWIFT_FLAGS ?=
PYTHON ?= python3
WAV ?=

.PHONY: app download verify-assets test selftest open clean

# SwiftPM tracks source, manifest, and module-map dependencies on every invocation.
app: verify-assets build/Vio.icns
	swift build -c release $(SWIFT_FLAGS)
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources/Licenses"
	cp "$$(swift build -c release $(SWIFT_FLAGS) --show-bin-path)/$(APP_NAME)" "$(APP)/Contents/MacOS/$(APP_NAME)"
	cp Resources/whistle.cact "$(APP)/Contents/Resources/"
	cp build/Vio.icns "$(APP)/Contents/Resources/"
	cp Info.plist "$(APP)/Contents/"
	cp LICENSE THIRD_PARTY_NOTICES.md Licenses/Apache-2.0.txt "$(APP)/Contents/Resources/Licenses/"
	codesign --force --sign - "$(APP)"
	touch "$(APP)"
	/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$(abspath $(APP))"
	@echo "Built $(APP)"
	@echo "After rebuilding, you may need to grant Accessibility and Microphone access again in System Settings › Privacy & Security."

verify-assets:
	$(PYTHON) Scripts/assets.py verify

build/Vio.icns: Resources/vio-icon-flat-teal.png
	mkdir -p build/Vio.iconset
	for size in 16 32 128 256 512; do \
		sips -z $$size $$size "$<" --out "build/Vio.iconset/icon_$${size}x$${size}.png" >/dev/null; \
		sips -z $$((size * 2)) $$((size * 2)) "$<" --out "build/Vio.iconset/icon_$${size}x$${size}@2x.png" >/dev/null; \
	done
	iconutil -c icns build/Vio.iconset -o "$@"

download:
	$(PYTHON) Scripts/assets.py download

test: verify-assets
	swift test $(SWIFT_FLAGS)
	$(PYTHON) -m unittest discover -s Tests/Scripts -p 'test_*.py'

# Use generated speech by default, or supply WAV="path/to/recording.wav".
selftest: app
	@if [ -n "$(WAV)" ]; then \
		"$(APP)/Contents/MacOS/$(APP_NAME)" --selftest "$(WAV)"; \
	else \
		say -o build/selftest.aiff "Hello world" && \
		afconvert -f WAVE -d LEI16@16000 -c 1 build/selftest.aiff build/selftest.wav && \
		"$(APP)/Contents/MacOS/$(APP_NAME)" --selftest build/selftest.wav; \
	fi

open: app
	open "$(APP)"

clean:
	rm -rf build .build
