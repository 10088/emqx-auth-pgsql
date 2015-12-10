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
%%% @doc emqttd pgsql plugin.
%%%
%%% @author Feng Lee <feng@emqtt.io>
%%%-----------------------------------------------------------------------------
-module(emqttd_plugin_pgsql).

-export([load/0, unload/0]).

load() ->
    {ok, AuthSql}  = application:get_env(?MODULE, authquery),
    {ok, HashType} = application:get_env(?MODULE, password_hash),
    ok = emqttd_access_control:register_mod(auth, emqttd_auth_pgsql, {AuthSql, HashType}),
    with_acl_enabled(fun(AclSql) ->
        {ok, AclNomatch} = application:get_env(?MODULE, acl_nomatch),
        ok = emqttd_access_control:register_mod(acl, emqttd_acl_pgsql, {AclSql, AclNomatch})
    end).

unload() ->
    emqttd_access_control:unregister_mod(auth, emqttd_auth_pgsql),
    with_acl_enabled(fun(_AclSql) ->
        emqttd_access_control:unregister_mod(acl, emqttd_acl_pgsql)
    end).
    
with_acl_enabled(Fun) ->
    case application:get_env(?MODULE, aclquery) of
        {ok, AclSql} -> Fun(AclSql);
        undefined    -> ok
    end.

