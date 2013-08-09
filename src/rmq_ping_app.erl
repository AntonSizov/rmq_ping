-module(rmq_ping_app).

-behaviour(application).

%% Application callbacks
-export([start/0, start/2, stop/1]).

%% ===================================================================
%% Application callbacks
%% ===================================================================

start() ->
	ok = application:start(compiler),
	ok = application:start(syntax_tools),
	ok = application:start(lager),
	ok = application:start(sync),
	ok = application:start(rmq_ping).

start(_StartType, _StartArgs) ->
    rmq_ping_sup:start_link().

stop(_State) ->
    ok.
