%%%-------------------------------------------------------------------
%%% @author kantappa
%%% @copyright (C) 2017, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 29. 三月 2017 上午10:59
%%%-------------------------------------------------------------------
-module(raft_event).
-author("kantappa").

-behaviour(gen_event).

%% API
-export([start_link/0]).
-export([become/1]).
-export([subscribe_msg/1]).
%% gen_event callbacks
-export([init/1,
  handle_event/2,
  handle_call/2,
  handle_info/2,
  terminate/2,
  code_change/3]).

-define(SERVER, ?MODULE).

-record(state, {current_role, pidlist = []}).


become(leader) ->
  ch_role(become_leader);
become(follower) ->
  ch_role(become_follower).


ch_role(Role) ->
  gen_event:notify(?SERVER, {change_role, Role}).


subscribe_msg(Pid) when erlang:is_pid(Pid) ->
  gen_event:notify(?SERVER, {subscribe, Pid}).


%%%===================================================================
%%% gen_event callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Creates an event manager
%%
%% @end
%%--------------------------------------------------------------------
-spec(start_link() -> {ok, pid()} | {error, {already_started, pid()}}).
start_link() ->
  Result = {ok, _Pid} = gen_event:start_link({local, ?SERVER}),
  add_handler(),
  Result.


%%%===================================================================
%%% gen_event callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Whenever a new event handler is added to an event manager,
%% this function is called to initialize the event handler.
%%
%% @end
%%--------------------------------------------------------------------
-spec(init(InitArgs :: term()) ->
  {ok, State :: #state{}} |
  {ok, State :: #state{}, hibernate} |
  {error, Reason :: term()}).
init([]) ->
  {ok, #state{}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Whenever an event manager receives an event sent using
%% gen_event:notify/2 or gen_event:sync_notify/2, this function is
%% called for each installed event handler to handle the event.
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_event(Event :: term(), State :: #state{}) ->
  {ok, NewState :: #state{}} |
  {ok, NewState :: #state{}, hibernate} |
  {swap_handler, Args1 :: term(), NewState :: #state{},
    Handler2 :: (atom() | {atom(), Id :: term()}), Args2 :: term()} |
  remove_handler).

%% 当前角色和之前的角色一样
handle_event({change_role, Role}, #state{current_role = Role} = State) ->
  {ok, State};
handle_event({change_role, Role}, #state{pidlist = []} = State) ->
  {ok, State#state{current_role = Role}};
handle_event({change_role, Role}, #state{pidlist = Pidlist} = State) ->
  NewPidlist = notify(Role, Pidlist),
  {ok, State#state{current_role = Role, pidlist = NewPidlist}};
handle_event({subscribe, Pid}, #state{pidlist = Pidlist} = State) ->
  NewPidlist = [Pid | lists:delete(Pid, Pidlist)],
  {ok, State#state{pidlist = NewPidlist}};
handle_event(_Event, State) ->
  {ok, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Whenever an event manager receives a request sent using
%% gen_event:call/3,4, this function is called for the specified
%% event handler to handle the request.
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_call(Request :: term(), State :: #state{}) ->
  {ok, Reply :: term(), NewState :: #state{}} |
  {ok, Reply :: term(), NewState :: #state{}, hibernate} |
  {swap_handler, Reply :: term(), Args1 :: term(), NewState :: #state{},
    Handler2 :: (atom() | {atom(), Id :: term()}), Args2 :: term()} |
  {remove_handler, Reply :: term()}).
handle_call(_Request, State) ->
  Reply = ok,
  {ok, Reply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called for each installed event handler when
%% an event manager receives any other message than an event or a
%% synchronous request (or a system message).
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_info(Info :: term(), State :: #state{}) ->
  {ok, NewState :: #state{}} |
  {ok, NewState :: #state{}, hibernate} |
  {swap_handler, Args1 :: term(), NewState :: #state{},
    Handler2 :: (atom() | {atom(), Id :: term()}), Args2 :: term()} |
  remove_handler).
handle_info(_Info, State) ->
  {ok, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Whenever an event handler is deleted from an event manager, this
%% function is called. It should be the opposite of Module:init/1 and
%% do any necessary cleaning up.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
-spec(terminate(Args :: (term() | {stop, Reason :: term()} | stop |
remove_handler | {error, {'EXIT', Reason :: term()}} |
{error, term()}), State :: term()) -> term()).
terminate(_Arg, _State) ->
  ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @end
%%--------------------------------------------------------------------
-spec(code_change(OldVsn :: term() | {down, term()}, State :: #state{},
    Extra :: term()) ->
  {ok, NewState :: #state{}}).
code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
%%--------------------------------------------------------------------
%% @doc
%% Adds an event handler
%%
%% @end
%%--------------------------------------------------------------------
-spec(add_handler() -> ok | {'EXIT', Reason :: term()} | term()).
add_handler() ->
  gen_event:add_handler(?SERVER, ?MODULE, []).


notify(Role, Pidlist) ->
  do_notify(Role, Pidlist, []).

do_notify(_Role, [], PidList) ->
  PidList;
do_notify(Role, [Pid | PidList], NewPidList) ->
  NewPidList2 =
    case erlang:is_process_alive(Pid) of
      true ->
        erlang:send(Pid, {current_role, Role}),
        [Pid | NewPidList];
      false ->
        NewPidList
    end,
  do_notify(Role, PidList, NewPidList2).