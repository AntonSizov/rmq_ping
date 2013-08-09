-module(rmq_ping_consumer).

-include_lib("amqp_client/include/amqp_client.hrl").
-include("rmq_ping.hrl").

-behavior(gen_server).

%% API exports
-export([start_link/0]).

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
	queue_name :: binary(),
	consumer_tag :: integer(),
	msg_received = 0 :: integer()
}).

%% ===================================================================
%% API
%% ===================================================================

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% -------------------------------------------------------------------------
%% gen_server callback functions
%% -------------------------------------------------------------------------

init([]) ->
	{ok, AmqpSpec, _Qos} = parse_opts([]),
	{ok, Conn} = amqp_connection:start(AmqpSpec),
	link(Conn),
	{ok, Chan} = amqp_connection:open_channel(Conn),
	link(Conn),
	QName = ?queue_name,
	{ok, ConsumerTag} = basic_consume(Chan, QName, false),
    {ok, #state{
			chan = Chan,
			conn = Conn,
			queue_name = QName,
			consumer_tag = ConsumerTag
			}, 5000}.

terminate(_Reason, _State) ->
    ok.

handle_call(Message, _From, State) ->
	{stop, {bad_message, Message}, State}.

handle_cast(Message, State) ->
	{stop, {bad_message, Message}, State}.

handle_info(timeout, State) ->
	lager:warning("no message received"),
	{noreply, State, ?wait_interval};


handle_info({BasicDeliver, #amqp_msg{}}, State=#state{msg_received=N}) ->
	lager:info("got_msg"),
	#'basic.deliver'{delivery_tag = Tag} = BasicDeliver,
	ok = basic_ack(State#state.chan, Tag),
	NewState=State#state{msg_received=N+1},
	case ((N+1) rem 100 =:= 0) of
		true -> lager:info("Received ~p messages", [N+1]);
		false -> ok
	end,
	{noreply, NewState, ?wait_interval};

handle_info(Message, State) ->
	{stop, {bad_message, Message}, State}.

code_change(_OldVsn, St, _Extra) ->
    {ok, St}.

%% ===================================================================
%% Internals
%% ===================================================================

basic_consume(Chan, Queue, NoAck) ->
    Method = #'basic.consume'{queue = Queue, no_ack = NoAck},
    try
        amqp_channel:subscribe(Chan, Method, self()),
        receive
            #'basic.consume_ok'{consumer_tag = ConsumerTag} ->
                {ok, ConsumerTag}
        after
            10000 -> {error, timeout}
        end
    catch
        _:Reason -> {error, Reason}
    end.

basic_ack(Chan, DeliveryTag) ->
    Method = #'basic.ack'{delivery_tag = DeliveryTag},
    try amqp_channel:call(Chan, Method) of
        ok    -> ok;
        Other -> {error, Other}
    catch
        _:Reason -> {error, Reason}
    end.

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
