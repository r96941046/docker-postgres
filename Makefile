all: build

build:
	@docker build -t="r96941046/postgresql" .
