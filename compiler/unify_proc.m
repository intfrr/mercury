%-----------------------------------------------------------------------------%
% Copyright (C) 1994-2005 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%
%
% unify_proc.m:
%
%	This module encapsulates access to the proc_requests table,
%	and constructs the clauses for out-of-line complicated
%	unification procedures.
%	It also generates the code for other compiler-generated type-specific
%	predicates such as compare/3.
%
% During mode analysis, we notice each different complicated unification
% that occurs.  For each one we add a new mode to the out-of-line
% unification predicate for that type, and we record in the `proc_requests'
% table that we need to eventually modecheck that mode of the unification
% procedure.
%
% After we've done mode analysis for all the ordinary predicates, we then
% do mode analysis for the out-of-line unification procedures.  Note that
% unification procedures may call other unification procedures which have
% not yet been encountered, causing new entries to be added to the
% proc_requests table.  We store the entries in a queue and continue the
% process until the queue is empty.
%
% The same queuing mechanism is also used for procedures created by
% mode inference during mode analysis and unique mode analysis.
%
% Currently if the same complicated unification procedure is called by
% different modules, each module will end up with a copy of the code for
% that procedure.  In the long run it would be desireable to either delay
% generation of complicated unification procedures until link time (like
% Cfront does with C++ templates) or to have a smart linker which could
% merge duplicate definitions (like Borland C++).  However the amount of
% code duplication involved is probably very small, so it's definitely not
% worth worrying about right now.

% XXX What about complicated unification of an abstract type in a partially
% instantiated mode?  Currently we don't implement it correctly. Probably
% it should be disallowed, but we should issue a proper error message.

%-----------------------------------------------------------------------------%

:- module check_hlds__unify_proc.

:- interface.

:- import_module check_hlds__mode_info.
:- import_module hlds__hlds_data.
:- import_module hlds__hlds_goal.
:- import_module hlds__hlds_module.
:- import_module hlds__hlds_pred.
:- import_module mdbcomp__prim_data.
:- import_module parse_tree__prog_data.

:- import_module bool.
:- import_module io.
:- import_module list.
:- import_module std_util.

:- type proc_requests.

:- type unify_proc_id == pair(type_ctor, uni_mode).

	% Initialize the proc_requests table.

:- pred unify_proc__init_requests(proc_requests::out) is det.

	% Add a new request for a unification procedure to the
	% proc_requests table.

:- pred unify_proc__request_unify(unify_proc_id::in, inst_varset::in,
	determinism::in, prog_context::in, module_info::in, module_info::out)
	is det.

	% Add a new request for a procedure (not necessarily a unification)
	% to the request queue.  Return the procedure's newly allocated
	% proc_id.  (This is used by unique_modes.m.)

:- pred unify_proc__request_proc(pred_id::in, list(mode)::in, inst_varset::in,
	maybe(list(is_live))::in, maybe(determinism)::in, prog_context::in,
	proc_id::out, module_info::in, module_info::out) is det.

	% unify_proc__add_lazily_generated_unify_pred(TypeCtor,
	%	UnifyPredId_for_Type, !ModuleInfo).
	%
	% For most imported unification procedures, we delay
	% generating declarations and clauses until we know
	% whether they are actually needed because there
	% is a complicated unification involving the type.
	% This predicate is exported for use by higher_order.m
	% when it is specializing calls to unify/2.

:- pred unify_proc__add_lazily_generated_unify_pred(type_ctor::in,
	pred_id::out, module_info::in, module_info::out) is det.

	% unify_proc__add_lazily_generated_compare_pred_decl(TypeCtor,
	%	ComparePredId_for_Type, !ModuleInfo).
	%
	% Add declarations, but not clauses, for a compare or index predicate.

:- pred unify_proc__add_lazily_generated_compare_pred_decl(type_ctor::in,
	pred_id::out, module_info::in, module_info::out) is det.

	% Do mode analysis of the queued procedures.
	% If the first argument is `unique_mode_check',
	% then also go on and do full determinism analysis and unique mode
	% analysis on them as well.
	% The pred_table arguments are used to store copies of the
	% procedure bodies before unique mode analysis, so that
	% we can restore them before doing the next analysis pass.

:- pred modecheck_queued_procs(how_to_check_goal::in,
	pred_table::in, pred_table::out, module_info::in, module_info::out,
	bool::out, io::di, io::uo) is det.

	% Given the type and mode of a unification, look up the
	% mode number for the unification proc.

:- pred unify_proc__lookup_mode_num(module_info::in, type_ctor::in,
	uni_mode::in, determinism::in, proc_id::out) is det.

	% Generate the clauses for one of the compiler-generated
	% special predicates (compare/3, index/3, unify, etc.)

:- pred unify_proc__generate_clause_info(special_pred_id::in, (type)::in,
	hlds_type_body::in, prog_context::in, module_info::in,
	clauses_info::out) is det.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- implementation.

:- import_module check_hlds__clause_to_proc.
:- import_module check_hlds__cse_detection.
:- import_module check_hlds__det_analysis.
:- import_module check_hlds__inst_match.
:- import_module check_hlds__mode_util.
:- import_module check_hlds__modes.
:- import_module check_hlds__polymorphism.
:- import_module check_hlds__post_typecheck.
:- import_module check_hlds__switch_detection.
:- import_module check_hlds__type_util.
:- import_module check_hlds__unique_modes.
:- import_module hlds__goal_util.
:- import_module hlds__hlds_out.
:- import_module hlds__instmap.
:- import_module hlds__make_hlds.
:- import_module hlds__quantification.
:- import_module hlds__special_pred.
:- import_module libs__globals.
:- import_module libs__options.
:- import_module libs__tree.
:- import_module mdbcomp__prim_data.
:- import_module parse_tree__error_util.
:- import_module parse_tree__mercury_to_mercury.
:- import_module parse_tree__prog_mode.
:- import_module parse_tree__prog_out.
:- import_module parse_tree__prog_util.
:- import_module parse_tree__prog_type.
:- import_module recompilation.

:- import_module assoc_list.
:- import_module int.
:- import_module map.
:- import_module queue.
:- import_module require.
:- import_module set.
:- import_module string.
:- import_module term.
:- import_module varset.

	% We keep track of all the complicated unification procs we need
	% by storing them in the proc_requests structure.
	% For each unify_proc_id (i.e. type & mode), we store the proc_id
	% (mode number) of the unification procedure which corresponds to
	% that mode.

:- type unify_req_map == map(unify_proc_id, proc_id).

:- type req_queue == queue(pred_proc_id).

:- type proc_requests
	--->	proc_requests(
			unify_req_map	:: unify_req_map,
					% The assignment of proc_id
					% numbers to unify_proc_ids.
			req_queue	:: req_queue
					% The queue of procs we still
					% to generate code for.
		).

%-----------------------------------------------------------------------------%

unify_proc__init_requests(Requests) :-
	map__init(UnifyReqMap),
	queue__init(ReqQueue),
	Requests = proc_requests(UnifyReqMap, ReqQueue).

%-----------------------------------------------------------------------------%

	% Boring access predicates

:- pred unify_proc__get_unify_req_map(proc_requests::in, unify_req_map::out)
	is det.
:- pred unify_proc__get_req_queue(proc_requests::in, req_queue::out) is det.
:- pred unify_proc__set_unify_req_map(unify_req_map::in,
	proc_requests::in, proc_requests::out) is det.
:- pred unify_proc__set_req_queue(req_queue::in,
	proc_requests::in, proc_requests::out) is det.

unify_proc__get_unify_req_map(PR, PR ^ unify_req_map).
unify_proc__get_req_queue(PR, PR ^ req_queue).
unify_proc__set_unify_req_map(UnifyReqMap, PR,
	PR ^ unify_req_map := UnifyReqMap).
unify_proc__set_req_queue(ReqQueue, PR,
	PR ^ req_queue := ReqQueue).

%-----------------------------------------------------------------------------%

unify_proc__lookup_mode_num(ModuleInfo, TypeCtor, UniMode, Det, Num) :-
	(
		unify_proc__search_mode_num(ModuleInfo, TypeCtor, UniMode,
			Det, Num1)
	->
		Num = Num1
	;
		error("unify_proc.m: unify_proc__search_num failed")
	).

:- pred unify_proc__search_mode_num(module_info::in, type_ctor::in,
	uni_mode::in, determinism::in, proc_id::out) is semidet.

	% Given the type, mode, and determinism of a unification, look up the
	% mode number for the unification proc.
	% We handle semidet unifications with mode (in, in) specially - they
	% are always mode zero.  Similarly for unifications of `any' insts.
	% (It should be safe to use the `in, in' mode for any insts, since
	% we assume that `ground' and `any' have the same representation.)
	% For unreachable unifications, we also use mode zero.

unify_proc__search_mode_num(ModuleInfo, TypeCtor, UniMode, Determinism,
		ProcId) :-
	UniMode = (XInitial - YInitial -> _Final),
	(
		Determinism = semidet,
		inst_is_ground_or_any(ModuleInfo, XInitial),
		inst_is_ground_or_any(ModuleInfo, YInitial)
	->
		hlds_pred__in_in_unification_proc_id(ProcId)
	;
		XInitial = not_reached
	->
		hlds_pred__in_in_unification_proc_id(ProcId)
	;
		YInitial = not_reached
	->
		hlds_pred__in_in_unification_proc_id(ProcId)
	;
		module_info_get_proc_requests(ModuleInfo, Requests),
		unify_proc__get_unify_req_map(Requests, UnifyReqMap),
		map__search(UnifyReqMap, TypeCtor - UniMode, ProcId)
	).

%-----------------------------------------------------------------------------%

