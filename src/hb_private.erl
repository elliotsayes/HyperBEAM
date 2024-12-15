-module(hb_private).
-export([from_message/1, get/2, get/3, set/3, reset/1, is_private/1]).
-include_lib("eunit/include/eunit.hrl").

%%% @moduledoc This module provides basic helper utilities for managing the
%%% private element of a message, which can be used to store state that is
%%% not included in serialized messages, or those granted to users via the
%%% APIs. Private elements of a message can be useful for storing state that
%%% is only relevant temporarily. For example, a device might use the private
%%% element to store a cache of values that are expensive to recompute. They
%%% should _not_ be used for encoding state that makes the execution of a
%%% device non-deterministic (unless you are sure you know what you are doing).
%%%
%%% The `set` and `get` functions of this module allow you to run those keys
%%% as converge paths if you would like to have private `devices` in the
%%% messages non-public zone.
%%%
%%% See `docs/converge-protocol.md` for more information about the Converge
%%% Protocol and private elements of messages.

%% @doc Return the `private` key from a message. If the key does not exist, an
%% empty map is returned.
from_message(Msg) -> maps:get(priv, Msg, #{}).

%% @doc Helper for getting a value from the private element of a message.
get(Msg, Key) ->
    get(Msg, Key, undefined).

get(Msg, InputPath, Default) ->
    Path = remove_private_specifier(InputPath),
    % Resolve the path against the private element of the message.
    Resolve =
        hb_converge:resolve(
            Path,
            from_message(Msg),
            converge_opts()
        ),
    case Resolve of
        {ok, Value} -> Value;
        not_found -> Default
    end.

%% @doc Helper function for setting a key in the private element of a message.
set(Msg, InputPath, Value) ->
    Path = remove_private_specifier(InputPath),
    Priv = from_message(Msg),
    NewPriv = hb_converge:set(Priv, Path, Value, converge_opts()),
    maps:put(
        priv,
        NewPriv,
        Msg
    ).

%% @doc Check if a key is private.
is_private(Key) ->
	case hb_converge:key_to_binary(Key) of
		<<"priv", _/binary>> -> true;
		_ -> false
	end.

%% @doc Remove the first key from the path if it is a private specifier.
remove_private_specifier(InputPath) ->
    case is_private(hd(Path = hb_path:term_to_path(InputPath))) of
        true -> tl(Path);
        false -> Path
    end.

%% @doc The opts map that should be used when resolving paths against the
%% private element of a message.
converge_opts() ->
    #{ hashpath => ignore, cache_control => false }.

%% @doc Unset all of the private keys in a message.
reset(Msg) ->
    maps:without(
        lists:filter(fun is_private/1, maps:keys(Msg)),
        Msg
    ).

%%% Tests

set_private_test() ->
    ?assertEqual(#{a => 1, private => #{b => 2}}, ?MODULE:set(#{a => 1}, b, 2)),
    Res = ?MODULE:set(#{a => 1}, a, 1),
    ?assertEqual(#{a => 1, private => #{a => 1}}, Res),
    ?assertEqual(#{a => 1, private => #{a => 1}}, ?MODULE:set(Res, a, 1)).

get_private_key_test() ->
    M1 = #{a => 1, private => #{b => 2}},
    ?assertEqual(undefined, ?MODULE:get(M1, a)),
    {ok, [a]} = hb_converge:resolve(M1, <<"Keys">>, #{}),
    ?assertEqual(2, ?MODULE:get(M1, b)),
    {Res, _} = hb_converge:resolve(M1, <<"Private">>, #{}),
    ?assertNotEqual(ok, Res),
    {Res, _} = hb_converge:resolve(M1, private, #{}).