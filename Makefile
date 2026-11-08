.PHONY: build app run test bench matrix check clean

build:
	swift build -c release

app:
	./scripts/bundle.sh

run: app
	open build/Gesture.app

test:
	swift run -c release GestureSelfTest

bench:
	swift run -c release gesture-bench --check

matrix:
	swift run -c release gesture-bench --matrix --check

check: test bench matrix

clean:
	rm -rf .build build
