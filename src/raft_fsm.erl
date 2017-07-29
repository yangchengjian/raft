-module(raft_fsm).

-behaviour(gen_fsm).

-include("raft.hrl").

-define(HEARTBEAT_TIMEOUT, 100).
-define(ELECTION_TIMEOUT_MIN, ?HEARTBEAT_TIMEOUT * 2).
-define(ELECTION_TIMEOUT_MAX, ?HEARTBEAT_TIMEOUT * 3).


%% API
-export([start_link/0]).
-export([open/0]).
-export([role/0]).
%% gen_fsm callbacks
-export([init/1,
    wait/2,
    follower/2,
    follower/3,
    candidate/2,
    candidate/3,
    leader/2,
    leader/3,
    handle_event/3,
    handle_sync_event/4,
    handle_info/3,
    terminate/3,
    code_change/4]).

-define(SERVER, ?MODULE).

-record(state, {term = 0, votedFor, votelist = [], timer}).


start_link() ->
    gen_fsm:start_link({local, ?SERVER}, ?MODULE, [], []).

open() ->
    case erlang:whereis(?SERVER) of
        undefined ->
            {error, not_found_process};
        _Pid ->
            try
                gen_fsm:sync_send_all_state_event(?SERVER, open, 1000)
            catch
                _:Reason ->
                    {error, Reason}
            end
    end.

role() ->
    case erlang:whereis(?SERVER) of
        undefined ->
            {error, not_found_process};
        _Pid ->
            try
                gen_fsm:sync_send_all_state_event(?SERVER, current_state, 1000)
            catch
                _:Reason ->
                    {error, Reason}
            end
    end.

