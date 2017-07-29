-ifndef(_raft).
-define(_raft, true).

%% 请求投票
-record(request_vote, {node, term}).
%% 收到投票
-record(vote, {node}).

%% 心跳
-record(heartbeat, {node, term}).


-endif.