unify_proc__request_unify(UnifyId, InstVarSet, Determinism, Context,
		!ModuleInfo) :-
	UnifyId = TypeCtor - UnifyMode,

	%
	% Generating a unification procedure for a type uses its body.
	%
	module_info_get_maybe_recompilation_info(!.ModuleInfo,
		MaybeRecompInfo0),
	( MaybeRecompInfo0 = yes(RecompInfo0) ->
		recompilation__record_used_item(type_body,
			TypeCtor, TypeCtor, RecompInfo0, RecompInfo),
		module_info_set_maybe_recompilation_info(yes(RecompInfo),
			!ModuleInfo)
	;
		true
	),

	%
	% check if this unification has already been requested, or
	% if the proc is hand defined.
	%
	(
		(
			unify_proc__search_mode_num(!.ModuleInfo, TypeCtor,
				UnifyMode, Determinism, _)
		;
			module_info_types(!.ModuleInfo, TypeTable),
			map__search(TypeTable, TypeCtor, TypeDefn),
			hlds_data__get_type_defn_body(TypeDefn, TypeBody),
			(
				TypeCtor = TypeName - _TypeArity,
				TypeName = qualified(TypeModuleName, _),
				module_info_name(!.ModuleInfo, ModuleName),
				ModuleName = TypeModuleName,
				TypeBody = abstract_type(_)
			;
				type_ctor_has_hand_defined_rtti(TypeCtor,
					TypeBody)
			)
		)
	->
		true
	;
		%
		% lookup the pred_id for the unification procedure
		% that we are going to generate
		%
		module_info_get_special_pred_map(!.ModuleInfo, SpecialPredMap),
		( map__search(SpecialPredMap, unify - TypeCtor, PredId0) ->
			PredId = PredId0
		;
			% We generate unification predicates for most
			% imported types lazily, so add the declarations
			% and clauses now.
			unify_proc__add_lazily_generated_unify_pred(TypeCtor,
				PredId, !ModuleInfo)
		),

		% convert from `uni_mode' to `list(mode)'
		UnifyMode = ((X_Initial - Y_Initial) -> (X_Final - Y_Final)),
		ArgModes0 = [(X_Initial -> X_Final), (Y_Initial -> Y_Final)],

		% for polymorphic types, add extra modes for the type_infos
		in_mode(InMode),
		TypeCtor = _ - TypeArity,
		list__duplicate(TypeArity, InMode, TypeInfoModes),
		list__append(TypeInfoModes, ArgModes0, ArgModes),

		ArgLives = no,  % XXX ArgLives should be part of the UnifyId

		unify_proc__request_proc(PredId, ArgModes, InstVarSet, ArgLives,
			yes(Determinism), Context, ProcId, !ModuleInfo),

		%
		% save the proc_id for this unify_proc_id
		%
		module_info_get_proc_requests(!.ModuleInfo, Requests0),
		unify_proc__get_unify_req_map(Requests0, UnifyReqMap0),
		map__set(UnifyReqMap0, UnifyId, ProcId, UnifyReqMap),
		unify_proc__set_unify_req_map(UnifyReqMap,
			Requests0, Requests),
		module_info_set_proc_requests(Requests, !ModuleInfo)
	).

unify_proc__request_proc(PredId, ArgModes, InstVarSet, ArgLives, MaybeDet,
		Context, ProcId, !ModuleInfo) :-
	%
	% create a new proc_info for this procedure
	%
	module_info_preds(!.ModuleInfo, Preds0),
	map__lookup(Preds0, PredId, PredInfo0),
	list__length(ArgModes, Arity),
	DeclaredArgModes = no,
	add_new_proc(InstVarSet, Arity, ArgModes, DeclaredArgModes, ArgLives,
		MaybeDet, Context, address_is_not_taken, PredInfo0, PredInfo1,
		ProcId),

	%
	% copy the clauses for the procedure from the pred_info to the
	% proc_info, and mark the procedure as one that cannot
	% be processed yet
	%
	pred_info_procedures(PredInfo1, Procs1),
	pred_info_clauses_info(PredInfo1, ClausesInfo),
	map__lookup(Procs1, ProcId, ProcInfo0),
	proc_info_set_can_process(no, ProcInfo0, ProcInfo1),

	copy_clauses_to_proc(ProcId, ClausesInfo, ProcInfo1, ProcInfo2),

	proc_info_goal(ProcInfo2, Goal0),
	set_goal_contexts(Context, Goal0, Goal),
	proc_info_set_goal(Goal, ProcInfo2, ProcInfo),
	map__det_update(Procs1, ProcId, ProcInfo, Procs2),
	pred_info_set_procedures(Procs2, PredInfo1, PredInfo2),
	map__det_update(Preds0, PredId, PredInfo2, Preds2),
	module_info_set_preds(Preds2, !ModuleInfo),

	%
	% insert the pred_proc_id into the request queue
	%
	module_info_get_proc_requests(!.ModuleInfo, Requests0),
	unify_proc__get_req_queue(Requests0, ReqQueue0),
	queue__put(ReqQueue0, proc(PredId, ProcId), ReqQueue),
	unify_proc__set_req_queue(ReqQueue, Requests0, Requests),
	module_info_set_proc_requests(Requests, !ModuleInfo).

%-----------------------------------------------------------------------------%

	% XXX these belong in modes.m

modecheck_queued_procs(HowToCheckGoal, OldPredTable0, OldPredTable,
		!ModuleInfo, Changed, !IO) :-
	module_info_get_proc_requests(!.ModuleInfo, Requests0),
	unify_proc__get_req_queue(Requests0, RequestQueue0),
	(
		queue__get(RequestQueue0, PredProcId, RequestQueue1)
	->
		unify_proc__set_req_queue(RequestQueue1, Requests0, Requests1),
		module_info_set_proc_requests(Requests1, !ModuleInfo),
		%
		% Check that the procedure is valid (i.e. type-correct),
		% before we attempt to do mode analysis on it.
		% This check is necessary to avoid internal errors
		% caused by doing mode analysis on type-incorrect code.
		% XXX inefficient! This is O(N*M).
		%
		PredProcId = proc(PredId, _ProcId),
		module_info_predids(!.ModuleInfo, ValidPredIds),
		( list__member(PredId, ValidPredIds) ->
			queued_proc_progress_message(PredProcId,
				HowToCheckGoal, !.ModuleInfo, !IO),
			modecheck_queued_proc(HowToCheckGoal, PredProcId,
				OldPredTable0, OldPredTable2,
				!ModuleInfo, Changed1, !IO)
		;
			OldPredTable2 = OldPredTable0,
			Changed1 = no
		),
		modecheck_queued_procs(HowToCheckGoal, OldPredTable2,
			OldPredTable, !ModuleInfo, Changed2, !IO),
		bool__or(Changed1, Changed2, Changed)
	;
		OldPredTable = OldPredTable0,
		Changed = no
	).

:- pred queued_proc_progress_message(pred_proc_id::in, how_to_check_goal::in,
	module_info::in, io::di, io::uo) is det.

queued_proc_progress_message(PredProcId, HowToCheckGoal, ModuleInfo, !IO) :-
	globals__io_lookup_bool_option(very_verbose, VeryVerbose, !IO),
	( VeryVerbose = yes ->
		%
		% print progress message
		%
		( HowToCheckGoal = check_unique_modes ->
			io__write_string("% Analyzing modes, determinism, " ++
				"and unique-modes for\n% ", !IO)
		;
			io__write_string("% Mode-analyzing ", !IO)
		),
		PredProcId = proc(PredId, ProcId),
		hlds_out__write_pred_proc_id(ModuleInfo, PredId, ProcId, !IO),
		io__write_string("\n", !IO)
%		/*****
%		mode_list_get_initial_insts(Modes, ModuleInfo1,
%			InitialInsts),
%		io__write_string("% Initial insts: `", !IO),
%		varset__init(InstVarSet),
%		mercury_output_inst_list(InitialInsts, InstVarSet, !IO),
%		io__write_string("'\n", !IO)
%		*****/
	;
		true
	).

:- pred modecheck_queued_proc(how_to_check_goal::in, pred_proc_id::in,
	pred_table::in, pred_table::out, module_info::in, module_info::out,
	bool::out, io::di, io::uo) is det.

modecheck_queued_proc(HowToCheckGoal, PredProcId, OldPredTable0, OldPredTable,
		!ModuleInfo, Changed, !IO) :-
	%
	% mark the procedure as ready to be processed
	%
	PredProcId = proc(PredId, ProcId),
	module_info_preds(!.ModuleInfo, Preds0),
	map__lookup(Preds0, PredId, PredInfo0),
	pred_info_procedures(PredInfo0, Procs0),
	map__lookup(Procs0, ProcId, ProcInfo0),
	proc_info_set_can_process(yes, ProcInfo0, ProcInfo1),
	map__det_update(Procs0, ProcId, ProcInfo1, Procs1),
	pred_info_set_procedures(Procs1, PredInfo0, PredInfo1),
	map__det_update(Preds0, PredId, PredInfo1, Preds1),
	module_info_set_preds(Preds1, !ModuleInfo),

	%
	% modecheck the procedure
	%
	modecheck_proc(ProcId, PredId, !ModuleInfo, NumErrors, Changed1, !IO),
	( NumErrors \= 0 ->
		io__set_exit_status(1, !IO),
		OldPredTable = OldPredTable0,
		module_info_remove_predid(PredId, !ModuleInfo),
		Changed = Changed1
	;
		( HowToCheckGoal = check_unique_modes ->
			detect_switches_in_proc(ProcId, PredId, !ModuleInfo),
			detect_cse_in_proc(ProcId, PredId, !ModuleInfo, !IO),
			determinism_check_proc(ProcId, PredId, !ModuleInfo,
				!IO),
			save_proc_info(ProcId, PredId, !.ModuleInfo,
				OldPredTable0, OldPredTable),
			unique_modes__check_proc(ProcId, PredId, !ModuleInfo,
				Changed2, !IO),
			bool__or(Changed1, Changed2, Changed)
		;
			OldPredTable = OldPredTable0,
			Changed = Changed1
		)
	).

%
% save a copy of the proc info for the specified procedure in OldProcTable0,
% giving OldProcTable.
%
:- pred save_proc_info(proc_id::in, pred_id::in, module_info::in,
	pred_table::in, pred_table::out) is det.

save_proc_info(ProcId, PredId, ModuleInfo, OldPredTable0, OldPredTable) :-
	module_info_pred_proc_info(ModuleInfo, PredId, ProcId,
		_PredInfo, ProcInfo),
	map__lookup(OldPredTable0, PredId, OldPredInfo0),
	pred_info_procedures(OldPredInfo0, OldProcTable0),
	map__set(OldProcTable0, ProcId, ProcInfo, OldProcTable),
	pred_info_set_procedures(OldProcTable, OldPredInfo0, OldPredInfo),
	map__det_update(OldPredTable0, PredId, OldPredInfo, OldPredTable).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

