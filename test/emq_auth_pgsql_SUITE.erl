%%--------------------------------------------------------------------
%% Copyright (c) 2015-2017 Feng Lee <feng@emqtt.io>.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%--------------------------------------------------------------------

-module(emq_auth_pgsql_SUITE).

-compile(export_all).

-define(PID, emq_auth_pgsql).

-define(APP, ?PID).

-include_lib("emqttd/include/emqttd.hrl").

-include_lib("eunit/include/eunit.hrl").

-include_lib("common_test/include/ct.hrl").

%%setp1 init table
-define(DROP_ACL_TABLE, "DROP TABLE IF EXISTS mqtt_acl").

-define(CREATE_ACL_TABLE, "CREATE TABLE mqtt_acl (
                           id SERIAL primary key,
                           allow integer,
                           ipaddr character varying(60),
                           username character varying(100),
                           clientid character varying(100),
                           access  integer,
                           topic character varying(100))").

-define(INIT_ACL, "INSERT INTO mqtt_acl (id, allow, ipaddr, username, clientid, access, topic)
                   VALUES
                   (1,1,'127.0.0.1','u1','c1',1,'t1'),
                   (2,0,'127.0.0.1','u2','c2',1,'t1'),
                   (3,1,'10.10.0.110','u1','c1',1,'t1'),
                   (4,1,'127.0.0.1','u3','c3',3,'t1')").

-define(DROP_AUTH_TABLE, "DROP TABLE IF EXISTS mqtt_user").

-define(CREATE_AUTH_TABLE, "CREATE TABLE mqtt_user (
                            id SERIAL primary key,
                            is_superuser boolean,
                            username character varying(100),
                            password character varying(100),
                            salt character varying(40))").

-define(INIT_AUTH, "INSERT INTO mqtt_user (id, is_superuser, username, password, salt)
                     VALUES  
                     (1, true, 'plain', 'plain', 'salt'),
                     (2, false, 'md5', '1bc29b36f623ba82aaf6724fd3b16718', 'salt'),
                     (3, false, 'sha', 'd8f4590320e1343a915b6394170650a8f35d6926', 'salt'),
                     (4, false, 'sha256', '5d5b09f6dcb2d53a5fffc60c4ac0d55fabdf556069d6631545f42aa6e3500f2e', 'salt'),
                     (5, false, 'pbkdf2_password', 'cdedb5281bb2f801565a1122b2563515', 'ATHENA.MIT.EDUraeburn'),
                     (6, false, 'bcrypt_foo', '$2a$12$sSS8Eg.ovVzaHzi1nUHYK.HbUIOdlQI0iS22Q5rd5z.JVVYH6sfm6', '$2a$12$sSS8Eg.ovVzaHzi1nUHYK.')").


all() ->
    [{group, emq_auth_pgsql_auth},
     {group, emq_auth_pgsql_acl}, 
     {group, emq_auth_pgsql}].

groups() ->
    [{emq_auth_pgsql_auth, [sequence],
     [check_auth, list_auth]},
    {emq_auth_pgsql_acl, [sequence],
     [check_acl, acl_super]}, 
    {emq_auth_pgsql, [sequence],
     [comment_config]}
    ].

init_per_suite(Config) ->
    DataDir = proplists:get_value(data_dir, Config),
    Apps = [start_apps(App, DataDir) || App <- [emqttd, emq_auth_pgsql]],
    ct:log("Apps:~p~n", [Apps]),
    Config.

end_per_suite(_Config) ->
    drop_auth_(),
    drop_acl_(),
    application:stop(emq_auth_pgsql),
    application:stop(emqttd).

comment_config(_) ->
    application:stop(?APP),
    [application:unset_env(?APP, Par) || Par <- [acl_query, auth_query]],
    application:start(?APP),
    ?assertEqual([], emqttd_access_control:lookup_mods(auth)),
    ?assertEqual([], emqttd_access_control:lookup_mods(acl)).

check_auth(_) ->
    init_auth_(), 
    Plain = #mqtt_client{client_id = <<"client1">>, username = <<"plain">>},
    Md5 = #mqtt_client{client_id = <<"md5">>, username = <<"md5">>},
    Sha = #mqtt_client{client_id = <<"sha">>, username = <<"sha">>},
    Sha256 = #mqtt_client{client_id = <<"sha256">>, username = <<"sha256">>},
    Pbkdf2 = #mqtt_client{client_id = <<"pbkdf2_password">>, username = <<"pbkdf2_password">>},
    Bcrypt = #mqtt_client{client_id = <<"bcrypt_foo">>, username = <<"bcrypt_foo">>},
    User1 = #mqtt_client{client_id = <<"bcrypt_foo">>, username = <<"user">>},
    reload([{password_hash, plain}]),
    {ok, true} = emqttd_access_control:auth(Plain, <<"plain">>),
    reload([{password_hash, md5}]),
    {ok, false} = emqttd_access_control:auth(Md5, <<"md5">>),
    reload([{password_hash, sha}]),
    {ok, false} = emqttd_access_control:auth(Sha, <<"sha">>),
    reload([{password_hash, sha256}]),
    {ok, false} = emqttd_access_control:auth(Sha256, <<"sha256">>),
    %%pbkdf2 sha
    reload([{password_hash, {pbkdf2, sha, 1, 16}}, {auth_query, "select password, salt from mqtt_user where username = '%u' limit 1"}]),
    {ok, false} = emqttd_access_control:auth(Pbkdf2, <<"password">>),
    reload([{password_hash, {salt, bcrypt}}]),
    {ok, false} = emqttd_access_control:auth(Bcrypt, <<"foo">>),
    ok = emqttd_access_control:auth(User1, <<"foo">>).

list_auth(_Config) ->
    application:start(emq_auth_username),
    emq_auth_username:add_user(<<"user1">>, <<"password1">>),
    User1 = #mqtt_client{client_id = <<"client1">>, username = <<"user1">>},
    ok = emqttd_access_control:auth(User1, <<"password1">>),
    reload([{password_hash, plain}, {auth_query, "select password from mqtt_user where username = '%u' limit 1"}]),
    Plain = #mqtt_client{client_id = <<"client1">>, username = <<"plain">>},
    {ok, true} = emqttd_access_control:auth(Plain, <<"plain">>),
    application:stop(emq_auth_username).


init_auth_() ->
    {ok, Pid} = ecpool_worker:client(gproc_pool:pick_worker({ecpool, ?PID})),
    {ok, [], []} = epgsql:squery(Pid, ?DROP_AUTH_TABLE),
    {ok, [], []} = epgsql:squery(Pid, ?CREATE_AUTH_TABLE),
    {ok, _} = epgsql:equery(Pid, ?INIT_AUTH).

drop_auth_() ->
    {ok, Pid} = ecpool_worker:client(gproc_pool:pick_worker({ecpool, ?PID})),
    {ok, [], []} = epgsql:squery(Pid, ?DROP_AUTH_TABLE).

check_acl(_) ->
    init_acl_(),
    User1 = #mqtt_client{peername = {{127,0,0,1}, 1}, client_id = <<"c1">>, username = <<"u1">>},
    User2 = #mqtt_client{peername = {{127,0,0,1}, 1}, client_id = <<"c2">>, username = <<"u2">>},
    allow = emqttd_access_control:check_acl(User1, subscribe, <<"t1">>),
    deny = emqttd_access_control:check_acl(User2, subscribe, <<"t1">>),
    
    User3 = #mqtt_client{peername = {{10,10,0,110}, 1}, client_id = <<"c1">>, username = <<"u1">>},
    User4 = #mqtt_client{peername = {{10,10,10,110}, 1}, client_id = <<"c1">>, username = <<"u1">>},
    allow = emqttd_access_control:check_acl(User3, subscribe, <<"t1">>),
    allow = emqttd_access_control:check_acl(User3, subscribe, <<"t1">>),
    allow = emqttd_access_control:check_acl(User3, subscribe, <<"t2">>),%% nomatch -> ignore -> emqttd acl
    allow = emqttd_access_control:check_acl(User4, subscribe, <<"t1">>),%% nomatch -> ignore -> emqttd acl
    
    User5 = #mqtt_client{peername = {{127,0,0,1}, 1}, client_id = <<"c3">>, username = <<"u3">>},
    allow = emqttd_access_control:check_acl(User5, subscribe, <<"t1">>),
    allow = emqttd_access_control:check_acl(User5, publish, <<"t1">>).

acl_super(_Config) ->
    reload([{password_hash, plain}]),
    {ok, C} = emqttc:start_link([{host, "localhost"}, {client_id, <<"simpleClient">>}, {username, <<"plain">>}, {password, <<"plain">>}]),
    timer:sleep(10),
    emqttc:subscribe(C, <<"TopicA">>, qos2),
    timer:sleep(1000),
    emqttc:publish(C, <<"TopicA">>, <<"Payload">>, qos2),
    timer:sleep(1000),
    receive
        {publish, Topic, Payload} ->
            ?assertEqual(<<"Payload">>, Payload)
    after
        1000 ->
            io:format("Error: receive timeout!~n"),
            ok
    end,
    emqttc:disconnect(C).

init_acl_() ->
    {ok, Pid} = ecpool_worker:client(gproc_pool:pick_worker({ecpool, ?PID})),
    {ok, [], []} = epgsql:squery(Pid, ?DROP_ACL_TABLE),
    {ok, [], []} = epgsql:squery(Pid, ?CREATE_ACL_TABLE),
    {ok, _} = epgsql:equery(Pid, ?INIT_ACL).

drop_acl_() -> 
    {ok, Pid} = ecpool_worker:client(gproc_pool:pick_worker({ecpool, ?PID})),
    {ok, [], []}= epgsql:squery(Pid, ?DROP_ACL_TABLE).

start_apps(App, DataDir) ->
    Schema = cuttlefish_schema:files([filename:join([DataDir, atom_to_list(App) ++ ".schema"])]),
    Conf = conf_parse:file(filename:join([DataDir, atom_to_list(App) ++ ".conf"])),
    NewConfig = cuttlefish_generator:map(Schema, Conf),
    Vals = proplists:get_value(App, NewConfig),
    [application:set_env(App, Par, Value) || {Par, Value} <- Vals],
    application:ensure_all_started(App).

reload(Config) when is_list(Config) ->
    application:stop(?APP), 
    [application:set_env(?APP, K, V) || {K, V} <- Config],
    application:start(?APP). 


