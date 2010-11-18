% Standard binary encoding of Bson documents, version 1.0. See bsonspec.org.
-module (bson_binary).

-export ([put_document/1, get_document/1, put_cstring/1, get_cstring/1]).

-include ("bson_binary.hrl").

-define (fits_int32 (N), -16#80000000 =< N andalso N =< 16#7fffffff).
-define (fits_int64 (N), -16#8000000000000000 =< N andalso N =< 16#7fffffffffffffff).

-define (put_tagname (Tag), (Tag):8, (put_cstring (Name))/binary).
% Name is expected to be in scope at call site

-spec put_field (bson:utf8(), bson:value()) -> binary().
put_field (Name, Value) -> case Value of
	{bin, Bin} -> <<?put_tagname (5), (put_binary (0, Bin)) /binary>>;
	{bfunction, Bin} -> <<?put_tagname (5), (put_binary (1, Bin)) /binary>>;
	{uuid, Bin} -> <<?put_tagname (5), (put_binary (3, Bin)) /binary>>;
	{md5, Bin} -> <<?put_tagname (5), (put_binary (5, Bin)) /binary>>;
	{userdefined, Bin} -> <<?put_tagname (5), (put_binary (128, Bin)) /binary>>;
	{oid, Bin} -> <<?put_tagname (7), (put_oid (Bin)) /binary>>;
	false -> <<?put_tagname (8), 0:8>>;
	true -> <<?put_tagname (8), 1:8>>;
	{unixtime, Millisecs} -> <<?put_tagname (9), ?put_int64 (Millisecs)>>;
	null -> <<?put_tagname (10)>>;
	{regex, Pat, Opt} -> <<?put_tagname (11), (put_cstring (Pat)) /binary, (put_cstring (Opt)) /binary>>;
	{javascript, Doc, Code} -> case Doc of
		[] -> <<?put_tagname (13), (put_string (Code)) /binary>>;
		Env -> <<?put_tagname (15), (put_closure (Code, Env)) /binary>> end;
	{symbol, Atom} -> <<?put_tagname (14), (put_string (atom_to_binary (Atom, utf8))) /binary>>;
	{mongostamp, N} -> <<?put_tagname (17), ?put_int64 (N)>>;
	minkey -> <<?put_tagname (255)>>;
	maxkey -> <<?put_tagname (127)>>;
	V -> if
		is_float (V) -> <<?put_tagname (1), ?put_float (V)>>;
		is_binary (V) -> <<?put_tagname (2), (put_string (V)) /binary>>;
		is_list (V) -> case bson:is_document (V) of
			true -> <<?put_tagname (3), (put_document (V)) /binary>>;
			false -> <<?put_tagname (4), (put_array (V)) /binary>> end;
		is_integer (V) -> if
			?fits_int32 (V) -> <<?put_tagname (16), ?put_int32 (V)>>;
			?fits_int64 (V) -> <<?put_tagname (18), ?put_int64 (V)>>;
			true -> erlang:error (bson_int_too_large, [Name, Value]) end;
		true -> erlang:error (bad_bson, [Name, Value]) end end.

-spec get_field (binary()) -> {bson:utf8(), bson:value(), binary()}.
get_field (<<Tag:8, Bin0/binary>>) ->
	{Name, Bin1} = get_cstring (Bin0),
	{Value, BinRest} = case Tag of
		1 -> <<?get_float (N), Bin2 /binary>> = Bin1, {N, Bin2};
		2 -> get_string (Bin1);
		3 -> get_document (Bin1);
		4 -> get_array (Bin1);
		5 ->
			{Subtype, Bin, Bin2} = get_binary (Bin1),
			Con = case Subtype of 0 -> bin; 1 -> bfunction; 3 -> uuid; 5 -> md5; 128 -> userdefined end,
			{{Con, Bin}, Bin2};
		7 -> {Oid, Bin2} = get_oid (Bin1), {{oid, Oid}, Bin2};
		8 -> <<Bit:8, Bin2 /binary>> = Bin1, {case Bit of 0 -> false; 1 -> true end, Bin2};
		9 -> <<?get_int64 (Millisecs), Bin2 /binary>> = Bin1, {{unixtime, Millisecs}, Bin2};
		10 -> {null, Bin1};
		11 ->
			{Pat, Bin2} = get_cstring (Bin1),
			{Opt, Bin3} = get_cstring (Bin2),
			{{regex, Pat, Opt}, Bin3};
		13 -> {Code, Bin2} = get_string (Bin1), {{javascript, [], Code}, Bin2};
		15 -> {Code, Env, Bin2} = get_closure (Bin1), {{javascript, Env, Code}, Bin2};
		14 -> {UBin, Bin2} = get_string (Bin1), {{symbol, binary_to_atom (UBin, utf8)}, Bin2};
		16 -> <<?get_int32 (N), Bin2 /binary>> = Bin1, {N, Bin2};
		18 -> <<?get_int64 (N), Bin2 /binary>> = Bin1, {N, Bin2};
		17 -> <<?get_int64 (N), Bin2 /binary>> = Bin1, {{mongostamp, N}, Bin2};
		255 -> {minkey, Bin1};
		127 -> {maxkey, Bin1};
		_ -> erlang:error (unknown_bson_tag, [<<Tag:8, Bin0/binary>>]) end,
	{Name, Value, BinRest}.

-spec put_string (bson:utf8()) -> binary().
put_string (UBin) -> <<?put_int32 (byte_size (UBin) + 1), UBin /binary, 0:8>>.

-spec get_string (binary()) -> {bson:utf8(), binary()}.
get_string (<<?get_int32 (N), Bin /binary>>) ->
	Size = N - 1,
	<<UBin :Size /binary, 0:8, Rest /binary>> = Bin,
	{UBin, Rest}.

-spec put_cstring (bson:utf8()) -> binary().
% utf8 binary cannot contain a 0 byte.
put_cstring (UBin) -> <<UBin /binary, 0:8>>.

-spec get_cstring (binary()) -> {bson:utf8(), binary()}.
get_cstring (Bin) -> list_to_tuple (binary:split (Bin, <<0>>)).

-spec put_document (bson:document()) -> binary().
put_document (Document) ->
	Bin = bson:doc_foldl (fun put_field_accum/3, <<>>, Document),
	<<?put_int32 (byte_size (Bin) + 5), Bin /binary, 0:8>>.
put_field_accum (Label, Value, Bin) ->
	<<Bin /binary, (put_field (atom_to_binary (Label, utf8), Value)) /binary>>.

-spec get_document (binary()) -> {bson:document(), binary()}.
get_document (<<?get_int32 (N), Bin /binary>>) ->
	Size = N - 5,
	<<DBin :Size /binary, 0:8, Bin1 /binary>> = Bin,
	Doc = get_fields (DBin),
	{Doc, Bin1}.
get_fields (<<>>) -> [];
get_fields (Bin) ->
	{Name, Value, Bin1} = get_field (Bin),
	[binary_to_atom (Name, utf8), Value | get_fields (Bin1)].

-spec put_array (bson:arr()) -> binary().
% encode same as document with labels '0', '1', etc.
put_array (Values) ->
	{_N, Bin} = lists:foldl (fun put_value_accum/2, {0, <<>>}, Values),
	<<?put_int32 (byte_size (Bin) + 5), Bin/binary, 0:8>>.
put_value_accum (Value, {N, Bin}) ->
	{N+1, <<Bin /binary, (put_field (bson:utf8 (integer_to_list (N)), Value)) /binary>>}.

-spec get_array (binary()) -> {bson:arr(), binary()}.
% encoded same as document with labels '0', '1', etc. which we ignore
get_array (<<?get_int32 (N), Bin /binary>>) ->
	Size = N - 5,
	<<DBin :Size /binary, 0:8, Bin1 /binary>> = Bin,
	Array = get_values (DBin),
	{Array, Bin1}.
get_values (<<>>) -> [];
get_values (Bin) ->
	{_, Value, Bin1} = get_field (Bin),
	[Value | get_values (Bin1)].

-spec put_binary (integer(), binary()) -> binary().
put_binary (Subtype, Bin) ->
	<<?put_int32 (byte_size (Bin)), Subtype:8, Bin /binary>>.

-spec get_binary (binary()) -> {integer(), binary(), binary()}.
get_binary (<<?get_int32 (Size), Subtype:8, Bin /binary>>) ->
	<<VBin :Size /binary, Bin1 /binary>> = Bin,
	{Subtype, VBin, Bin1}.

-spec put_closure (bson:utf8(), bson:document()) -> binary().
put_closure (Code, Env) ->
	Bin = <<(put_string (Code)) /binary, (put_document (Env)) /binary>>,
	<<?put_int32 (byte_size (Bin) + 4), Bin /binary>>.

-spec get_closure (binary()) -> {bson:utf8(), bson:document(), binary()}.
get_closure (<<?get_int32 (N), Bin /binary>>) ->
	_Size = N - 4,
	{Code, Bin1} = get_string (Bin),
	{Env, Bin2} = get_document (Bin1),
	{Code, Env, Bin2}.

-spec put_oid (<<_:96>>) -> <<_:96>>.
put_oid (<<Oid :12/binary>>) -> Oid.

-spec get_oid (binary()) -> {<<_:96>>, binary()}.
get_oid (<<Oid :12/binary, Bin/binary>>) -> {Oid, Bin}.