unify_proc__add_lazily_generated_unify_pred(TypeCtor,
		PredId, ModuleInfo0, ModuleInfo) :-
	(
		type_ctor_is_tuple(TypeCtor)
	->
		TypeCtor = _ - TupleArity,

		%
		% Build a hlds_type_body for the tuple constructor, which will
		% be used by unify_proc__generate_clause_info.
		%

		varset__init(TVarSet0),
		varset__new_vars(TVarSet0, TupleArity, TupleArgTVars, TVarSet),
		term__var_list_to_term_list(TupleArgTVars, TupleArgTypes),

		% Tuple constructors can't be existentially quantified.
		ExistQVars = [],
		ClassConstraints = [],

		MakeUnamedField = (func(ArgType) = no - ArgType),
		CtorArgs = list__map(MakeUnamedField, TupleArgTypes),

		Ctor = ctor(ExistQVars, ClassConstraints, CtorSymName,
			CtorArgs),

		CtorSymName = unqualified("{}"),
		ConsId = cons(CtorSymName, TupleArity),
		map__from_assoc_list([ConsId - single_functor],
			ConsTagValues),
		TypeBody = du_type([Ctor], ConsTagValues, IsEnum, UnifyPred,
				ReservedTag, IsForeign),
		UnifyPred = no,
		IsEnum = no,
		IsForeign = no,
		ReservedTag = no,
		IsForeign = no,
		construct_type(TypeCtor, TupleArgTypes, Type),

		term__context_init(Context)
	;
		unify_proc__collect_type_defn(ModuleInfo0, TypeCtor,
			Type, TVarSet, TypeBody, Context)
	),

	% Call make_hlds.m to construct the unification predicate.
	(
		can_generate_special_pred_clauses_for_type(ModuleInfo0,
			TypeCtor, TypeBody)
	->
		% If the unification predicate has another status it should
		% already have been generated.
		UnifyPredStatus = pseudo_imported,
		Item = clauses
	;
		UnifyPredStatus = imported(implementation),
		Item = declaration
	),

	unify_proc__add_lazily_generated_special_pred(unify, Item,
		TVarSet, Type, TypeCtor, TypeBody, Context, UnifyPredStatus,
		PredId, ModuleInfo0, ModuleInfo).

unify_proc__add_lazily_generated_compare_pred_decl(TypeCtor,
		PredId, ModuleInfo0, ModuleInfo) :-
	unify_proc__collect_type_defn(ModuleInfo0, TypeCtor, Type,
		TVarSet, TypeBody, Context),

	% If the compare predicate has another status it should
	% already have been generated.
	ImportStatus = imported(implementation),

	unify_proc__add_lazily_generated_special_pred(compare, declaration,
		TVarSet, Type, TypeCtor, TypeBody, Context, ImportStatus,
		PredId, ModuleInfo0, ModuleInfo).

:- pred unify_proc__add_lazily_generated_special_pred(special_pred_id::in,
	unify_pred_item::in, tvarset::in, (type)::in, type_ctor::in,
	hlds_type_body::in, context::in, import_status::in, pred_id::out,
	module_info::in, module_info::out) is det.

unify_proc__add_lazily_generated_special_pred(SpecialId, Item,
		TVarSet, Type, TypeCtor, TypeBody, Context,
		PredStatus, PredId, !ModuleInfo) :-
	%
	% Add the declaration and maybe clauses.
	%
	(
		Item = clauses,
		make_hlds__add_special_pred_for_real(SpecialId, TVarSet,
			Type, TypeCtor, TypeBody, Context, PredStatus,
			!ModuleInfo)
	;
		Item = declaration,
		make_hlds__add_special_pred_decl_for_real(SpecialId, TVarSet,
			Type, TypeCtor, Context, PredStatus, !ModuleInfo)
	),

	module_info_get_special_pred_map(!.ModuleInfo, SpecialPredMap),
	map__lookup(SpecialPredMap, SpecialId - TypeCtor, PredId),
	module_info_pred_info(!.ModuleInfo, PredId, PredInfo0),

	%
	% The clauses are generated with all type information computed,
	% so just go on to post_typecheck.
	%
	(
		Item = clauses,
		post_typecheck__finish_pred_no_io(!.ModuleInfo,
			ErrorProcs, PredInfo0, PredInfo)
	;
		Item = declaration,
		post_typecheck__finish_imported_pred_no_io(!.ModuleInfo,
			ErrorProcs,  PredInfo0, PredInfo)
	),
	require(unify(ErrorProcs, []),
		"unify_proc__add_lazily_generated_special_pred: " ++
		"error in post_typecheck"),

	%
	% Call polymorphism to introduce type_info arguments
	% for polymorphic types.
	%
	module_info_set_pred_info(PredId, PredInfo, !ModuleInfo),

	%
	% Note that this will not work if the generated clauses call
	% a polymorphic predicate which requires type_infos to be added.
	% Such calls can be generated by unify_proc__generate_clause_info,
	% but unification predicates which contain such calls are never
	% generated lazily.
	%
	polymorphism__process_generated_pred(PredId, !ModuleInfo).

:- type unify_pred_item
	--->	declaration
	;	clauses.

:- pred unify_proc__collect_type_defn(module_info::in, type_ctor::in,
	(type)::out, tvarset::out, hlds_type_body::out, prog_context::out)
	is det.

unify_proc__collect_type_defn(ModuleInfo0, TypeCtor, Type,
		TVarSet, TypeBody, Context) :-
	module_info_types(ModuleInfo0, Types),
	map__lookup(Types, TypeCtor, TypeDefn),
	hlds_data__get_type_defn_tvarset(TypeDefn, TVarSet),
	hlds_data__get_type_defn_tparams(TypeDefn, TypeParams),
	hlds_data__get_type_defn_body(TypeDefn, TypeBody),
	hlds_data__get_type_defn_status(TypeDefn, TypeStatus),
	hlds_data__get_type_defn_context(TypeDefn, Context),

	require(special_pred_is_generated_lazily(ModuleInfo0,
		TypeCtor, TypeBody, TypeStatus),
		"unify_proc__add_lazily_generated_unify_pred"),

	construct_type(TypeCtor, TypeParams, Type).

%-----------------------------------------------------------------------------%

unify_proc__generate_clause_info(SpecialPredId, Type, TypeBody, Context,
		ModuleInfo, ClauseInfo) :-
	special_pred_interface(SpecialPredId, Type, ArgTypes, _Modes, _Det),
	unify_proc__info_init(ModuleInfo, Info0),
	unify_proc__make_fresh_named_vars_from_types(ArgTypes, "HeadVar__", 1,
		Args, Info0, Info1),
	( SpecialPredId = unify, Args = [H1, H2] ->
		unify_proc__generate_unify_clauses(ModuleInfo, Type, TypeBody,
			H1, H2, Context, Clauses, Info1, Info)
	; SpecialPredId = index, Args = [X, Index] ->
		unify_proc__generate_index_clauses(ModuleInfo, TypeBody,
			X, Index, Context, Clauses, Info1, Info)
	; SpecialPredId = compare, Args = [Res, X, Y] ->
		unify_proc__generate_compare_clauses(ModuleInfo, Type,
			TypeBody, Res, X, Y, Context, Clauses, Info1, Info)
	; SpecialPredId = initialise, Args = [X] ->
		unify_proc__generate_initialise_clauses(ModuleInfo, Type,
			TypeBody, X, Context, Clauses, Info1, Info)

	;
		error("unknown special pred")
	),
	unify_proc__info_extract(Info, VarSet, Types),
	map__init(TVarNameMap),
	rtti_varmaps_init(RttiVarMaps),
	set_clause_list(Clauses, ClausesRep),
	HasForeignClauses = yes,
	ClauseInfo = clauses_info(VarSet, Types, TVarNameMap, Types, Args,
		ClausesRep, RttiVarMaps, HasForeignClauses).


:- pred unify_proc__generate_initialise_clauses(module_info::in, (type)::in,
	hlds_type_body::in, prog_var::in, prog_context::in,
	list(clause)::out, unify_proc_info::in, unify_proc_info::out) is det.

unify_proc__generate_initialise_clauses(ModuleInfo, _Type, TypeBody,
		X, Context, Clauses, !Info) :-
	(
		type_util__type_body_has_solver_type_details(ModuleInfo,
			TypeBody, SolverTypeDetails)
	->
		% Just generate a call to the specified predicate,
		% which is the user-defined equality pred for this
		% type.
		% (The pred_id and proc_id will be figured
		% out by type checking and mode analysis.)
		%
		InitPred = SolverTypeDetails ^ init_pred,
		PredId = invalid_pred_id,
		ModeId = invalid_proc_id,
		Call = call(PredId, ModeId, [X], not_builtin, no, InitPred),
		goal_info_init(Context, GoalInfo),
		Goal = Call - GoalInfo,
		unify_proc__quantify_clauses_body([X], Goal, Context, Clauses,
			!Info)
	;
		% If this is an equivalence type then we just generate a
		% call to the initialisation pred of the type on the RHS
		% of the equivalence and cast the result back to the type
		% on the LHS of the equivalence.
		TypeBody = eqv_type(EqvType)
	->
		goal_info_init(Context, GoalInfo),
		unify_proc__make_fresh_named_var_from_type(EqvType,
			"PreCast_HeadVar", 1, X0, !Info),
		(
			type_to_ctor_and_args(EqvType, TypeCtor0, _TypeArgs)
		->
			TypeCtor = TypeCtor0
		;
			error("unify_proc__generate_initialise_clauses: " ++
				"type_to_ctor_and_args failed")
		),
		PredName = special_pred__special_pred_name(initialise,
				TypeCtor),
		hlds_module__module_info_name(ModuleInfo, ModuleName),
		TypeCtor = TypeSymName - _TypeArity,
		sym_name_get_module_name(TypeSymName, ModuleName,
			TypeModuleName),
		InitPred = qualified(TypeModuleName, PredName),
		PredId   = invalid_pred_id,
		ModeId   = invalid_proc_id,
		InitCall = call(PredId, ModeId, [X0], not_builtin, no,
				InitPred),
		InitGoal = InitCall - GoalInfo,

		Any = any(shared),
		generate_cast(equiv_type_cast, X0, X, Any, Any, Context,
			CastGoal),
		Goal = conj([InitGoal, CastGoal]) - GoalInfo,
		unify_proc__quantify_clauses_body([X], Goal, Context, Clauses,
			!Info)
	;
		error("unify_proc__generate_initialise_clauses: " ++
			"trying to create initialisation proc for type " ++
			"that has no solver_type_details")
	).


:- pred unify_proc__generate_unify_clauses(module_info::in, (type)::in,
	hlds_type_body::in, prog_var::in, prog_var::in, prog_context::in,
	list(clause)::out, unify_proc_info::in, unify_proc_info::out) is det.

