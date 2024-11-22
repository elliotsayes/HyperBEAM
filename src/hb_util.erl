-module(hb_util).
-export([id/1, id/2]).
-export([encode/1, decode/1, safe_encode/1, safe_decode/1]).
-export([find_value/2, find_value/3]).
-export([number/1, list_to_numbered_map/1, message_to_numbered_list/1]).
-export([hd/1, hd/2, hd/3]).
-export([remove_common/2]).
-include("include/hb.hrl").

%%% @moduledoc A collection of utility functions for building with HyperBEAM.

%% @doc Return the human-readable form of an ID of a message when given either
%% a message explicitly, raw encoded ID, or an Erlang Arweave `tx` record.
id(Item) -> id(Item, unsigned).
id(TX, Type) when is_record(TX, tx) ->
	encode(ar_bundles:id(TX, Type));
id(Map, Type) when is_map(Map) ->
	hb_pam:get(Map, Type);
id(Bin, _) when is_binary(Bin) andalso byte_size(Bin) == 43 ->
	Bin;
id(Bin, _) when is_binary(Bin) andalso byte_size(Bin) == 32 ->
	encode(Bin);
id(Data, Type) when is_list(Data) ->
	id(list_to_binary(Data), Type).

%% @doc Encode a binary to URL safe base64 binary string.
encode(Bin) ->
  b64fast:encode(Bin).

%% @doc Try to decode a URL safe base64 into a binary or throw an error when
%% invalid.
decode(Input) ->
  b64fast:decode(Input).

%% @doc Safely encode a binary to URL safe base64.
safe_encode(Bin) when is_binary(Bin) ->
  encode(Bin);
safe_encode(Bin) ->
  Bin.

%% @doc Safely decode a URL safe base64 into a binary returning an ok or error
%% tuple.
safe_decode(E) ->
  try
    D = decode(E),
    {ok, D}
  catch
    _:_ ->
      {error, invalid}
  end.

%% @doc Label a list of elements with a number.
number(List) ->
	lists:map(
		fun({N, Item}) -> {integer_to_binary(N), Item} end,
		lists:zip(lists:seq(1, length(List)), List)
	).

%% @doc Convert a list of elements to a map with numbered keys.
list_to_numbered_map(List) ->
  maps:from_list(number(List)).

%% @doc Take a message with numbered keys and convert it to a list of tuples
%% with the associated key as an integer and a value. Optionally, it takes a
%% standard map of HyperBEAM runtime options.
message_to_numbered_list(Message) ->
	message_to_numbered_list(Message, #{}).
message_to_numbered_list(Message, Opts) ->
	{ok, Keys} = hb_pam:resolve(Message, keys, Opts),
	KeyValList =
		lists:filtermap(
			fun(Key) ->
				case string:to_integer(Key) of
					{Int, ""} ->
						{
							true,
							{Int, hb_pam:get(Message, Key, Opts)}
						};
					_ -> false
				end
			end,
			Keys
		),
	lists:sort(KeyValList).

%% @doc Convert a map of numbered elements to a list. We stop at the first
%% integer key that is not associated with a value.

%% @doc Get the first element (the lowest integer key >= 1) of a numbered map.
%% Optionally, it takes a specifier of whether to return the key or the value,
%% as well as a standard map of HyperBEAM runtime options.
%% 
%% If `error_strategy` is `throw`, raise an exception if no integer keys are
%% found. If `error_strategy` is `any`, return `undefined` if no integer keys
%% are found. By default, the function does not pass a `throw` execution
%% strategy to `hb_pam:to_key/2`, such that non-integer keys present in the
%% message will not lead to an exception.
hd(Message) -> hd(Message, value).
hd(Message, ReturnType) ->
	hd(Message, ReturnType, #{ error_strategy => throw }).
hd(Message, ReturnType, Opts) -> 
	{ok, Keys} = hb_pam:resolve(Message, keys),
	hd(Message, Keys, 1, ReturnType, Opts).
hd(_Map, [], _Index, _ReturnType, #{ error_strategy := throw }) ->
	throw(no_integer_keys);
hd(_Map, [], _Index, _ReturnType, _Opts) -> undefined;
hd(Message, [Key|Rest], Index, ReturnType, Opts) ->
	case hb_pam:to_key(Key, Opts#{ error_strategy => return }) of
		undefined ->
			hd(Message, Rest, Index + 1, ReturnType, Opts);
		Key ->
			case ReturnType of
				key -> Key;
				value -> hb_pam:resolve(Message, Key)
			end
	end.

%% @doc Find the value associated with a key in parsed a JSON structure list.
find_value(Key, List) ->
  hb_util:find_value(Key, List, undefined).

find_value(Key, Map, Default) when is_map(Map) ->
  case maps:find(Key, Map) of
    {ok, Value} ->
      Value;
    error ->
      Default
  end;
find_value(Key, List, Default) ->
  case lists:keyfind(Key, 1, List) of
    {Key, Val} ->
      Val;
    false ->
      Default
  end.

%% @doc Remove the common prefix from two strings, returning the remainder of the
%% first string. This function also coerces lists to binaries where appropriate,
%% returning the type of the first argument.
remove_common(MainStr, SubStr) when is_binary(MainStr) and is_list(SubStr) ->
    remove_common(MainStr, list_to_binary(SubStr));
remove_common(MainStr, SubStr) when is_list(MainStr) and is_binary(SubStr) ->
    binary_to_list(remove_common(list_to_binary(MainStr), SubStr));
remove_common(<< X:8, Rest1/binary>>, << X:8, Rest2/binary>>) ->
    remove_common(Rest1, Rest2);
remove_common([X|Rest1], [X|Rest2]) ->
    remove_common(Rest1, Rest2);
remove_common([$/|Path], _) -> Path;
remove_common(Rest, _) -> Rest.