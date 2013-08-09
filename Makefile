
all: generate

get-deps:
	./rebar get-deps

compile: get-deps
	./rebar compile

non-rel-start:
	erl -pa deps/*/ebin ebin -s rmq_ping_app

generate: compile
	./rebar generate

console:
	./rel/rmq_ping/bin/rmq_ping console

clean:
	rm -rf ./rel/rmq_ping
	./rebar clean