init([]) ->
    {ok, wait, #state{}}.

wait(_, State) ->
    {next_state, wait, State}.

follower(timeout, State) ->
    send_request_vote(State),
    {next_state, candidate, election_timer(State#state{votedFor = undefined, votelist = []})};
follower(#request_vote{node = Node, term = Term}, #state{votedFor = undefined, term = Myterm} = State) when Term >= Myterm ->
    send_vote(Node, State),
    {next_state, follower, State#state{votedFor = Node}};
follower(#request_vote{}, State) ->
    {next_state, follower, State};
follower(#heartbeat{term = Term}, #state{term = MyTerm} = State) when Term >= MyTerm ->
    {next_state, follower, election_timer(State#state{term = Term, votedFor = undefined})};
follower(#heartbeat{}, State) ->
    {next_state, follower, State};
follower(Event, State) ->
    lager:error("[~p ~p] unknown event ~p", [?MODULE, ?LINE, Event]),
    {next_state, follower, State}.

follower(_Event, _From, State) ->
    Reply = ok,
    {reply, Reply, follower, State}.

candidate(timeout, State) ->
    candidate_maybe_become_leader(cluster_node(State), State#state{votedFor = undefined, votelist = []});
candidate(#request_vote{} = RequestVote, State) ->
    candidate_maybe_become_follower(RequestVote, State);
candidate(#vote{} = Vote, State) ->
    candidate_maybe_become_leader(Vote, State);
candidate(#heartbeat{} = Heartbeat, State) ->
    candidate_maybe_become_follower(Heartbeat, State);

candidate(Event, State) ->
    lager:error("[~p ~p] unknown event ~p", [?MODULE, ?LINE, Event]),
    {next_state, candidate, State}.

candidate(_Event, _From, State) ->
    Reply = ok,
    {reply, Reply, candidate, State}.

leader(timeout, State) ->
    send_heartbeat(State),
    NewState = heartbeat_timer(State#state{votedFor = undefined}),
    {next_state, leader, NewState};
leader(#heartbeat{} = Heartbeat, State) ->
    leader_maybe_become_follower(Heartbeat, State);
leader(#request_vote{} = Request_vote, State) ->
    leader_maybe_become_follower(Request_vote, State);
leader(#vote{}, State) ->
    {next_state, leader, State};
leader(Event, State) ->
    lager:error("[~p ~p] unknown event ~p", [?MODULE, ?LINE, Event]),
    {next_state, leader, State}.


leader(_Event, _From, State) ->
    Reply = ok,
    {reply, Reply, leader, State}.


handle_event(_Event, StateName, State) ->
    {next_state, StateName, State}.

handle_sync_event(open, _From, wait, State) ->
    Ref = election_timer(),
    Reply = ok,
    {reply, Reply, follower, State#state{timer = Ref}};
handle_sync_event(open, _From, StateName, State) ->
    Reply = {error, is_working},
    {reply, Reply, StateName, State};
handle_sync_event(current_state, _From, wait = StateName, State) ->
    Reply = {error, not_work},
    {reply, Reply, StateName, State};
handle_sync_event(current_state, _From, StateName, State) ->
    Reply = StateName,
    {reply, Reply, StateName, State};
handle_sync_event(_Event, _From, StateName, State) ->
    Reply = ok,
    {reply, Reply, StateName, State}.

handle_info(_Info, StateName, State) ->
    {next_state, StateName, State}.

terminate(_Reason, _StateName, _State) ->
    ok.

code_change(_OldVsn, StateName, State, _Extra) ->
    {ok, StateName, State}.

election_timer() ->
    gen_fsm:send_event_after(election_timeout(), timeout).

election_timer(State) ->
        catch gen_fsm:cancel_timer(State#state.timer),
    State#state{timer = gen_fsm:send_event_after(election_timeout(), timeout)}.

heartbeat_timer(State) ->
        catch gen_fsm:cancel_timer(State#state.timer),
    State#state{timer = gen_fsm:send_event_after(?HEARTBEAT_TIMEOUT, timeout)}.

election_timeout() ->
    crypto:rand_uniform(?ELECTION_TIMEOUT_MIN, ?ELECTION_TIMEOUT_MAX).

candidate_maybe_become_follower(#request_vote{node = Node, term = Term}, #state{term = Myterm, votedFor = VoteFor} = State) when Term >= Myterm andalso VoteFor =:= undefined ->
    send_vote(Node, State),
    {next_state, follower, election_timer(State#state{votedFor = Node, votelist = []})};
candidate_maybe_become_follower(#request_vote{}, State) ->
    {next_state, candidate, State};
candidate_maybe_become_follower(#heartbeat{term = Term}, #state{term = Myterm} = State) when Term >= Myterm ->
    {next_state, follower, election_timer(State#state{term = Term, votedFor = undefined, votelist = []})};
candidate_maybe_become_follower(#heartbeat{}, State) ->
    {next_state, candidate, State}.

candidate_maybe_become_leader([], #state{term = Term} = State) ->
    NewState = State#state{term = Term + 1, votelist = []},
    send_heartbeat(NewState),
    raft_event:become(leader),
    {next_state, leader, heartbeat_timer(NewState)};

candidate_maybe_become_leader([_node | _], State) ->
    NewState = election_timer(State),
    send_request_vote(NewState),
    {next_state, candidate, NewState};
candidate_maybe_become_leader(#vote{node = Node}, #state{term = Term, votelist = Votelist} = State) ->
    NewVotelist = [Node | lists:delete(Node, Votelist)],
    Len = erlang:length(NewVotelist),
    ClusterNodeLen = erlang:length(cluster_node(State)),
    case Len == erlang:trunc(ClusterNodeLen / 2) + 1 of
        true ->
            NewState = State#state{votelist = [], term = Term + 1, votedFor = undefined},
            send_heartbeat(NewState),
            raft_event:become(leader),
            {next_state, leader, heartbeat_timer(NewState)};
        false ->
            {next_state, candidate, State#state{votelist = NewVotelist}}
    end.

leader_maybe_become_follower(#heartbeat{term = Term}, #state{term = MyTerm} = State) when MyTerm =< Term ->
    raft_event:become(follower),
    {next_state, follower, election_timer(State#state{votedFor = undefined, votelist = []})};
leader_maybe_become_follower(#heartbeat{}, State) ->
    {next_state, leader, State};
leader_maybe_become_follower(#request_vote{node = Node, term = Term}, #state{term = MyTerm} = State) when MyTerm < Term ->
    send_vote(Node, State),
    raft_event:become(follower),
    {next_state, follower, election_timer(State#state{votedFor = undefined, votelist = []})};
leader_maybe_become_follower(#request_vote{}, State) ->
    {next_state, leader, State}.

cluster_node(_State) ->
    erlang:nodes().

send_heartbeat(State) ->
    raft_request:send(?SERVER, cluster_node(State), encode_heartbeat_pkg(State)).

send_request_vote(State) ->
    raft_request:send(?SERVER, cluster_node(State), encode_request_vote_pkd(State)).

send_vote(Node, State) ->
    raft_request:send(?SERVER, [Node], encode_vote_pkg(State)).

encode_heartbeat_pkg(#state{term = Term}) ->
    #heartbeat{node = node(), term = Term}.

encode_request_vote_pkd(#state{term = Term}) ->
    #request_vote{node = node(), term = Term}.

encode_vote_pkg(#state{}) ->
    #vote{node = node()}.
