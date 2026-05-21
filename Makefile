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
	swift run CoreTestRunner

clean:
	rm -rf .build ClaudeUsageBar.app
