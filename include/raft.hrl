%%%-------------------------------------------------------------------
%%% @author kantappa
%%% @copyright (C) 2017, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 28. 三月 2017 下午7:33
%%%-------------------------------------------------------------------
-author("kantappa").
-ifndef(_raft).
-define(_raft, true).

%% 请求投票
-record(request_vote, {node, term}).
%% 收到投票
-record(vote, {node}).

%% 心跳
-record(heartbeat, {node, term}).


-endif.
