.PHONY: build app run clean

build:
	swift build

app:
	./scripts/build-app.sh

run:
	./scripts/run.sh

clean:
	rm -rf .build NotesTool.app
