%-----------------------------------------------------------------------------%
% Copyright (C) 1995 University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%

% livemap.nl - module to build up a map that gives
%	the set of live lvals at each label.

% Author: zs.

%-----------------------------------------------------------------------------%

:- module livemap.

:- interface.

:- import_module llds, list, set, map, std_util.

:- type livemap		==	map(label, lvalset).
:- type lvalset		==	set(lval).

	% Build up a map of what lvals are live at each label.
	% This step must be iterated in the presence of backward
	% branches, which at the moment are generated by middle
	% recursion and the construction of closures.

:- pred livemap__build(list(instruction), bool, livemap).
:- mode livemap__build(in, out, out) is det.

:- implementation.

:- import_module opt_util, require.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

livemap__build(Instrs, Ccode, Livemap) :-
	map__init(Livemap0),
	list__reverse(Instrs, BackInstrs),
	livemap__build_2(BackInstrs, Livemap0, Ccode, Livemap).

:- pred livemap__build_2(list(instruction), livemap, bool, livemap).
:- mode livemap__build_2(in, di, out, uo) is det.

livemap__build_2(Backinstrs, Livemap0, Ccode, Livemap) :-
	set__init(Livevals0),
	livemap__build_livemap(Backinstrs, Livevals0, no, Ccode1,
		Livemap0, Livemap1),
	( Ccode1 = yes ->
		Ccode = yes,
		Livemap = Livemap1
	; livemap__equal_livemaps(Livemap0, Livemap1) ->
		Ccode = no,
		Livemap = Livemap1
	;
		livemap__build_2(Backinstrs, Livemap1, Ccode, Livemap)
	).

:- pred livemap__equal_livemaps(livemap, livemap).
:- mode livemap__equal_livemaps(in, in) is semidet.

livemap__equal_livemaps(Livemap1, Livemap2) :-
	map__keys(Livemap1, Labels),
	livemap__equal_livemaps_keys(Labels, Livemap1, Livemap2).

:- pred livemap__equal_livemaps_keys(list(label), livemap, livemap).
:- mode livemap__equal_livemaps_keys(in, in, in) is semidet.

livemap__equal_livemaps_keys([], _Livemap1, _Livemap2).
livemap__equal_livemaps_keys([Label | Labels], Livemap1, Livemap2) :-
	map__lookup(Livemap1, Label, Liveset1),
	map__lookup(Livemap2, Label, Liveset2),
	set__equal(Liveset1, Liveset2),
	livemap__equal_livemaps_keys(Labels, Livemap1, Livemap2).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

	% Build up a map of what lvals are live at each label.
	% The input instruction sequence is reversed.

:- pred livemap__build_livemap(list(instruction), lvalset, bool, bool,
	livemap, livemap).
:- mode livemap__build_livemap(in, in, in, out, di, uo) is det.

