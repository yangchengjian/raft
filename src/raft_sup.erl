%%%-------------------------------------------------------------------
%% @doc raft top level supervisor.
%% @end
%%%-------------------------------------------------------------------

-module(raft_sup).

-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).
-define(CHILD_SPEC(Module, Fun, ARGS), {Module, {Module, Fun, ARGS}, permanent, 5000, worker, [Module]}).
%%====================================================================
%% API functions
%%====================================================================

start_link() ->
  supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%%====================================================================
%% Supervisor callbacks
%%====================================================================

%% Child :: {Id,StartFunc,Restart,Shutdown,Type,Modules}
init([]) ->
  Child = [
    ?CHILD_SPEC(raft_fsm, start_link, [])
    , ?CHILD_SPEC(raft_request, start_link, [])
    , ?CHILD_SPEC(raft_event, start_link, [])
    , ?CHILD_SPEC(raft, start_link, [])
  ],
  {ok, {{one_for_one, 5, 5}, Child}}.

%%====================================================================
%% Internal functions
%%====================================================================
