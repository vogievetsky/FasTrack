ROOT_DIR := $(shell pwd)
PATH := ${PATH}:${ROOT_DIR}/node/current/bin:${ROOT_DIR}/node_modules/.bin:

all: compile

init: install-node install-node-modules
#
# node
#

install-node:
	make/install-node

install-node-modules:
	make/install-node-modules

#
# app
#

compile:
	make/compile

watch:
	make/watch

run:
	make/run

jenkins-release: clean init compile


#
# clean
#

clean-all: clean clean-node clean-node-modules

clean:
	@rm -rfv target/

clean-node-modules:
	@rm -rfv node_modules

clean-node:
	@rm -rfv node
