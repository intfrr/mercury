%------------------------------------------------------------------------------%
% string_format_u.m
%
% Test the u specifier of string__format.
%------------------------------------------------------------------------------%

:- module string_format_u.

:- interface.

:- import_module io.

:- pred main(io::di, io::uo) is det.

%------------------------------------------------------------------------------%
%------------------------------------------------------------------------------%

:- implementation.

:- import_module string_format_lib.
:- import_module int, list, string.

%------------------------------------------------------------------------------%

main -->
	{ Ints = [i(0), i(1), i(10), i(100), i(max_int)] },
	list__foldl(output_list(Ints), format_strings("u")).

%------------------------------------------------------------------------------%
%------------------------------------------------------------------------------%