unify_proc__generate_unify_clauses(ModuleInfo, Type, TypeBody,
		H1, H2, Context, Clauses, !Info) :-
	(
		type_body_has_user_defined_equality_pred(ModuleInfo,
			TypeBody, UserEqComp)
	->
		unify_proc__generate_user_defined_unify_clauses(UserEqComp,
			H1, H2, Context, Clauses, !Info)
	;
		(
			Ctors = TypeBody ^ du_type_ctors,
			IsEnum = TypeBody ^ du_type_is_enum,
			(
				%
				% Enumerations are atomic types, so
				% modecheck_unify.m will treat this
				% unification as a simple_test, not
				% a complicated_unify.
				%
				IsEnum = yes,
				create_atomic_unification(H1, var(H2),
					Context, explicit, [], Goal),
				unify_proc__quantify_clauses_body([H1, H2],
					Goal, Context, Clauses, !Info)
			;
				IsEnum = no,
				unify_proc__generate_du_unify_clauses(Ctors,
					H1, H2, Context, Clauses, !Info)
			)
		;
			TypeBody = eqv_type(EqvType),
			generate_unify_clauses_eqv_type(EqvType, H1, H2,
				Context, Clauses, !Info)
		;
			TypeBody = solver_type(_, _),
			% If no user defined equality predicate is given,
			% we treat solver types as if they were an equivalent
			% to the builtin type c_pointer.
			generate_unify_clauses_eqv_type(c_pointer_type,
				H1, H2, Context, Clauses, !Info)
		;
			TypeBody = foreign_type(_),
			% If no user defined equality predicate is given,
			% we treat foreign_type as if they were an equivalent
			% to the builtin type c_pointer.
			generate_unify_clauses_eqv_type(c_pointer_type,
				H1, H2, Context, Clauses, !Info)
		;
			TypeBody = abstract_type(_),
			( compiler_generated_rtti_for_builtins(ModuleInfo) ->
				TypeCategory = classify_type(ModuleInfo, Type),
				generate_builtin_unify(TypeCategory,
					H1, H2, Context, Clauses, !Info)
			;
				error("trying to create unify proc " ++
					"for abstract type")
			)

		)
	).

:- pred generate_builtin_unify((type_category)::in,
	prog_var::in, prog_var::in, prog_context::in, list(clause)::out,
	unify_proc_info::in, unify_proc_info::out) is det.

generate_builtin_unify(TypeCategory, H1, H2, Context, Clauses, !Info) :-
	ArgVars = [H1, H2],

	% can_generate_special_pred_clauses_for_type ensures the unexpected
	% cases can never occur.
	(
		TypeCategory = int_type,
		Name = "builtin_unify_int"
	;
		TypeCategory = char_type,
		Name = "builtin_unify_character"
	;
		TypeCategory = str_type,
		Name = "builtin_unify_string"
	;
		TypeCategory = float_type,
		Name = "builtin_unify_float"
	;
		TypeCategory = higher_order_type,
		Name = "builtin_unify_pred"
	;
		TypeCategory = tuple_type,
		unexpected(this_file, "generate_builtin_unify: tuple")
	;
		TypeCategory = enum_type,
		unexpected(this_file, "generate_builtin_unify: enum")
	;
		TypeCategory = variable_type,
		unexpected(this_file, "generate_builtin_unify: variable type")
	;
		TypeCategory = type_info_type,
		unexpected(this_file, "generate_builtin_unify: type_info type")
	;
		TypeCategory = type_ctor_info_type,
		unexpected(this_file,
			"generate_builtin_unify: type_ctor_info type")
	;
		TypeCategory = typeclass_info_type,
		unexpected(this_file,
			"generate_builtin_unify: typeclass_info type")
	;
		TypeCategory = base_typeclass_info_type,
		unexpected(this_file,
			"generate_builtin_unify: base_typeclass_info type")
	;
		TypeCategory = void_type,
		unexpected(this_file,
			"generate_builtin_unify: void type")
	;
		TypeCategory = user_ctor_type,
		unexpected(this_file,
			"generate_builtin_unify: user_ctor type")
	),
	unify_proc__build_call(Name, ArgVars, Context, UnifyGoal, !Info),
	quantify_clauses_body(ArgVars, UnifyGoal, Context, Clauses, !Info).

:- pred unify_proc__generate_user_defined_unify_clauses(unify_compare::in,
	prog_var::in, prog_var::in, prog_context::in, list(clause)::out,
	unify_proc_info::in, unify_proc_info::out) is det.

unify_proc__generate_user_defined_unify_clauses(
		abstract_noncanonical_type(_IsSolverType),
		_, _, _, _, !Info) :-
	error("trying to create unify proc for abstract noncanonical type").
