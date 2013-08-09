-module(rmq_ping_producer).

-include_lib("amqp_client/include/amqp_client.hrl").
-include("rmq_ping.hrl").

-behavior(gen_server).

%% API exports
-export([start_link/0, populate_queue/1]).

%% gen_server exports
-export([
	init/1,
	terminate/2,
	handle_call/3,
	handle_cast/2,
	handle_info/2,
	code_change/3
]).

-record(state, {
	chan :: pid(),
	conn :: pid(),
	queue_name :: binary()
}).

%% ===================================================================
%% API
%% ===================================================================

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

populate_queue(Count) ->
	gen_server:cast(?MODULE, {populate_queue, Count}).

%% -------------------------------------------------------------------------
%% gen_server callback functions
%% -------------------------------------------------------------------------

init([]) ->
	{ok, Host} = application:get_env(rmq_host),
	{ok, Port} = application:get_env(rmq_port),
	{ok, AmqpSpec, _Qos} = parse_opts([{host, Host}, {port, Port}]),
	{ok, Conn} = amqp_connection:start(AmqpSpec),
	link(Conn),
	{ok, Chan} = amqp_connection:open_channel(Conn),
	link(Conn),
	QName = ?queue_name,
    ok = queue_declare(Chan, QName, false, false, true),
    {ok, #state{
			chan = Chan,
			conn = Conn,
			queue_name = QName}, 0}.

terminate(_Reason, _State) ->
    ok.

handle_call(Message, _From, State) ->
	{stop, {bad_message, Message}, State}.

handle_cast({populate_queue, Count}, State) ->
	publish_dumb_msg(Count, State),
	{noreply, State, ?ping_interval};

handle_cast(Message, State) ->
	{stop, {bad_message, Message}, State}.

handle_info(timeout, State) ->
	publish_dumb_msg(1, State),
	lager:info("sent_msg"),
	{noreply, State, ?ping_interval};

handle_info(Message, State) ->
	{stop, {bad_message, Message}, State}.


code_change(_OldVsn, St, _Extra) ->
    {ok, St}.


queue_declare(Chan, Queue, Durable, Exclusive, AutoDelete) ->
    Method = #'queue.declare'{queue = Queue,
                              durable = Durable,
                              exclusive = Exclusive,
                              auto_delete = AutoDelete},
    try amqp_channel:call(Chan, Method) of
        #'queue.declare_ok'{} -> ok;
        Other                 -> {error, Other}
    catch
        _:Reason -> {error, Reason}
    end.


basic_publish(Chan, RoutingKey, Payload, Props = #'P_basic'{}) ->
    Method = #'basic.publish'{routing_key = RoutingKey},
    Content = #amqp_msg{payload = Payload, props = Props},
    try amqp_channel:call(Chan, Method, Content) of
        ok    -> ok;
        Other -> {error, Other}
    catch
        _:Reason -> {error, Reason}
    end.

publish_dumb_msg(0, _State) -> ok;
publish_dumb_msg(Count, State) ->
	ok = basic_publish(State#state.chan, State#state.queue_name, <<"blah-blah">>, #'P_basic'{}),
	publish_dumb_msg(Count-1, State).

parse_opts(Opts) ->
	DefaultPropList =
		case application:get_env(rmql, amqp_props) of
			{ok, Value} -> Value;
			undefined -> []
		end,

	%% default amqp props definition
	DHost 		= proplists:get_value(host, DefaultPropList, "127.0.0.1"),
	DPort 		= proplists:get_value(port, DefaultPropList, 5672),
	DVHost 		= proplists:get_value(vhost, DefaultPropList, <<"/">>),
	DUsername 	= proplists:get_value(username, DefaultPropList, <<"guest">>),
	DPass 		= proplists:get_value(password, DefaultPropList, <<"guest">>),
	DQos 		= proplists:get_value(qos, DefaultPropList, 0),

	%% custom amqp props definition
	Host    = proplists:get_value(host, Opts, DHost),
	Port 	= proplists:get_value(port, Opts, DPort),
	VHost 	= proplists:get_value(vhost, Opts, DVHost),
	User 	= proplists:get_value(username, Opts, DUsername),
	Pass 	= proplists:get_value(password, Opts, DPass),
	Qos 	= proplists:get_value(qos, Opts, DQos),

	AmqpSpec = #amqp_params_network{
					username = User,
					password = Pass,
					virtual_host = VHost,
					host = Host,
					port = Port,
					heartbeat = 0
				},
	{ok, AmqpSpec, Qos}.
