-module(cu_beamr).
-export([start/1, call/3, call/4, call/5, stop/1, test/0]).

-include("src/include/ao.hrl").
-include_lib("eunit/include/eunit.hrl").

test() ->
    aos64_standalone_wex_test(),
    erlang:halt().

load_driver() ->
    case erl_ddll:load("./priv", ?MODULE) of
        ok -> ok;
        {error, already_loaded} -> ok;
        {error, Error} -> {error, Error}
    end.

start(WasmBinary) ->
    ok = load_driver(),
    Port = open_port({spawn, "cu_beamr"}, []),
    Port ! {self(), {command, term_to_binary({init, WasmBinary})}},
    ao:c({waiting_for_init_from, Port}),
    receive
        {ok, Imports, Exports} ->
            ao:c({wasm_init_success, Imports, Exports}),
            {ok, Port, Imports, Exports};
        Other ->
            ao:c({unexpected_result, Other}),
            Other
    end.

stop(Port) ->
    port_close(Port),
    ok.

call(Port, FunctionName, Args) ->
    call(Port, FunctionName, Args, fun stub_stdlib/6).
call(Port, FunctionName, Args, Stdlib) ->
    {ResType, Res, _} = call(undefined, Port, FunctionName, Args, Stdlib),
    {ResType, Res}.
call(S, Port, FunctionName, Args, ImportFunc) ->
    ao:c({call_started, Port, FunctionName, Args, ImportFunc}),
    Port ! {self(), {command, term_to_binary({call, FunctionName, Args})}},
    exec_call(S, ImportFunc, Port).

stub_stdlib(S, _Port, _Module, Func, _Args, _Signature) ->
    ao:c({stub_stdlib_called, Func}),
    {S, [0]}.

exec_call(S, ImportFunc, Port) ->
    receive
        {ok, Result} ->
            ao:c({call_result, Result}),
            {ok, Result, S};
        {import, Module, Func, Args, Signature} ->
            %ao:c({import_called, Module, Func, Args, Signature}),
            {S2, ErlRes} = ImportFunc(S, Port, Module, Func, Args, Signature),
            ao:c({import_returned, Module, Func, Args, ErlRes}),
            Port ! {self(), {command, term_to_binary({import_response, ErlRes})}},
            exec_call(S2, ImportFunc, Port);
        {error, Error} ->
            ao:c({wasm_error, Error}),
            {error, Error, S};
        Error ->
            ao:c({unexpected_result, Error}),
            Error
    end.

serialize(Port) ->
    {ok, Size} = cu_beamr_io:size(Port),
    {ok, Mem} = cu_beamr_io:read(Port, 0, Size),
    {ok, Mem}.

deserialize(Port, Bin) ->
    % TODO: Be careful of memory growth!
    ok = cu_beamr_io:write(Port, 0, Bin).

%% Tests

nif_loads_test() ->
    ?MODULE:module_info().

simple_wasm_test() ->
    {ok, File} = file:read_file("test/test.wasm"),
    {ok, Port, _Imports, _Exports} = start(File),
    {ok, [Result]} = call(Port, "fac", [5.0]),
    ?assertEqual(120.0, Result).

simple_wasm_calling_test() ->
    {ok, File} = file:read_file("test/test-calling.wasm"),
    {ok, Port, _Imports, _Exports} = start(File),
    {ok, [Result]} = call(Port, "main", [1,1]),
    ?assertEqual(1, Result),
    Arg0 = <<"Test string arg 000000000000000\0">>,
    Arg1 = <<"Test string arg 111111111111111\0">>,
    {ok, Ptr0} = cu_beamr_io:malloc(Port, byte_size(Arg0)),
    ?assertNotEqual(0, Ptr0),
    cu_beamr_io:write(Port, Ptr0, Arg0),
    {ok, Ptr1} = cu_beamr_io:malloc(Port, byte_size(Arg1)),
    ?assertNotEqual(0, Ptr1),
    cu_beamr_io:write(Port, Ptr1, Arg1),
    {ok, []} = call(Port, "print_args", [Ptr0, Ptr1]).

wasm64_test() ->
    ao:c(simple_wasm64_test),
    {ok, File} = file:read_file("test/test-64.wasm"),
    {ok, Port, _ImportMap, _Exports} = start(File),
    {ok, [Result]} = call(Port, "fac", [5.0]),
    ?assertEqual(120.0, Result).

% wasm_exceptions_test_skip() ->
%     {ok, File} = file:read_file("test/test-ex.wasm"),
%     {ok, Port, _Imports, _Exports} = start(File),
%     {ok, [Result]} = call(Port, "main", [1, 0]),
%     ?assertEqual(1, Result).