unify_proc__generate_user_defined_unify_clauses(UserEqCompare, H1, H2,
		Context, Clauses, !Info) :-
	UserEqCompare = unify_compare(MaybeUnify, MaybeCompare),
	( MaybeUnify = yes(UnifyPredName) ->
		%
		% Just generate a call to the specified predicate,
		% which is the user-defined equality pred for this
		% type.
		% (The pred_id and proc_id will be figured
		% out by type checking and mode analysis.)
		%
		PredId = invalid_pred_id,
		ModeId = invalid_proc_id,
		Call = call(PredId, ModeId, [H1, H2], not_builtin, no,
			UnifyPredName),
		goal_info_init(Context, GoalInfo),
		Goal = Call - GoalInfo
	; MaybeCompare = yes(ComparePredName) ->
		%
		% Just generate a call to the specified predicate,
		% which is the user-defined comparison pred for this
		% type, and unify the result with `='.
		% (The pred_id and proc_id will be figured
		% out by type checking and mode analysis.)
		%
		unify_proc__info_new_var(comparison_result_type, ResultVar,
			!Info),
		PredId = invalid_pred_id,
		ModeId = invalid_proc_id,
		Call = call(PredId, ModeId, [ResultVar, H1, H2], not_builtin,
			no, ComparePredName),
		goal_info_init(Context, GoalInfo),
		CallGoal = Call - GoalInfo,

		mercury_public_builtin_module(Builtin),
		create_atomic_unification(ResultVar,
			functor(cons(qualified(Builtin, "="), 0), no, []),
			Context, explicit, [], UnifyGoal),
		Goal = conj([CallGoal, UnifyGoal]) - GoalInfo
	;
		error("unify_proc__generate_user_defined_unify_clauses")
	),
	unify_proc__quantify_clauses_body([H1, H2], Goal, Context, Clauses,
		!Info).

:- pred generate_unify_clauses_eqv_type((type)::in, prog_var::in, prog_var::in,
	prog_context::in, list(clause)::out,
	unify_proc_info::in, unify_proc_info::out) is det.

generate_unify_clauses_eqv_type(EqvType, H1, H2, Context, Clauses, !Info) :-
	% We should check whether EqvType is a type variable,
	% an abstract type or a concrete type.
	% If it is type variable, then we should generate the same code
	% we generate now. If it is an abstract type, we should call
	% its unification procedure directly; if it is a concrete type,
	% we should generate the body of its unification procedure
	% inline here.
	unify_proc__make_fresh_named_var_from_type(EqvType,
		"Cast_HeadVar", 1, CastVar1, !Info),
	unify_proc__make_fresh_named_var_from_type(EqvType,
		"Cast_HeadVar", 2, CastVar2, !Info),
	generate_cast(equiv_type_cast, H1, CastVar1, Context, Cast1Goal),
	generate_cast(equiv_type_cast, H2, CastVar2, Context, Cast2Goal),
	create_atomic_unification(CastVar1, var(CastVar2), Context,
		explicit, [], UnifyGoal),

	goal_info_init(GoalInfo0),
	goal_info_set_context(GoalInfo0, Context, GoalInfo),
	conj_list_to_goal([Cast1Goal, Cast2Goal, UnifyGoal], GoalInfo, Goal),
	unify_proc__quantify_clauses_body([H1, H2], Goal, Context, Clauses,
		!Info).

	% This predicate generates the bodies of index predicates for the
	% types that need index predicates.
	%
	% add_special_preds in make_hlds.m should include index in the list
	% of special preds to define only for the kinds of types which do not
	% lead this predicate to abort.

:- pred unify_proc__generate_index_clauses(module_info::in, hlds_type_body::in,
	prog_var::in, prog_var::in, prog_context::in, list(clause)::out,
	unify_proc_info::in, unify_proc_info::out) is det.

unify_proc__generate_index_clauses(ModuleInfo, TypeBody,
		X, Index, Context, Clauses, !Info) :-
	( type_body_has_user_defined_equality_pred(ModuleInfo, TypeBody, _) ->
		%
		% For non-canonical types, the generated comparison
		% predicate either calls a user-specified comparison
		% predicate or returns an error, and does not call the
		% type's index predicate, so do not generate an index
		% predicate for such types.
		%
		error("trying to create index proc for non-canonical type")
	;
		(
			Ctors = TypeBody ^ du_type_ctors,
			IsEnum = TypeBody ^ du_type_is_enum,
			(
				%
				% For enum types, the generated comparison
				% predicate performs an integer comparison,
				% and does not call the type's index predicate,
				% so do not generate an index predicate for
				% such types.
				%
				IsEnum = yes,
				error("trying to create index proc " ++
					"for enum type")
			;
				IsEnum = no,
				unify_proc__generate_du_index_clauses(Ctors,
					X, Index, Context, 0, Clauses, !Info)
			)
		;
			TypeBody = eqv_type(_Type),
			% The only place that the index predicate for a type
			% can ever be called from is the compare predicate
			% for that type. However, the compare predicate for
			% an equivalence type never calls the index predicate
			% for that type; it calls the compare predicate of
			% the expanded type instead. Therefore the clause body
			% we are generating should never be invoked.
			error("trying to create index proc for eqv type")
		;
			TypeBody = foreign_type(_),
			error("trying to create index proc for a foreign type")
		;
			TypeBody = solver_type(_, _),
			error("trying to create index proc for a solver type")
		;
			TypeBody = abstract_type(_),
			error("trying to create index proc for abstract type")
		)
	).

:- pred unify_proc__generate_compare_clauses(module_info::in, (type)::in,
	hlds_type_body::in, prog_var::in, prog_var::in, prog_var::in,
	prog_context::in, list(clause)::out,
	unify_proc_info::in, unify_proc_info::out) is det.

unify_proc__generate_compare_clauses(ModuleInfo, Type, TypeBody, Res,
		H1, H2, Context, Clauses, !Info) :-
	(
		type_body_has_user_defined_equality_pred(ModuleInfo,
			TypeBody, UserEqComp)
	->
		generate_user_defined_compare_clauses(UserEqComp,
			Res, H1, H2, Context, Clauses, !Info)
	;
		(
			Ctors = TypeBody ^ du_type_ctors,
			IsEnum = TypeBody ^ du_type_is_enum,
			(
				IsEnum = yes,
				IntType = int_type,
				unify_proc__make_fresh_named_var_from_type(
					IntType, "Cast_HeadVar", 1, CastVar1,
					!Info),
				unify_proc__make_fresh_named_var_from_type(
					IntType, "Cast_HeadVar", 2, CastVar2,
					!Info),
				generate_cast(unsafe_type_cast, H1, CastVar1,
					Context, Cast1Goal),
				generate_cast(unsafe_type_cast, H2, CastVar2,
					Context, Cast2Goal),
				unify_proc__build_call("builtin_compare_int",
					[Res, CastVar1, CastVar2], Context,
					CompareGoal, !Info),

				goal_info_init(GoalInfo0),
				goal_info_set_context(GoalInfo0, Context,
					GoalInfo),
				conj_list_to_goal([Cast1Goal, Cast2Goal,
					CompareGoal], GoalInfo, Goal),
				unify_proc__quantify_clauses_body(
					[Res, H1, H2], Goal, Context, Clauses,
					!Info)
			;
				IsEnum = no,
				unify_proc__generate_du_compare_clauses(Type,
					Ctors, Res, H1, H2, Context, Clauses,
					!Info)
			)
		;
			TypeBody = eqv_type(EqvType),
			generate_compare_clauses_eqv_type(EqvType,
				Res, H1, H2, Context, Clauses, !Info)
		;
			TypeBody = foreign_type(_),
			generate_compare_clauses_eqv_type(c_pointer_type,
				Res, H1, H2, Context, Clauses, !Info)
		;
			TypeBody = solver_type(_, _),
			generate_compare_clauses_eqv_type(c_pointer_type,
				Res, H1, H2, Context, Clauses, !Info)
		;
			TypeBody = abstract_type(_),
			( compiler_generated_rtti_for_builtins(ModuleInfo) ->
				TypeCategory = classify_type(ModuleInfo, Type),
				generate_builtin_compare(TypeCategory, Res,
					H1, H2, Context, Clauses, !Info)
			;
				error("trying to create compare proc " ++
					"for abstract type")
			)
		)
	).

:- pred generate_builtin_compare(type_category::in,
	prog_var::in, prog_var::in, prog_var::in,
	prog_context::in, list(clause)::out,
	unify_proc_info::in, unify_proc_info::out) is det.

generate_builtin_compare(TypeCategory, Res, H1, H2, Context, Clauses, !Info) :-
	ArgVars = [Res, H1, H2],

	% can_generate_special_pred_clauses_for_type ensures the unexpected
	% cases can never occur.
	(
		TypeCategory = int_type,
		Name = "builtin_compare_int"
	;
		TypeCategory = char_type,
		Name = "builtin_compare_character"
	;
		TypeCategory = str_type,
		Name = "builtin_compare_string"
	;
		TypeCategory = float_type,
		Name = "builtin_compare_float"
	;
		TypeCategory = higher_order_type,
		Name = "builtin_compare_pred"
	;
		TypeCategory = tuple_type,
		unexpected(this_file, "generate_builtin_compare: tuple type")
	;
		TypeCategory = enum_type,
		unexpected(this_file, "generate_builtin_compare: enum type")
	;
		TypeCategory = variable_type,
		unexpected(this_file, "generate_builtin_compare: variable type")
	;
		TypeCategory = type_info_type,
		unexpected(this_file,
			"generate_builtin_compare: type_info type")
	;
		TypeCategory = type_ctor_info_type,
		unexpected(this_file,
			"generate_builtin_compare: type_ctor_info type")
	;
		TypeCategory = typeclass_info_type,
		unexpected(this_file,
			"generate_builtin_compare: typeclass_info type")
	;
		TypeCategory = base_typeclass_info_type,
		unexpected(this_file,
			"generate_builtin_compare: base_typeclass_info type")
	;
		TypeCategory = void_type,
		unexpected(this_file,
			"generate_builtin_compare: void type")
	;
		TypeCategory = user_ctor_type,
		unexpected(this_file,
			"generate_builtin_compare: user_ctor type")
	),
	unify_proc__build_call(Name, ArgVars, Context, CompareGoal, !Info),
	quantify_clauses_body(ArgVars, CompareGoal, Context, Clauses, !Info).

:- pred generate_user_defined_compare_clauses(unify_compare::in,
	prog_var::in, prog_var::in, prog_var::in,
	prog_context::in, list(clause)::out,
	unify_proc_info::in, unify_proc_info::out) is det.

generate_user_defined_compare_clauses(abstract_noncanonical_type(_),
		_, _, _, _, _, !Info) :-
	error("trying to create compare proc for abstract noncanonical type").
generate_user_defined_compare_clauses(unify_compare(_, MaybeCompare),
		Res, H1, H2, Context, Clauses, !Info) :-
	ArgVars = [Res, H1, H2],
	(
		MaybeCompare = yes(ComparePredName),
		%
		% Just generate a call to the specified predicate,
		% which is the user-defined comparison pred for this
		% type.
		% (The pred_id and proc_id will be figured
		% out by type checking and mode analysis.)
		%
		PredId = invalid_pred_id,
		ModeId = invalid_proc_id,
		Call = call(PredId, ModeId, ArgVars, not_builtin,
			no, ComparePredName),
		goal_info_init(Context, GoalInfo),
		Goal = Call - GoalInfo
	;
		MaybeCompare = no,
		%
		% just generate code that will call error/1
		%
		unify_proc__build_call("builtin_compare_non_canonical_type",
			ArgVars, Context, Goal, !Info)
	),
	unify_proc__quantify_clauses_body(ArgVars, Goal, Context, Clauses,
		!Info).

:- pred generate_compare_clauses_eqv_type((type)::in,
	prog_var::in, prog_var::in, prog_var::in,
	prog_context::in, list(clause)::out,
	unify_proc_info::in, unify_proc_info::out) is det.

generate_compare_clauses_eqv_type(EqvType, Res, H1, H2, Context, Clauses,
		!Info) :-
	% We should check whether EqvType is a type variable,
	% an abstract type or a concrete type.
	% If it is type variable, then we should generate the same code
	% we generate now. If it is an abstract type, we should call
	% its comparison procedure directly; if it is a concrete type,
	% we should generate the body of its comparison procedure
	% inline here.
	unify_proc__make_fresh_named_var_from_type(EqvType,
		"Cast_HeadVar", 1, CastVar1, !Info),
	unify_proc__make_fresh_named_var_from_type(EqvType,
		"Cast_HeadVar", 2, CastVar2, !Info),
	generate_cast(equiv_type_cast, H1, CastVar1, Context, Cast1Goal),
	generate_cast(equiv_type_cast, H2, CastVar2, Context, Cast2Goal),
	unify_proc__build_call("compare", [Res, CastVar1, CastVar2],
		Context, CompareGoal, !Info),

	goal_info_init(GoalInfo0),
	goal_info_set_context(GoalInfo0, Context, GoalInfo),
	conj_list_to_goal([Cast1Goal, Cast2Goal, CompareGoal],
		GoalInfo, Goal),
	unify_proc__quantify_clauses_body([Res, H1, H2], Goal, Context,
		Clauses, !Info).

:- pred unify_proc__quantify_clauses_body(list(prog_var)::in, hlds_goal::in,
	prog_context::in, list(clause)::out,
	unify_proc_info::in, unify_proc_info::out) is det.

unify_proc__quantify_clauses_body(HeadVars, Goal, Context, Clauses, !Info) :-
	unify_proc__quantify_clause_body(HeadVars, Goal, Context, Clause,
		!Info),
	Clauses = [Clause].

:- pred unify_proc__quantify_clause_body(list(prog_var)::in, hlds_goal::in,
	prog_context::in, clause::out,
	unify_proc_info::in, unify_proc_info::out) is det.

unify_proc__quantify_clause_body(HeadVars, Goal0, Context, Clause, !Info) :-
	unify_proc__info_get_varset(Varset0, !Info),
	unify_proc__info_get_types(Types0, !Info),
	implicitly_quantify_clause_body(HeadVars, _Warnings, Goal0, Goal,
		Varset0, Varset, Types0, Types),
	unify_proc__info_set_varset(Varset, !Info),
	unify_proc__info_set_types(Types, !Info),
	Clause = clause([], Goal, mercury, Context).

%-----------------------------------------------------------------------------%

% For a type such as
%
%	type t ---> a1 ; a2 ; b(int) ; c(float); d(int, string, t).
%
% we want to generate the code
%
%	__Unify__(X, Y) :-
%		(
%			X = a1,
%			Y = X
%			% Actually, to avoid infinite recursion,
%			% the above unification is done as type int:
%			%	CastX = unsafe_cast(X) `with_type` int,
%			%	CastY = unsafe_cast(Y) `with_type` int,
%			%	CastX = CastY
%		;
%			X = a2,
%			Y = X	% Likewise, done as type int
%		;
%			X = b(X1),
%			Y = b(Y2),
%			X1 = Y2,
%		;
%			X = c(X1),
%			Y = c(Y1),
%			X1 = X2,
%		;
%			X = d(X1, X2, X3),
%			Y = c(Y1, Y2, Y3),
%			X1 = y1,
%			X2 = Y2,
%			X3 = Y3
%		).
%
% Note that in the disjuncts handling constants, we want to unify Y with X,
% not with the constant. Doing this allows dupelim to take the code fragments
% implementing the switch arms for constants and eliminate all but one of them.
% This can be a significant code size saving for types with lots of constants,
% such as the one representing Aditi bytecodes, which can lead to significant
% reductions in C compilation time.
%
% The keep_constant_binding feature on the cast goals is there to ask
% mode analysis to copy any known bound inst on the cast-from variable
% to the cast-to variable. This is necessary to keep determinism analysis
% working for modes in which the inputs of the unify predicate are known
% to be bound to the same constant, modes whose determinism should therefore
% be inferred to be det. (tests/general/det_complicated_unify2.m tests
% this case.)

:- pred unify_proc__generate_du_unify_clauses(list(constructor)::in,
	prog_var::in, prog_var::in, prog_context::in, list(clause)::out,
	unify_proc_info::in, unify_proc_info::out) is det.

unify_proc__generate_du_unify_clauses([], _X, _Y, _Context, [], !Info).
unify_proc__generate_du_unify_clauses([Ctor | Ctors], X, Y, Context,
		[Clause | Clauses], !Info) :-
	Ctor = ctor(ExistQTVars, _Constraints, FunctorName, ArgTypes),
	list__length(ArgTypes, FunctorArity),
	FunctorConsId = cons(FunctorName, FunctorArity),
	(
		ArgTypes = [],
		can_compare_constants_as_ints(!.Info) = yes
	->
		create_atomic_unification(
			X, functor(FunctorConsId, no, []), Context,
			explicit, [], UnifyX_Goal),
		unify_proc__info_new_named_var(int_type, "CastX", CastX,
			!Info),
		unify_proc__info_new_named_var(int_type, "CastY", CastY,
			!Info),
		generate_cast(unsafe_type_cast, X, CastX, Context, CastXGoal0),
		generate_cast(unsafe_type_cast, Y, CastY, Context, CastYGoal0),
		goal_add_feature(CastXGoal0, keep_constant_binding, CastXGoal),
		goal_add_feature(CastYGoal0, keep_constant_binding, CastYGoal),
		create_atomic_unification(CastY, var(CastX), Context,
			explicit, [], UnifyY_Goal),
		GoalList = [UnifyX_Goal, CastXGoal, CastYGoal, UnifyY_Goal]
	;
		unify_proc__make_fresh_vars(ArgTypes, ExistQTVars, Vars1,
			!Info),
		unify_proc__make_fresh_vars(ArgTypes, ExistQTVars, Vars2,
			!Info),
		create_atomic_unification(
			X, functor(FunctorConsId, no, Vars1), Context,
			explicit, [], UnifyX_Goal),
		create_atomic_unification(
			Y, functor(FunctorConsId, no, Vars2), Context,
			explicit, [], UnifyY_Goal),
		unify_proc__unify_var_lists(ArgTypes, ExistQTVars,
			Vars1, Vars2, UnifyArgs_Goals, !Info),
		GoalList = [UnifyX_Goal, UnifyY_Goal | UnifyArgs_Goals]
	),
	goal_info_init(GoalInfo0),
	goal_info_set_context(GoalInfo0, Context, GoalInfo),
	conj_list_to_goal(GoalList, GoalInfo, Goal),
	unify_proc__quantify_clause_body([X, Y], Goal, Context, Clause, !Info),
	unify_proc__generate_du_unify_clauses(Ctors, X, Y, Context, Clauses,
		!Info).

	% Succeed iff the target back end guarantees that comparing two
	% constants for equality can be done by casting them both to integers
	% and comparing the integers for equality.
:- func can_compare_constants_as_ints(unify_proc_info) = bool.

can_compare_constants_as_ints(Info) = CanCompareAsInt :-
	ModuleInfo = Info ^ module_info,
	module_info_globals(ModuleInfo, Globals),
	lookup_bool_option(Globals, can_compare_constants_as_ints,
		CanCompareAsInt).

%-----------------------------------------------------------------------------%

% For a type such as
%
%	:- type foo ---> f ; g(a, b, c) ; h(foo).
%
% we want to generate the code
%
%	index(X, Index) :-
%		(
%			X = f,
%			Index = 0
%		;
%			X = g(_, _, _),
%			Index = 1
%		;
%			X = h(_),
%			Index = 2
%		).

:- pred unify_proc__generate_du_index_clauses(list(constructor)::in,
	prog_var::in, prog_var::in, prog_context::in, int::in,
	list(clause)::out, unify_proc_info::in, unify_proc_info::out) is det.

unify_proc__generate_du_index_clauses([], _X, _Index, _Context, _N, [], !Info).
unify_proc__generate_du_index_clauses([Ctor | Ctors], X, Index, Context, N,
		[Clause | Clauses], !Info) :-
	Ctor = ctor(ExistQTVars, _Constraints, FunctorName, ArgTypes),
	list__length(ArgTypes, FunctorArity),
	FunctorConsId = cons(FunctorName, FunctorArity),
	unify_proc__make_fresh_vars(ArgTypes, ExistQTVars, ArgVars, !Info),
	create_atomic_unification(
		X, functor(FunctorConsId, no, ArgVars), Context, explicit, [],
		UnifyX_Goal),
	create_atomic_unification(
		Index, functor(int_const(N), no, []), Context, explicit, [],
		UnifyIndex_Goal),
	GoalList = [UnifyX_Goal, UnifyIndex_Goal],
	goal_info_init(GoalInfo0),
	goal_info_set_context(GoalInfo0, Context, GoalInfo),
	conj_list_to_goal(GoalList, GoalInfo, Goal),
	unify_proc__quantify_clause_body([X, Index], Goal, Context, Clause,
		!Info),
	unify_proc__generate_du_index_clauses(Ctors, X, Index, Context, N + 1,
		Clauses, !Info).

%-----------------------------------------------------------------------------%

:- pred unify_proc__generate_du_compare_clauses((type)::in,
	list(constructor)::in, prog_var::in, prog_var::in, prog_var::in,
	prog_context::in, list(clause)::out,
	unify_proc_info::in, unify_proc_info::out) is det.

unify_proc__generate_du_compare_clauses(Type, Ctors, Res, H1, H2,
		Context, Clauses, !Info) :-
	(
		Ctors = [],
		error("compare for type with no functors")
	;
		Ctors = [_ | _],
		unify_proc__info_get_module_info(ModuleInfo, !Info),
		module_info_globals(ModuleInfo, Globals),
		globals__lookup_int_option(Globals, compare_specialization,
			CompareSpec),
		list__length(Ctors, NumCtors),
		( NumCtors =< CompareSpec ->
			unify_proc__generate_du_quad_compare_clauses(
				Ctors, Res, H1, H2, Context, Clauses, !Info)
		;
			unify_proc__generate_du_linear_compare_clauses(Type,
				Ctors, Res, H1, H2, Context, Clauses, !Info)
		)
	).

%-----------------------------------------------------------------------------%

% For a du type, such as
%
%	:- type foo ---> f(a) ; g(a, b, c) ; h.
%
% the quadratic code we want to generate is
%
%	compare(Res, X, Y) :-
%		(
%			X = f(X1),
%			Y = f(Y1),
%			compare(R, X1, Y1)
%		;
%			X = f(_),
%			Y = g(_, _, _),
%			R = (<)
%		;
%			X = f(_),
%			Y = h,
%			R = (<)
%		;
%			X = g(_, _, _),
%			Y = f(_),
%			R = (>)
%		;
%			X = g(X1, X2, X3),
%			Y = g(Y1, Y2, Y3),
%			( compare(R1, X1, Y1), R1 \= (=) ->
%				R = R1
%			; compare(R2, X2, Y2), R2 \= (=) ->
%				R = R2
%			;
%				compare(R, X3, Y3)
%			)
%		;
%			X = g(_, _, _),
%			Y = h,
%			R = (<)
%		;
%			X = f(_),
%			Y = h,
%			R = (<)
%		;
%			X = g(_, _, _),
%			Y = h,
%			R = (<)
%		;
%			X = h,
%			Y = h,
%			R = (<)
%		).
%
% Note that in the clauses handling two copies of the same constant,
% we unify Y with the constant, not with X. This is required to get
% switch_detection and det_analysis to recognize the determinism of the
% predicate.

:- pred unify_proc__generate_du_quad_compare_clauses(list(constructor)::in,
	prog_var::in, prog_var::in, prog_var::in, prog_context::in,
	list(clause)::out, unify_proc_info::in, unify_proc_info::out) is det.

unify_proc__generate_du_quad_compare_clauses(Ctors, R, X, Y, Context,
		Clauses, !Info) :-
	unify_proc__generate_du_quad_compare_clauses_1(Ctors, Ctors, R, X, Y,
		Context, [], Cases, !Info),
	goal_info_init(GoalInfo0),
	goal_info_set_context(GoalInfo0, Context, GoalInfo),
	disj_list_to_goal(Cases, GoalInfo, Goal),
	HeadVars = [R, X, Y],
	unify_proc__quantify_clauses_body(HeadVars, Goal, Context, Clauses,
		!Info).

:- pred unify_proc__generate_du_quad_compare_clauses_1(
	list(constructor)::in, list(constructor)::in,
	prog_var::in, prog_var::in, prog_var::in, prog_context::in,
	list(hlds_goal)::in, list(hlds_goal)::out,
	unify_proc_info::in, unify_proc_info::out) is det.

unify_proc__generate_du_quad_compare_clauses_1([],
		_RightCtors, _R, _X, _Y, _Context, !Cases, !Info).
unify_proc__generate_du_quad_compare_clauses_1([LeftCtor | LeftCtors],
		RightCtors, R, X, Y, Context, !Cases, !Info) :-
	unify_proc__generate_du_quad_compare_clauses_2(LeftCtor, RightCtors,
		">", R, X, Y, Context, !Cases, !Info),
	unify_proc__generate_du_quad_compare_clauses_1(LeftCtors, RightCtors,
		R, X, Y, Context, !Cases, !Info).

:- pred unify_proc__generate_du_quad_compare_clauses_2(
	constructor::in, list(constructor)::in, string::in,
	prog_var::in, prog_var::in, prog_var::in, prog_context::in,
	list(hlds_goal)::in, list(hlds_goal)::out,
	unify_proc_info::in, unify_proc_info::out) is det.

unify_proc__generate_du_quad_compare_clauses_2(_LeftCtor,
		[], _Cmp, _R, _X, _Y, _Context, !Cases, !Info).
unify_proc__generate_du_quad_compare_clauses_2(LeftCtor,
		[RightCtor | RightCtors], Cmp0, R, X, Y, Context,
		!Cases, !Info) :-
	( LeftCtor = RightCtor ->
		unify_proc__generate_compare_case(LeftCtor, R, X, Y, Context,
			quad, Case, !Info),
		Cmp1 = "<"
	;
		unify_proc__generate_asymmetric_compare_case(LeftCtor,
			RightCtor, Cmp0, R, X, Y, Context, Case, !Info),
		Cmp1 = Cmp0
	),
	unify_proc__generate_du_quad_compare_clauses_2(LeftCtor, RightCtors,
		Cmp1, R, X, Y, Context, [Case | !.Cases], !:Cases, !Info).

%-----------------------------------------------------------------------------%

% For a du type, such as
%
%	:- type foo ---> f ; g(a) ; h(b, foo).
%
% the linear code we want to generate is
%
%	compare(Res, X, Y) :-
%		__Index__(X, X_Index),	% Call_X_Index
%		__Index__(Y, Y_Index),	% Call_Y_Index
%		( X_Index < Y_Index ->	% Call_Less_Than
%			Res = (<)	% Return_Less_Than
%		; X_Index > Y_Index ->	% Call_Greater_Than
%			Res = (>)	% Return_Greater_Than
%		;
%			% This disjunction is generated by
%			% unify_proc__generate_compare_cases, below.
%			(
%				X = f
%				R = (=)
%			;
%				X = g(X1),
%				Y = g(Y1),
%				compare(R, X1, Y1)
%			;
%				X = h(X1, X2),
%				Y = h(Y1, Y2),
%				( compare(R1, X1, Y1), R1 \= (=) ->
%					R = R1
%				;
%					compare(R, X2, Y2)
%				)
%			)
%		->
%			Res = R		% Return_R
%		;
%			compare_error 	% Abort
%		).
%
% Note that disjuncts covering constants do not test Y, since for constants
% X_Index = Y_Index implies X = Y.

:- pred unify_proc__generate_du_linear_compare_clauses((type)::in,
	list(constructor)::in, prog_var::in, prog_var::in, prog_var::in,
	prog_context::in, list(clause)::out,
	unify_proc_info::in, unify_proc_info::out) is det.

unify_proc__generate_du_linear_compare_clauses(Type, Ctors, Res, X, Y,
		Context, [Clause], !Info) :-
	unify_proc__generate_du_linear_compare_clauses_2(Type, Ctors, Res,
		X, Y, Context, Goal, !Info),
	HeadVars = [Res, X, Y],
	unify_proc__quantify_clause_body(HeadVars, Goal, Context, Clause,
		!Info).

:- pred unify_proc__generate_du_linear_compare_clauses_2((type)::in,
	list(constructor)::in, prog_var::in, prog_var::in, prog_var::in,
	prog_context::in, hlds_goal::out,
	unify_proc_info::in, unify_proc_info::out) is det.

unify_proc__generate_du_linear_compare_clauses_2(Type, Ctors, Res, X, Y,
		Context, Goal, !Info) :-
	IntType = int_type,
	unify_proc__info_new_var(IntType, X_Index, !Info),
	unify_proc__info_new_var(IntType, Y_Index, !Info),
	unify_proc__info_new_var(comparison_result_type, R, !Info),

	goal_info_init(GoalInfo0),
	goal_info_set_context(GoalInfo0, Context, GoalInfo),

	instmap_delta_from_assoc_list([X_Index - ground(shared, none)],
		X_InstmapDelta),
	unify_proc__build_specific_call(Type, index, [X, X_Index],
		X_InstmapDelta, det, Context, Call_X_Index, !Info),
	instmap_delta_from_assoc_list([Y_Index - ground(shared, none)],
		Y_InstmapDelta),
	unify_proc__build_specific_call(Type, index, [Y, Y_Index],
		Y_InstmapDelta, det, Context, Call_Y_Index, !Info),

	unify_proc__build_call("builtin_int_lt", [X_Index, Y_Index], Context,
		Call_Less_Than, !Info),
	unify_proc__build_call("builtin_int_gt", [X_Index, Y_Index], Context,
		Call_Greater_Than, !Info),

	create_atomic_unification(
		Res, functor(cons(unqualified("<"), 0), no, []),
			Context, explicit, [],
		Return_Less_Than),

	create_atomic_unification(
		Res, functor(cons(unqualified(">"), 0), no, []),
			Context, explicit, [],
		Return_Greater_Than),

	create_atomic_unification(Res, var(R), Context, explicit, [],
		Return_R),

	unify_proc__generate_compare_cases(Ctors, R, X, Y, Context, Cases,
		!Info),
	CasesGoal = disj(Cases) - GoalInfo,

	unify_proc__build_call("compare_error", [], Context, Abort, !Info),

	Goal = conj([
		Call_X_Index,
		Call_Y_Index,
		if_then_else([], Call_Less_Than, Return_Less_Than,
			if_then_else([], Call_Greater_Than, Return_Greater_Than,
				if_then_else([], CasesGoal, Return_R, Abort)
				- GoalInfo)
			- GoalInfo)
		- GoalInfo
	]) - GoalInfo.

% unify_proc__generate_compare_cases: for a type such as
%
%	:- type foo ---> f ; g(a) ; h(b, foo).
%
% we want to generate code
%
%	(
%		X = f,		% UnifyX_Goal
%		Y = X,		% UnifyY_Goal
%		R = (=)		% CompareArgs_Goal
%	;
%		X = g(X1),
%		Y = g(Y1),
%		compare(R, X1, Y1)
%	;
%		X = h(X1, X2),
%		Y = h(Y1, Y2),
%		( compare(R1, X1, Y1), R1 \= (=) ->
%			R = R1
%		;
%			compare(R, X2, Y2)
%		)
%	)
%
% Note that in the clauses for constants, we unify Y with X, not with
% the constant. This is to allow dupelim to eliminate all but one of
% the code fragments implementing such switch arms.

:- pred unify_proc__generate_compare_cases(list(constructor)::in, prog_var::in,
	prog_var::in, prog_var::in, prog_context::in, list(hlds_goal)::out,
	unify_proc_info::in, unify_proc_info::out) is det.

unify_proc__generate_compare_cases([], _R, _X, _Y, _Context, [], !Info).
unify_proc__generate_compare_cases([Ctor | Ctors], R, X, Y, Context,
		[Case | Cases], !Info) :-
	unify_proc__generate_compare_case(Ctor, R, X, Y, Context, linear,
		Case, !Info),
	unify_proc__generate_compare_cases(Ctors, R, X, Y, Context, Cases,
		!Info).

:- type linear_or_quad	--->	linear ; quad.

:- pred unify_proc__generate_compare_case(constructor::in,
	prog_var::in, prog_var::in, prog_var::in, prog_context::in,
	linear_or_quad::in, hlds_goal::out,
	unify_proc_info::in, unify_proc_info::out) is det.

unify_proc__generate_compare_case(Ctor, R, X, Y, Context, Kind, Case, !Info) :-
	Ctor = ctor(ExistQTVars, _Constraints, FunctorName, ArgTypes),
	list__length(ArgTypes, FunctorArity),
	FunctorConsId = cons(FunctorName, FunctorArity),
	(
		ArgTypes = [],
		create_atomic_unification(
			X, functor(FunctorConsId, no, []), Context,
			explicit, [], UnifyX_Goal),
		unify_proc__generate_return_equal(R, Context, EqualGoal),
		(
			Kind = linear,
			% The disjunct we are generating is executed only if
			% the index values of X and Y are the same, so if X is
			% bound to a constant, Y must also be bound to that
			% same constant.
			GoalList = [UnifyX_Goal, EqualGoal]
		;
			Kind = quad,
			create_atomic_unification(
				Y, functor(FunctorConsId, no, []), Context,
				explicit, [], UnifyY_Goal),
			GoalList = [UnifyX_Goal, UnifyY_Goal, EqualGoal]
		)
	;
		ArgTypes = [_ | _],
		unify_proc__make_fresh_vars(ArgTypes, ExistQTVars, Vars1,
			!Info),
		unify_proc__make_fresh_vars(ArgTypes, ExistQTVars, Vars2,
			!Info),
		create_atomic_unification(
			X, functor(FunctorConsId, no, Vars1), Context,
			explicit, [], UnifyX_Goal),
		create_atomic_unification(
			Y, functor(FunctorConsId, no, Vars2), Context,
			explicit, [], UnifyY_Goal),
		unify_proc__compare_args(ArgTypes, ExistQTVars, Vars1, Vars2,
			R, Context, CompareArgs_Goal, !Info),
		GoalList = [UnifyX_Goal, UnifyY_Goal, CompareArgs_Goal]
	),
	goal_info_init(GoalInfo0),
	goal_info_set_context(GoalInfo0, Context, GoalInfo),
	conj_list_to_goal(GoalList, GoalInfo, Case).

:- pred unify_proc__generate_asymmetric_compare_case(constructor::in,
	constructor::in, string::in, prog_var::in, prog_var::in, prog_var::in,
	prog_context::in, hlds_goal::out,
	unify_proc_info::in, unify_proc_info::out) is det.

unify_proc__generate_asymmetric_compare_case(Ctor1, Ctor2, CompareOp, R, X, Y,
		Context, Case, !Info) :-
	Ctor1 = ctor(ExistQTVars1, _Constraints1, FunctorName1, ArgTypes1),
	Ctor2 = ctor(ExistQTVars2, _Constraints2, FunctorName2, ArgTypes2),
	list__length(ArgTypes1, FunctorArity1),
	list__length(ArgTypes2, FunctorArity2),
	FunctorConsId1 = cons(FunctorName1, FunctorArity1),
	FunctorConsId2 = cons(FunctorName2, FunctorArity2),
	unify_proc__make_fresh_vars(ArgTypes1, ExistQTVars1, Vars1, !Info),
	unify_proc__make_fresh_vars(ArgTypes2, ExistQTVars2, Vars2, !Info),
	create_atomic_unification(
		X, functor(FunctorConsId1, no, Vars1), Context, explicit, [],
		UnifyX_Goal),
	create_atomic_unification(
		Y, functor(FunctorConsId2, no, Vars2), Context, explicit, [],
		UnifyY_Goal),
	create_atomic_unification(
		R, functor(cons(unqualified(CompareOp), 0), no, []),
			Context, explicit, [],
		ReturnResult),
	GoalList = [UnifyX_Goal, UnifyY_Goal, ReturnResult],
	goal_info_init(GoalInfo0),
	goal_info_set_context(GoalInfo0, Context, GoalInfo),
	conj_list_to_goal(GoalList, GoalInfo, Case).

% unify_proc__compare_args: for a constructor such as
%
%	h(list(int), foo, string)
%
% we want to generate code
%
%	(
%		compare(R1, X1, Y1),	% Do_Comparison
%		R1 \= (=)		% Check_Not_Equal
%	->
%		R = R1			% Return_R1
%	;
%		compare(R2, X2, Y2),
%		R2 \= (=)
%	->
%		R = R2
%	;
%		compare(R, X3, Y3)	% Return_Comparison
%	)
%
% For a constructor with no arguments, we want to generate code
%
%	R = (=)		% Return_Equal

:- pred unify_proc__compare_args(list(constructor_arg)::in, existq_tvars::in,
	list(prog_var)::in, list(prog_var)::in, prog_var::in, prog_context::in,
	hlds_goal::out, unify_proc_info::in, unify_proc_info::out) is det.

unify_proc__compare_args(ArgTypes, ExistQTVars, Xs, Ys, R, Context, Goal,
		!Info) :-
	(
		unify_proc__compare_args_2(ArgTypes, ExistQTVars, Xs, Ys, R,
			Context, Goal0, !Info)
	->
		Goal = Goal0
	;
		error("unify_proc__compare_args: length mismatch")
	).

:- pred unify_proc__compare_args_2(list(constructor_arg)::in, existq_tvars::in,
	list(prog_var)::in, list(prog_var)::in, prog_var::in, prog_context::in,
	hlds_goal::out, unify_proc_info::in, unify_proc_info::out) is semidet.

unify_proc__compare_args_2([], _, [], [], R, Context, Return_Equal, !Info) :-
	unify_proc__generate_return_equal(R, Context, Return_Equal).
unify_proc__compare_args_2([_Name - Type | ArgTypes], ExistQTVars,
		[X | Xs], [Y | Ys], R, Context, Goal, !Info) :-
	goal_info_init(GoalInfo0),
	goal_info_set_context(GoalInfo0, Context, GoalInfo),
	%
	% When comparing existentially typed arguments, the arguments may
	% have different types; in that case, rather than just comparing them,
	% which would be a type error, we call `typed_compare', which is a
	% builtin that first compares their types and then compares
	% their values.
	%
	(
		list__member(ExistQTVar, ExistQTVars),
		term__contains_var(Type, ExistQTVar)
	->
		ComparePred = "typed_compare"
	;
		ComparePred = "compare"
	),
	(
		Xs = [],
		Ys = []
	->
		unify_proc__build_call(ComparePred, [R, X, Y], Context, Goal,
			!Info)
	;
		unify_proc__info_new_var(comparison_result_type, R1, !Info),

		unify_proc__build_call(ComparePred, [R1, X, Y], Context,
			Do_Comparison, !Info),

		create_atomic_unification(
			R1, functor(cons(unqualified("="), 0), no, []),
			Context, explicit, [], Check_Equal),
		Check_Not_Equal = not(Check_Equal) - GoalInfo,

		create_atomic_unification(
			R, var(R1), Context, explicit, [], Return_R1),
		Condition = conj([Do_Comparison, Check_Not_Equal])
			- GoalInfo,
		Goal = if_then_else([], Condition, Return_R1, ElseCase)
			- GoalInfo,
		unify_proc__compare_args_2(ArgTypes, ExistQTVars, Xs, Ys, R,
			Context, ElseCase, !Info)
	).

:- pred unify_proc__generate_return_equal(prog_var::in, prog_context::in,
	hlds_goal::out) is det.

unify_proc__generate_return_equal(ResultVar, Context, Return_Equal) :-
	create_atomic_unification(
		ResultVar, functor(cons(unqualified("="), 0), no, []),
		Context, explicit, [], Return_Equal).

%-----------------------------------------------------------------------------%

:- pred unify_proc__build_call(string::in, list(prog_var)::in,
	prog_context::in, hlds_goal::out,
	unify_proc_info::in, unify_proc_info::out) is det.

unify_proc__build_call(Name, ArgVars, Context, Goal, !Info) :-
	unify_proc__info_get_module_info(ModuleInfo, !Info),
	list__length(ArgVars, Arity),
	%
	% We assume that the special preds compare/3, index/2, and unify/2
	% are the only public builtins called by code generated
	% by this module.
	%
	( special_pred_name_arity(_, Name, Arity) ->
		MercuryBuiltin = mercury_public_builtin_module
	;
		MercuryBuiltin = mercury_private_builtin_module
	),
	goal_util__generate_simple_call(MercuryBuiltin, Name, predicate,
		mode_no(0), erroneous, ArgVars, [], [], ModuleInfo,
		Context, Goal).

:- pred unify_proc__build_specific_call((type)::in, special_pred_id::in,
	list(prog_var)::in, instmap_delta::in, determinism::in,
	prog_context::in, hlds_goal::out,
	unify_proc_info::in, unify_proc_info::out) is det.

unify_proc__build_specific_call(Type, SpecialPredId, ArgVars, InstmapDelta,
		Detism, Context, Goal, !Info) :-
	unify_proc__info_get_module_info(ModuleInfo, !Info),
	(
		polymorphism__get_special_proc(Type, SpecialPredId, ModuleInfo,
			PredName, PredId, ProcId)
	->
		GoalExpr = call(PredId, ProcId, ArgVars, not_builtin, no,
			PredName),
		set__list_to_set(ArgVars, NonLocals),
		goal_info_init(NonLocals, InstmapDelta,
			Detism, pure, GoalInfo0),
		goal_info_set_context(GoalInfo0, Context, GoalInfo),
		Goal = GoalExpr - GoalInfo
	;
			% unify_proc__build_specific_call is only ever used
			% to build calls to special preds for a type in the
			% bodies of other special preds for that same type.
			% If the special preds for a type are built in the
			% right order (index before compare), the lookup
			% should never fail.
		error("unify_proc__build_specific_call: lookup failed")
	).

%-----------------------------------------------------------------------------%

:- pred unify_proc__make_fresh_named_var_from_type((type)::in,
	string::in, int::in, prog_var::out,
	unify_proc_info::in, unify_proc_info::out) is det.

unify_proc__make_fresh_named_var_from_type(Type, BaseName, Num, Var, !Info) :-
	string__int_to_string(Num, NumStr),
	string__append(BaseName, NumStr, Name),
	unify_proc__info_new_named_var(Type, Name, Var, !Info).

:- pred unify_proc__make_fresh_named_vars_from_types(list(type)::in,
	string::in, int::in, list(prog_var)::out,
	unify_proc_info::in, unify_proc_info::out) is det.

unify_proc__make_fresh_named_vars_from_types([], _, _, [], !Info).
unify_proc__make_fresh_named_vars_from_types([Type | Types], BaseName, Num,
		[Var | Vars], !Info) :-
	unify_proc__make_fresh_named_var_from_type(Type, BaseName, Num, Var,
		!Info),
	unify_proc__make_fresh_named_vars_from_types(Types, BaseName, Num + 1,
		Vars, !Info).

:- pred unify_proc__make_fresh_vars_from_types(list(type)::in,
	list(prog_var)::out, unify_proc_info::in, unify_proc_info::out) is det.

unify_proc__make_fresh_vars_from_types([], [], !Info).
unify_proc__make_fresh_vars_from_types([Type | Types], [Var | Vars], !Info) :-
	unify_proc__info_new_var(Type, Var, !Info),
	unify_proc__make_fresh_vars_from_types(Types, Vars, !Info).

:- pred unify_proc__make_fresh_vars(list(constructor_arg)::in,
	existq_tvars::in, list(prog_var)::out,
	unify_proc_info::in, unify_proc_info::out) is det.

unify_proc__make_fresh_vars(CtorArgs, ExistQTVars, Vars, !Info) :-
	( ExistQTVars = [] ->
		assoc_list__values(CtorArgs, ArgTypes),
		unify_proc__make_fresh_vars_from_types(ArgTypes, Vars, !Info)
	;
		%
		% If there are existential types involved, then it's too
		% hard to get the types right here (it would require
		% allocating new type variables) -- instead, typecheck.m
		% will typecheck the clause to figure out the correct types.
		% So we just allocate the variables and leave it up to
		% typecheck.m to infer their types.
		%
		unify_proc__info_get_varset(VarSet0, !Info),
		list__length(CtorArgs, NumVars),
		varset__new_vars(VarSet0, NumVars, Vars, VarSet),
		unify_proc__info_set_varset(VarSet, !Info)
	).

:- pred unify_proc__unify_var_lists(list(constructor_arg)::in,
	existq_tvars::in, list(prog_var)::in, list(prog_var)::in,
	list(hlds_goal)::out, unify_proc_info::in, unify_proc_info::out)
	is det.

unify_proc__unify_var_lists(ArgTypes, ExistQVars, Vars1, Vars2, Goal, !Info) :-
	(
		unify_proc__unify_var_lists_2(ArgTypes, ExistQVars,
			Vars1, Vars2, Goal0, !Info)
	->
		Goal = Goal0
	;
		error("unify_proc__unify_var_lists: length mismatch")
	).

:- pred unify_proc__unify_var_lists_2(list(constructor_arg)::in,
	existq_tvars::in, list(prog_var)::in, list(prog_var)::in,
	list(hlds_goal)::out, unify_proc_info::in, unify_proc_info::out)
	is semidet.

unify_proc__unify_var_lists_2([], _, [], [], [], !Info).
unify_proc__unify_var_lists_2([_Name - Type | ArgTypes], ExistQTVars,
		[Var1 | Vars1], [Var2 | Vars2], [Goal | Goals], !Info) :-
	term__context_init(Context),
	%
	% When unifying existentially typed arguments, the arguments may
	% have different types; in that case, rather than just unifying them,
	% which would be a type error, we call `typed_unify', which is a
	% builtin that first checks that their types are equal and then
	% unifies the values.
	%
	(
		list__member(ExistQTVar, ExistQTVars),
		term__contains_var(Type, ExistQTVar)
	->
		unify_proc__build_call("typed_unify", [Var1, Var2], Context,
			Goal, !Info)
	;
		create_atomic_unification(Var1, var(Var2), Context, explicit,
			[], Goal)
	),
	unify_proc__unify_var_lists_2(ArgTypes, ExistQTVars, Vars1, Vars2,
		Goals, !Info).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

% It's a pity that we don't have nested modules. XXX now we do

% :- begin_module unify_proc_info.
% :- interface.

:- type unify_proc_info.

:- pred unify_proc__info_init(module_info::in, unify_proc_info::out) is det.
:- pred unify_proc__info_new_var((type)::in, prog_var::out,
	unify_proc_info::in, unify_proc_info::out) is det.
:- pred unify_proc__info_new_named_var((type)::in, string::in, prog_var::out,
	unify_proc_info::in, unify_proc_info::out) is det.
:- pred unify_proc__info_extract(unify_proc_info::in,
	prog_varset::out, vartypes::out) is det.
:- pred unify_proc__info_get_varset(prog_varset::out,
	unify_proc_info::in, unify_proc_info::out) is det.
:- pred unify_proc__info_set_varset(prog_varset::in,
	unify_proc_info::in, unify_proc_info::out) is det.
:- pred unify_proc__info_get_types(vartypes::out,
	unify_proc_info::in, unify_proc_info::out) is det.
:- pred unify_proc__info_set_types(vartypes::in,
	unify_proc_info::in, unify_proc_info::out) is det.
:- pred unify_proc__info_get_rtti_varmaps(rtti_varmaps::out,
	unify_proc_info::in, unify_proc_info::out) is det.
:- pred unify_proc__info_get_module_info(module_info::out,
	unify_proc_info::in, unify_proc_info::out) is det.

%-----------------------------------------------------------------------------%

% :- implementation

:- type unify_proc_info
	--->	unify_proc_info(
			varset			::	prog_varset,
			vartypes		::	vartypes,
			rtti_varmaps		::	rtti_varmaps,
			module_info		::	module_info
		).

unify_proc__info_init(ModuleInfo, UPI) :-
	varset__init(VarSet),
	map__init(Types),
	rtti_varmaps_init(RttiVarMaps),
	UPI = unify_proc_info(VarSet, Types, RttiVarMaps, ModuleInfo).

unify_proc__info_new_var(Type, Var, UPI,
		(UPI^varset := VarSet) ^vartypes := Types) :-
	varset__new_var(UPI^varset, Var, VarSet),
	map__det_insert(UPI^vartypes, Var, Type, Types).

unify_proc__info_new_named_var(Type, Name, Var, UPI,
		(UPI^varset := VarSet) ^vartypes := Types) :-
	varset__new_named_var(UPI^varset, Name, Var, VarSet),
	map__det_insert(UPI^vartypes, Var, Type, Types).

unify_proc__info_extract(UPI, UPI^varset, UPI^vartypes).

unify_proc__info_get_varset(UPI^varset, UPI, UPI).
unify_proc__info_get_types(UPI^vartypes, UPI, UPI).
unify_proc__info_get_rtti_varmaps(UPI^rtti_varmaps, UPI, UPI).
unify_proc__info_get_module_info(UPI^module_info, UPI, UPI).

unify_proc__info_set_varset(VarSet, UPI, UPI^varset := VarSet).
unify_proc__info_set_types(Types, UPI, UPI^vartypes := Types).

%-----------------------------------------------------------------------------%

:- func this_file = string.
this_file = "unify_proc.m".

%-----------------------------------------------------------------------------%
