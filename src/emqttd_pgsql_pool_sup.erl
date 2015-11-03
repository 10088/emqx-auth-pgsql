%%%-----------------------------------------------------------------------------
%%% Copyright (c) 2015 eMQTT.IO, All Rights Reserved.
%%%
%%% Permission is hereby granted, free of charge, to any person obtaining a copy
%%% of this software and associated documentation files (the "Software"), to deal
%%% in the Software without restriction, including without limitation the rights
%%% to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
%%% copies of the Software, and to permit persons to whom the Software is
%%% furnished to do so, subject to the following conditions:
%%%
%%% The above copyright notice and this permission notice shall be included in all
%%% copies or substantial portions of the Software.
%%%
%%% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
%%% IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
%%% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
%%% AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
%%% LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
%%% OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
%%% SOFTWARE.
%%%-----------------------------------------------------------------------------
%%% @doc
%%% emqttd pgsql pool supervisor.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(emqttd_pgsql_pool_sup).

-author("Feng Lee <feng@emqtt.io>").

-behaviour(supervisor).

%% API
-export([start_link/2]).

%% Supervisor callbacks
-export([init/1]).

start_link(Pool, Opts) when is_atom(Pool) ->
    supervisor:start_link(?MODULE, [Pool, Opts]).

init([Pool, Opts]) ->  
    PoolSize = proplists:get_value(size, Opts, erlang:system_info(schedulers)),
    gproc_pool:new(Pool, random, [{size, PoolSize}]),
    Children = lists:map(
                 fun(I) ->
                     gproc_pool:add_worker(Pool, {emqttd_pgsql_pool, I}, I),
                     {{emqttd_pgsql_pool, I},
                        {emqttd_pgsql_pool, start_link, [Pool, I, Opts]},
                            permanent, 5000, worker, [emqttd_pgsql_pool]}
                 end, lists:seq(1, PoolSize)),
    {ok, {{one_for_one, 10, 3600}, Children}}.