livemap__build_livemap([], _, Ccode, Ccode, Livemap, Livemap).
livemap__build_livemap([Instr|Moreinstrs], Livevals0, Ccode0, Ccode,
		Livemap0, Livemap) :-
	Instr = Uinstr - _Comment,
	(
		Uinstr = comment(_),
		Livemap1 = Livemap0,
		Livevals2 = Livevals0,
		Moreinstrs2 = Moreinstrs,
		Ccode1 = Ccode0
	;
		Uinstr = livevals(_),
		error("livevals found in backward scan in build_livemap")
	;
		Uinstr = block(_, _),
		error("block found in backward scan in build_livemap")
	;
		Uinstr = assign(Lval, Rval),

		% Make dead the variable assigned, but make any variables
		% needed to access it live. Make the variables in the assigned
		% expression live as well.
		% The deletion has to be done first. If the assigned-to lval
		% appears on the right hand side as well as the left, then we
		% want make_live to put it back into the liveval set.

		set__delete(Livevals0, Lval, Livevals1),
		opt_util__lval_access_rvals(Lval, Rvals),
		livemap__make_live([Rval | Rvals], Livevals1, Livevals2),
		Livemap1 = Livemap0,
		Moreinstrs2 = Moreinstrs,
		Ccode1 = Ccode0
	;
		Uinstr = call(_, _, _, _),
		opt_util__skip_comments(Moreinstrs, Moreinstrs1),
		(
			Moreinstrs1 = [Nextinstr | Evenmoreinstrs],
			Nextinstr = Nextuinstr - Nextcomment,
			Nextuinstr = livevals(Livevals1)
		->
			livemap__filter_livevals(Livevals1, Livevals2),
			Livemap1 = Livemap0,
			Moreinstrs2 = Evenmoreinstrs,
			Ccode1 = Ccode0
		;
			error("call not preceded by livevals")
		)
	;
		Uinstr = call_closure(_, _, _),
		opt_util__skip_comments(Moreinstrs, Moreinstrs1),
		(
			Moreinstrs1 = [Nextinstr | Evenmoreinstrs],
			Nextinstr = Nextuinstr - Nextcomment,
			Nextuinstr = livevals(Livevals1)
		->
			livemap__filter_livevals(Livevals1, Livevals2),
			Livemap1 = Livemap0,
			Moreinstrs2 = Evenmoreinstrs,
			Ccode1 = Ccode0
		;
			error("call_closure not preceded by livevals")
		)
	;
		Uinstr = mkframe(_, _, _),
		Livemap1 = Livemap0,
		Livevals2 = Livevals0,
		Moreinstrs2 = Moreinstrs,
		Ccode1 = Ccode0
	;
		Uinstr = modframe(_),
		Livemap1 = Livemap0,
		Livevals2 = Livevals0,
		Moreinstrs2 = Moreinstrs,
		Ccode1 = Ccode0
	;
		Uinstr = label(Label),
		map__det_insert(Livemap0, Label, Livevals0, Livemap1),
		Livevals2 = Livevals0,
		Moreinstrs2 = Moreinstrs,
		Ccode1 = Ccode0
	;
		Uinstr = goto(CodeAddr, _),
		opt_util__skip_comments(Moreinstrs, Moreinstrs1),
		opt_util__livevals_addr(CodeAddr, LivevalsNeeded),
		( LivevalsNeeded = yes ->
			(
				Moreinstrs1 = [Nextinstr | Evenmoreinstrs],
				Nextinstr = Nextuinstr - Nextcomment,
				Nextuinstr = livevals(Livevals1)
			->
				livemap__filter_livevals(Livevals1, Livevals2),
				Livemap1 = Livemap0,
				Moreinstrs2 = Evenmoreinstrs,
				Ccode1 = Ccode0
			;
				error("tailcall not preceded by livevals")
			)
		; CodeAddr = label(Label) ->
			set__init(Livevals1),
			livemap__insert_label_livevals([Label], Livemap0,
				Livevals1, Livevals2),
			Livemap1 = Livemap0,
			Moreinstrs2 = Moreinstrs,
			Ccode1 = Ccode0
		; CodeAddr = do_redo ->
			Livemap1 = Livemap0,
			Livevals2 = Livevals0,
			Moreinstrs2 = Moreinstrs,
			Ccode1 = Ccode0
		; CodeAddr = do_fail ->
			Livemap1 = Livemap0,
			Livevals2 = Livevals0,
			Moreinstrs2 = Moreinstrs,
			Ccode1 = Ccode0
		;
			error("unknown label type in build_livemap")
			% Livevals2 = Livevals0,
			% Livemap1 = Livemap0,
			% Moreinstrs2 = Moreinstrs,
			% Ccode1 = Ccode0
		)
	;
		Uinstr = computed_goto(_, Labels),
		set__init(Livevals1),
		livemap__insert_label_livevals(Labels, Livemap0,
			Livevals1, Livevals2),
		Livemap1 = Livemap0,
		Moreinstrs2 = Moreinstrs,
		Ccode1 = Ccode0
	;
		Uinstr = c_code(_),
		Livemap1 = Livemap0,
		Livevals2 = Livevals0,
		Moreinstrs2 = Moreinstrs,
		Ccode1 = yes
	;
		Uinstr = if_val(Rval, CodeAddr),
		opt_util__skip_comments(Moreinstrs, Moreinstrs1),
		(
			Moreinstrs1 = [Nextinstr | Evenmoreinstrs],
			Nextinstr = Nextuinstr - Nextcomment,
			Nextuinstr = livevals(Livevals1)
		->
			% This if_val was put here by middle_rec.
			livemap__filter_livevals(Livevals1, Livevals2),
			Livemap1 = Livemap0,
			Moreinstrs2 = Evenmoreinstrs,
			Ccode1 = Ccode0
		;
			livemap__make_live([Rval], Livevals0, Livevals1),
			( CodeAddr = label(Label) ->
				livemap__insert_label_livevals([Label], Livemap0,
					Livevals1, Livevals2)
			;	
				Livevals2 = Livevals1
			),
			Livemap1 = Livemap0,
			Moreinstrs2 = Moreinstrs,
			Ccode1 = Ccode0
		)
	;
		Uinstr = incr_hp(Lval, _, Rval),

		% Make dead the variable assigned, but make any variables
		% needed to access it live. Make the variables in the size
		% expression live as well.
		% The use of the size expression occurs after the assignment
		% to lval, but the two should never have any variables in
		% common. This is why doing the deletion first works.

		set__delete(Livevals0, Lval, Livevals1),
		opt_util__lval_access_rvals(Lval, Rvals),
		livemap__make_live([Rval | Rvals], Livevals1, Livevals2),
		Livemap1 = Livemap0,
		Moreinstrs2 = Moreinstrs,
		Ccode1 = Ccode0
	;
		Uinstr = mark_hp(Lval),
		opt_util__lval_access_rvals(Lval, Rvals),
		livemap__make_live(Rvals, Livevals0, Livevals2),
		Livemap1 = Livemap0,
		Moreinstrs2 = Moreinstrs,
		Ccode1 = Ccode0
	;
		Uinstr = restore_hp(Rval),
		livemap__make_live([Rval], Livevals0, Livevals2),
		Livemap1 = Livemap0,
		Moreinstrs2 = Moreinstrs,
		Ccode1 = Ccode0
	;
		Uinstr = incr_sp(_),
		Livevals2 = Livevals0,
		Livemap1 = Livemap0,
		Moreinstrs2 = Moreinstrs,
		Ccode1 = Ccode0
	;
		Uinstr = decr_sp(_),
		Livevals2 = Livevals0,
		Livemap1 = Livemap0,
		Moreinstrs2 = Moreinstrs,
		Ccode1 = Ccode0
	),
	livemap__build_livemap(Moreinstrs2, Livevals2, Ccode1, Ccode,
		Livemap1, Livemap).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

	% Set all lvals found in this rval to live, with the exception of
	% fields, since they are treated specially (the later stages consider
	% them to be live even if they are not explicitly in the live set).

