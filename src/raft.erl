-module(raft).

-behaviour(gen_server).

-export_type([raft_event/0, raft_role_type/0]).
-type raft_event() :: 'become_leader'|'become_follower'.
-type raft_role_type() :: 'follower'|'candidate'|'leader'.
%% API
-export([start_link/0]).
-export([start_working/0]).
-export([add_handler/2]).
-export([delete_handler/1]).
-export([role/0]).
%% gen_server callbacks
-export([init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3]).

%% test
-export([test_start_master_node/1, test_start_slave_node/2]).

-define(SERVER, ?MODULE).

-record(state, {handler}).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @end
%%--------------------------------------------------------------------
-spec(start_link() ->
    {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

-spec(start_working() -> ok|{error, any()}).
start_working() ->
    case application:ensure_all_started(raft) of
        {ok, _Started} ->
            case raft_fsm:open() of
                ok ->
                    ok;
                {error, is_working}->ok;
                {error, Reason} ->
                    {error, Reason}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

-spec(add_handler(Key, Fun) -> ok|{error, term()} when
    Key :: term(),
    Fun :: fun((Event)  -> any()),
    Event :: raft_event()
).
add_handler(Key, Fun) when is_function(Fun, 1) ->
    case erlang:whereis(?SERVER) of
        undefined ->
            {error, not_found_process};
        _Pid ->
            try
                gen_server:call(?SERVER, {add_handler, Key, Fun}, 1000)
            catch
                _ : Reason ->
                    {error, Reason}
            end
    end.

-spec(delete_handler(Key) -> ok|{error, term()} when
    Key :: term()
).
delete_handler(Key) ->
    case erlang:whereis(?SERVER) of
        undefined ->
            ok;
        _Pid ->
            try
                gen_server:call(?SERVER, {delete_handler, Key}, 1000)
            catch
                _ : Reason ->
                    {error, Reason}
            end
    end.

-spec(role() -> raft_role_type()|{error, any()}).
role() ->
    raft_fsm:role().

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
-spec(init(Args :: term()) ->
    {ok, State :: #state{}} | {ok, State :: #state{}, timeout() | hibernate} |
    {stop, Reason :: term()} | ignore).
init([]) ->
    raft_event:subscribe_msg(self()),
    {ok, #state{handler = dict:new()}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_call(Request :: term(), From :: {pid(), Tag :: term()},
    State :: #state{}) ->
    {reply, Reply :: term(), NewState :: #state{}} |
    {reply, Reply :: term(), NewState :: #state{}, timeout() | hibernate} |
    {noreply, NewState :: #state{}} |
    {noreply, NewState :: #state{}, timeout() | hibernate} |
    {stop, Reason :: term(), Reply :: term(), NewState :: #state{}} |
    {stop, Reason :: term(), NewState :: #state{}}).

handle_call({add_handler, Key, Fun}, _From, #state{handler = Handlers} = State) ->
    NewHandlers = dict:store(Key, Fun, Handlers),
    {reply, ok, State#state{handler = NewHandlers}};
handle_call({delete_handler, Key}, _From, #state{handler = Handlers} = State) ->
    NewHandlers = dict:erase(Key, Handlers),
    {reply, ok, State#state{handler = NewHandlers}};
handle_call(_Request, _From, State) ->
    {reply, ok, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_cast(Request :: term(), State :: #state{}) ->
    {noreply, NewState :: #state{}} |
    {noreply, NewState :: #state{}, timeout() | hibernate} |
    {stop, Reason :: term(), NewState :: #state{}}).
handle_cast(_Request, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
-spec(handle_info(Info :: timeout() | term(), State :: #state{}) ->
    {noreply, NewState :: #state{}} |
    {noreply, NewState :: #state{}, timeout() | hibernate} |
    {stop, Reason :: term(), NewState :: #state{}}).
handle_info({current_role, become_leader}, #state{handler = Handlers} = State) ->
    broadcast_event(become_leader, dict:to_list(Handlers)),
    {noreply, State};
handle_info({current_role, become_follower}, #state{handler = Handlers} = State) ->
    broadcast_event(become_follower, dict:to_list(Handlers)),
    {noreply, State};
handle_info(_Info, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
-spec(terminate(Reason :: (normal | shutdown | {shutdown, term()} | term()),
    State :: #state{}) -> term()).
terminate(_Reason, _State) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
-spec(code_change(OldVsn :: term() | {down, term()}, State :: #state{},
    Extra :: term()) ->
    {ok, NewState :: #state{}} | {error, Reason :: term()}).
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
broadcast_event(_Event, []) ->
    ok;
broadcast_event(Event, [{_Key, Fun} | List]) ->
    erlang:apply(Fun, [Event]),
    broadcast_event(Event, List).

%%%===================================================================
%%% test functions
%%%===================================================================
test_start_master_node(NodeName) ->
    case start_working() of
        ok ->
            lager:info("[~p ~p] start master node (~p) success", [?MODULE, ?LINE, NodeName]);
        {error, Reason} ->
            lager:error("[~p ~p] start master node (~p) fail (~p)", [?MODULE, ?LINE, NodeName, Reason]),
            timer:sleep(100),
            exit(kill)
    end.


test_start_slave_node(NodeName, MasterNode) ->
    {ok, _Started} = application:ensure_all_started(raft),
    case net_adm:ping(MasterNode) of
        pong ->
            lager:info("[~p ~p] cluster node ~p success", [?MODULE, ?LINE, MasterNode]),
            case start_working() of
                ok ->
                    lager:info("[~p ~p] start   node (~p) success", [?MODULE, ?LINE, NodeName]);
                {error, Reason} ->
                    lager:error("[~p ~p] start   node (~p) fail (~p)", [?MODULE, ?LINE, NodeName, Reason]),
                    timer:sleep(100),
                    exit(kill)
            end;
        pang ->
            lager:error("[~p ~p] net_adm:ping(~p) pang", [?MODULE, ?LINE, MasterNode]),
            timer:sleep(100),
            exit(kill)
    end.
