all:
	./rebar get-deps
	./rebar compile
start:
	erl -pa deps/*/ebin ebin -s rmq_ping_app
