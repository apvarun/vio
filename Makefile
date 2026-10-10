APP_NAME = Vio
APP = build/$(APP_NAME).app
SWIFT_FLAGS ?=
PYTHON ?= python3
WAV ?=
export SIGNING_IDENTITY
export NOTARY_PROFILE

.PHONY: app app-icon dmg release release-check dmg-artwork download verify-assets test selftest open clean

dmg: app dmg-artwork
	bash Scripts/build-dmg.sh preview

release-check:
	bash Scripts/build-dmg.sh check-release

release: release-check
	$(MAKE) app dmg-artwork
	bash Scripts/build-dmg.sh release

dmg-artwork: app-icon
	swift Scripts/render-dmg.swift

# SwiftPM tracks source, manifest, and module-map dependencies on every invocation.
app: verify-assets app-icon Resources/MenuBarIcon.pdf
	swift build -c release $(SWIFT_FLAGS)
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources/Licenses"
	cp "$$(swift build -c release $(SWIFT_FLAGS) --show-bin-path)/$(APP_NAME)" "$(APP)/Contents/MacOS/$(APP_NAME)"
	cp Resources/whistle.cact "$(APP)/Contents/Resources/"
	cp build/Vio.icns "$(APP)/Contents/Resources/"
	cp build/composer-icons/Assets.car "$(APP)/Contents/Resources/"
	cp Resources/MenuBarIcon.pdf "$(APP)/Contents/Resources/"
	cp Info.plist "$(APP)/Contents/"
	cp LICENSE THIRD_PARTY_NOTICES.md Licenses/Apache-2.0.txt "$(APP)/Contents/Resources/Licenses/"
	codesign --force --sign - "$(APP)"
	touch "$(APP)"
	/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$(abspath $(APP))"
	@echo "Built $(APP)"
	@echo "After rebuilding, you may need to grant Accessibility and Microphone access again in System Settings › Privacy & Security."

verify-assets:
	$(PYTHON) Scripts/assets.py verify

Resources/MenuBarIcon.pdf: Resources/vio.icon/Assets/vio_heart_like_waveform_white.svg Scripts/render-menubar-icon.swift
	swift Scripts/render-menubar-icon.swift

app-icon:
	rm -rf build/composer-icons
	mkdir -p build/composer-icons
	xcrun actool Resources/vio.icon --compile build/composer-icons \
		--platform macosx --minimum-deployment-target 26.0 --app-icon vio \
		--output-partial-info-plist build/composer-icons/Info.plist
	cp build/composer-icons/vio.icns build/Vio.icns

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
