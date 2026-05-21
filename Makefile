.PHONY: build bundle install autostart run clean test

build:
	swift build -c release

bundle: build
	bash Scripts/bundle.sh

install: bundle
	bash Scripts/install.sh

autostart: install
	bash Scripts/autostart.sh

run: build
	.build/debug/ClaudeUsageBar

test:
	mkdir -p .build/test-bin
	swift build 2>&1 | head -20
	swiftc -suppress-warnings -I .build/debug/Modules -enable-testing .test-bin/main.swift Sources/ClaudeUsageBarCore/Stage.swift -o .build/test-bin/stage-tests
	./.build/test-bin/stage-tests

clean:
	rm -rf .build ClaudeUsageBar.app