:- pred livemap__make_live(list(rval), lvalset, lvalset).
:- mode livemap__make_live(in, di, uo) is det.

livemap__make_live([], Livevals, Livevals).
livemap__make_live([Rval | Rvals], Livevals0, Livevals) :-
	(
		Rval = lval(Lval),
		( Lval = field(_, Rval1, Rval2) ->
			livemap__make_live([Rval1, Rval2], Livevals0, Livevals1)
		;
			set__insert(Livevals0, Lval, Livevals1)
		)
	;
		Rval = create(_, _, _),
		Livevals1 = Livevals0
	;
		Rval = mkword(_, Rval1),
		livemap__make_live([Rval1], Livevals0, Livevals1)
	;
		Rval = const(_),
		Livevals1 = Livevals0
	;
		Rval = unop(_, Rval1),
		livemap__make_live([Rval1], Livevals0, Livevals1)
	;
		Rval = binop(_, Rval1, Rval2),
		livemap__make_live([Rval1, Rval2], Livevals0, Livevals1)
	;
		Rval = var(_),
		error("var rval should not propagate to value_number")
	),
	livemap__make_live(Rvals, Livevals1, Livevals).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- pred livemap__filter_livevals(lvalset, lvalset).
:- mode livemap__filter_livevals(in, out) is det.

livemap__filter_livevals(Livevals0, Livevals) :-
	set__to_sorted_list(Livevals0, Livelist),
	set__init(Livevals1),
	livemap__insert_proper_livevals(Livelist, Livevals1, Livevals).

:- pred livemap__insert_label_livevals(list(label), livemap, lvalset, lvalset).
:- mode livemap__insert_label_livevals(in, in, di, uo) is det.

livemap__insert_label_livevals([], _, Livevals, Livevals).
livemap__insert_label_livevals([Label | Labels], Livemap, Livevals0, Livevals) :-
	( map__search(Livemap, Label, LabelLivevals) ->
		set__to_sorted_list(LabelLivevals, Livelist),
		livemap__insert_proper_livevals(Livelist, Livevals0, Livevals1)
	;
		Livevals1 = Livevals0
	),
	livemap__insert_label_livevals(Labels, Livemap, Livevals1, Livevals).

:- pred livemap__insert_proper_livevals(list(lval), lvalset, lvalset).
:- mode livemap__insert_proper_livevals(in, di, uo) is det.

livemap__insert_proper_livevals([], Livevals, Livevals).
livemap__insert_proper_livevals([Live | Livelist], Livevals0, Livevals) :-
	livemap__insert_proper_liveval(Live, Livevals0, Livevals1),
	livemap__insert_proper_livevals(Livelist, Livevals1, Livevals).

	% Make sure that we insert general register and stack references only.

:- pred livemap__insert_proper_liveval(lval, lvalset, lvalset).
:- mode livemap__insert_proper_liveval(in, di, uo) is det.

livemap__insert_proper_liveval(Live, Livevals0, Livevals) :-
	( Live = reg(_) ->
		set__insert(Livevals0, Live, Livevals)
	; Live = stackvar(_) ->
		set__insert(Livevals0, Live, Livevals)
	; Live = framevar(_) ->
		set__insert(Livevals0, Live, Livevals)
	;
		Livevals = Livevals0
	).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%