aos64_standalone_wex_test() ->
    Env = <<"{\"Process\":{\"Id\":\"AOS\",\"Owner\":\"FOOBAR\",\"Tags\":[{\"name\":\"Name\",\"value\":\"Thomas\"}, {\"name\":\"Authority\",\"value\":\"FOOBAR\"}]}}\0">>,
    Msg = <<"{\"From\":\"FOOBAR\",\"Block-Height\":\"1\",\"Target\":\"AOS\",\"Owner\":\"FOOBAR\",\"Id\":\"1\",\"Module\":\"W\",\"Tags\":[{\"name\":\"Action\",\"value\":\"Eval\"}],\"Data\":\"return 1+1\"}\0">>,
    {ok, File} = file:read_file("test/aos-2-pure.wasm"),
    {ok, Port, _ImportMap, _Exports} = start(File),
    {ok, Ptr1} = cu_beamr_io:malloc(Port, byte_size(Msg)),
    ?assertNotEqual(0, Ptr1),
    cu_beamr_io:write(Port, Ptr1, Msg),
    {ok, Ptr2} = cu_beamr_io:malloc(Port, byte_size(Env)),
    ?assertNotEqual(0, Ptr2),
    cu_beamr_io:write(Port, Ptr2, Env),
    % Read the strings to validate they are correctly passed
    {ok, MsgBin} = cu_beamr_io:read(Port, Ptr1, byte_size(Msg)),
    {ok, EnvBin} = cu_beamr_io:read(Port, Ptr2, byte_size(Env)),
    ?assertEqual(Env, EnvBin),
    ?assertEqual(Msg, MsgBin),
    {ok, [Ptr3], _} = call(Port, "handle", [Ptr1, Ptr2]),
    {ok, ResBin} = cu_beamr_io:read_string(Port, Ptr3),
    #{<<"ok">> := true, <<"response">> := Resp} = jiffy:decode(ResBin, [return_maps]),
    #{<<"Output">> := #{ <<"data">> := Data }} = Resp,
    ?assertEqual(<<"2">>, Data).

aos64_standalone_wex_test() ->
    Env = <<"{\"Process\":{\"Id\":\"AOS\",\"Owner\":\"FOOBAR\",\"Tags\":[{\"name\":\"Name\",\"value\":\"Thomas\"}, {\"name\":\"Authority\",\"value\":\"FOOBAR\"}]}}\0">>,
    Msg1 = <<"{\"From\":\"FOOBAR\",\"Block-Height\":\"1\",\"Target\":\"AOS\",\"Owner\":\"FOOBAR\",\"Id\":\"1\",\"Module\":\"W\",\"Tags\":[{\"name\":\"Action\",\"value\":\"Eval\"}],\"Data\":\"TestVar = 0\"}\0">>,
    Msg2 = <<"{\"From\":\"FOOBAR\",\"Block-Height\":\"1\",\"Target\":\"AOS\",\"Owner\":\"FOOBAR\",\"Id\":\"1\",\"Module\":\"W\",\"Tags\":[{\"name\":\"Action\",\"value\":\"Eval\"}],\"Data\":\"TestVar = 1\"}\0">>,
    Msg3 = <<"{\"From\":\"FOOBAR\",\"Block-Height\":\"1\",\"Target\":\"AOS\",\"Owner\":\"FOOBAR\",\"Id\":\"1\",\"Module\":\"W\",\"Tags\":[{\"name\":\"Action\",\"value\":\"Eval\"}],\"Data\":\"return TestVar\"}\0">>,
    {ok, File} = file:read_file("test/aos-2-pure.wasm"),
    {ok, Port1, _ImportMap, _Exports} = start(File),
    EnvPtr = cu_beamr_io:write_string(Port1, Env),
    Msg1Ptr = cu_beamr_io:write_string(Port2, Msg1),
    Msg2Ptr = cu_beamr_io:write_string(Port2, Msg2),
    Msg3Ptr = cu_beamr_io:write_string(Port2, Msg3),
    {ok, [_ResPtr], _} = call(Port1, "handle", [Msg1Ptr, EnvPtr]),
    {ok, MemCheckpoint} = serialize(Port1),
    {ok, [_ResPtr], _} = call(Port1, "handle", [Msg2Ptr, EnvPtr]),
    {ok, [Out1Ptr], _} = call(Port1, "handle", [Msg3Ptr, EnvPtr]),
    {ok, Port2, _ImportMap, _Exports} = start(File),
    deserialize(Port2, MemCheckpoint),
    {ok, [Out2Ptr], _} = call(Port2, "handle", [Msg3Ptr, EnvPtr]),
    Str1 = ?c(cu_beamr_io:read_string(Port1, Out1Ptr)),
    Str2 = ?c(cu_beamr_io:read_string(Port2, Out1Ptr)),
    ?assertNotEqual(Str1, Str2).