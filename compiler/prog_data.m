%-----------------------------------------------------------------------------%
% Copyright (C) 1996-1999 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%
%
% File: prog_data.m.
% Main author: fjh.
%
% This module defines a data structure for representing Mercury programs.
%
% This data structure specifies basically the same information as is
% contained in the source code, but in a parse tree rather than a flat file.
% Simplifications are done only by make_hlds.m, which transforms
% the parse tree which we built here into the HLDS.

:- module prog_data.

:- interface.

:- import_module hlds_data, hlds_pred, (inst), purity, term_util.
:- import_module varset, term.
:- import_module list, map, term, std_util.

%-----------------------------------------------------------------------------%

	% This is how programs (and parse errors) are represented.

:- type message_list	==	list(pair(string, term)).
				% the error/warning message, and the
				% term to which it relates

:- type compilation_unit		
	--->	module(
			module_name,
			item_list
		).

:- type item_list	==	list(item_and_context).

:- type item_and_context ==	pair(item, prog_context).

:- type item		
	--->	pred_clause(prog_varset, sym_name, list(prog_term), goal)
		%      VarNames, PredName, HeadArgs, ClauseBody

	;	func_clause(prog_varset, sym_name, list(prog_term),
			prog_term, goal)
		%      VarNames, PredName, HeadArgs, Result, ClauseBody

	; 	type_defn(tvarset, type_defn, condition)
	; 	inst_defn(inst_varset, inst_defn, condition)
	; 	mode_defn(inst_varset, mode_defn, condition)
	; 	module_defn(prog_varset, module_defn)

	; 	pred(tvarset, inst_varset, existq_tvars, sym_name,
			types_and_modes, maybe(determinism), condition, purity,
			class_constraints)
		%       TypeVarNames, InstVarNames,
		%       ExistentiallyQuantifiedTypeVars, PredName,
		%       ArgTypes, Deterministicness, Cond, Purity,
		%       TypeClassContext

	; 	func(tvarset, inst_varset, existq_tvars, sym_name,
			types_and_modes, type_and_mode, maybe(determinism),
			condition, purity, class_constraints)
		%       TypeVarNames, InstVarNames,
		%       ExistentiallyQuantifiedTypeVars, PredName,
		%       ArgTypes, ReturnType, Deterministicness, Cond, 
		%       Purity, TypeClassContext

	; 	pred_mode(inst_varset, sym_name, argument_modes,
			maybe(determinism), condition)
		%       VarNames, PredName, ArgModes, Deterministicness,
		%       Cond

	; 	func_mode(inst_varset, sym_name, argument_modes, mode,
			maybe(determinism), condition)
		%       VarNames, PredName, ArgModes, ReturnValueMode,
		%       Deterministicness, Cond

	;	pragma(pragma_type)

	;	typeclass(list(class_constraint), class_name, list(tvar),
			class_interface, tvarset)
		%	Constraints, ClassName, ClassParams, 
		%	ClassMethods, VarNames

	;	instance(list(class_constraint), class_name, list(type),
			instance_interface, tvarset)
		%	DerivingClass, ClassName, Types, 
		%	MethodInstances, VarNames

	;	nothing.
		% used for items that should be ignored (currently only
		% NU-Prolog `when' declarations, which are silently ignored
		% for backwards compatibility).

:- type type_and_mode	
	--->	type_only(type)
	;	type_and_mode(type, mode).

:- type types_and_modes
	--->	types_and_modes(inst_table, list(type_and_mode)).

:- type pragma_type 
	--->	c_header_code(string)

	;	c_code(string)

	;	c_code(pragma_c_code_attributes, sym_name, pred_or_func,
			list(pragma_var), prog_varset, pragma_c_code_impl)
			% Set of C code attributes, eg.:
			%	whether or not the C code may call Mercury,
			%	whether or not the C code is thread-safe
			% PredName, Predicate or Function, Vars/Mode, 
			% VarNames, C Code Implementation Info

	;	inline(sym_name, arity)
			% Predname, Arity

	;	no_inline(sym_name, arity)
			% Predname, Arity

	;	obsolete(sym_name, arity)
			% Predname, Arity

	;	export(sym_name, pred_or_func, argument_modes,
			string)
			% Predname, Predicate/function, Modes,
			% C function name.

	;	import(sym_name, pred_or_func, argument_modes,
			pragma_c_code_attributes, string)
			% Predname, Predicate/function, Modes,
			% Set of C code attributes, eg.:
			%	whether or not the C code may call Mercury,
			%	whether or not the C code is thread-safe
			% C function name.

	;	source_file(string)
			% Source file name.

	;	unused_args(pred_or_func, sym_name, int,
			proc_id, list(int))
			% PredName, Arity, Mode, Optimized pred name,
			% 	Removed arguments.
			% Used for inter-module unused argument
			% removal, should only appear in .opt files.

	;	fact_table(sym_name, arity, string)
			% Predname, Arity, Fact file name.

	;	tabled(eval_method, sym_name, int, maybe(pred_or_func), 
				maybe(argument_modes))
			% Tabling type, Predname, Arity, PredOrFunc?, Mode?
	
	;	promise_pure(sym_name, arity)
			% Predname, Arity

	;	termination_info(pred_or_func, sym_name, argument_modes,
			maybe(arg_size_info), maybe(termination_info))
			% the argument_modes is the declared argmodes of the
			% procedure, unless there are no declared argmodes,
			% in which case the inferred argmodes are used.
			% This pragma is used to define information about a
			% predicates termination properties.  It is most
			% useful where the compiler has insufficient
			% information to be able to analyse the predicate.
			% This includes c_code, and imported predicates.
			% termination_info pragmas are used in opt and
			% trans_opt files.

	;	terminates(sym_name, arity)
			% Predname, Arity

	;	does_not_terminate(sym_name, arity)
			% Predname, Arity

	;	check_termination(sym_name, arity).
			% Predname, Arity

	% This type holds information about the implementation details
	% of procedures defined via `pragma c_code'.

	% All the strings in this type may be accompanied by the context
	% of their appearance in the source code. These contexts are
	% used to tell the C compiler where the included C code comes from,
	% to allow it to generate error messages that refer to the original
	% appearance of the code in the Mercury program.
	% The context is missing if the C code was constructed by the compiler.
:- type pragma_c_code_impl
	--->	ordinary(		% This is a C definition of a model_det
					% or model_semi procedure. (We also
					% allow model_non, until everyone has
					% had time to adapt to the new way
					% of handling model_non pragmas.)
			string,		% The C code of the procedure.
			maybe(prog_context)
		)
	;	nondet(			% This is a C definition of a model_non
					% procedure.
			string,
			maybe(prog_context),
					% The info saved for the time when
					% backtracking reenters this procedure
					% is stored in a C struct. This arg
					% contains the field declarations.

			string,
			maybe(prog_context),
					% Gives the code to be executed when
					% the procedure is called for the first 
					% time. This code may access the input
					% variables.

			string,	
			maybe(prog_context),
					% Gives the code to be executed when
					% control backtracks into the procedure.
					% This code may not access the input
					% variables.

			pragma_shared_code_treatment,
					% How should the shared code be
					% treated during code generation.
			string,	
			maybe(prog_context)
					% Shared code that is executed after
					% both the previous code fragments.
					% May not access the input variables.
		).

	% The use of this type is explained in the comment at the top of
	% pragma_c_gen.m.
:- type pragma_shared_code_treatment
	--->	duplicate
	;	share
	;	automatic.

	% A class constraint represents a constraint that a given
	% list of types is a member of the specified type class.
	% It is an invariant of this data structure that
	% the types in a class constraint do not contain any
	% information in their prog_context fields.
	% This invariant is needed to ensure that we can do
	% unifications, map__lookups, etc., and get the
	% expected semantics.
	% Any code that creates new class constraints must
	% ensure that this invariant is preserved,
	% probably by using strip_term_contexts/2 in type_util.m.
:- type class_constraint
	---> constraint(class_name, list(type)).

:- type class_constraints
	---> constraints(
		list(class_constraint),	% ordinary (universally quantified)
		list(class_constraint)	% existentially quantified constraints
	).

:- type class_name == sym_name.

:- type class_interface  == list(class_method).	

:- type class_method
	--->	pred(tvarset, inst_varset, existq_tvars, sym_name,
			types_and_modes, maybe(determinism), condition,
			class_constraints, term__context)
		%       TypeVarNames, InstVarNames,
		%	ExistentiallyQuantifiedTypeVars,
		%	PredName, ArgTypes, Determinism, Cond
		%	ClassContext, Context

	; 	func(tvarset, inst_varset, existq_tvars, sym_name,
			types_and_modes, type_and_mode,
			maybe(determinism), condition,
			class_constraints, prog_context)
		%       TypeVarNames, InstVarNames,
		%	ExistentiallyQuantfiedTypeVars,
		%	PredName, ArgTypes, ReturnType,
		%	Determinism, Cond
		%	ClassContext, Context

	; 	pred_mode(inst_varset, sym_name, argument_modes,
			maybe(determinism), condition,
			prog_context)
		%       InstVarNames, PredName, ArgModes,
		%	Determinism, Cond
		%	Context

	; 	func_mode(inst_varset, sym_name, argument_modes, mode,
			maybe(determinism), condition,
			prog_context)
		%       InstVarNames, PredName, ArgModes,
		%	ReturnValueMode,
		%	Determinism, Cond
		%	Context
	.

:- type instance_method	
	--->	func_instance(sym_name, sym_name, arity, prog_context)
				% Method, Instance, Arity, 
				% Line number of declaration
	;	pred_instance(sym_name, sym_name, arity, prog_context)
				% Method, Instance, Arity, 
				% Line number of declaration
	.

:- type instance_interface ==	list(instance_method).

		% an abstract type for representing a set of
		% `pragma_c_code_attribute's.
:- type pragma_c_code_attributes.

:- pred default_attributes(pragma_c_code_attributes).
:- mode default_attributes(out) is det.

:- pred may_call_mercury(pragma_c_code_attributes, may_call_mercury).
:- mode may_call_mercury(in, out) is det.

:- pred set_may_call_mercury(pragma_c_code_attributes, may_call_mercury,
		pragma_c_code_attributes).
:- mode set_may_call_mercury(in, in, out) is det.

:- pred thread_safe(pragma_c_code_attributes, thread_safe).
:- mode thread_safe(in, out) is det.

:- pred set_thread_safe(pragma_c_code_attributes, thread_safe,
		pragma_c_code_attributes).
:- mode set_thread_safe(in, in, out) is det.

	% For pragma c_code, there are two different calling conventions,
	% one for C code that may recursively call Mercury code, and another
	% more efficient one for the case when we know that the C code will
	% not recursively invoke Mercury code.
:- type may_call_mercury
	--->	may_call_mercury
	;	will_not_call_mercury.

	% If thread_safe execution is enabled, then we need to put a mutex
	% around the C code for each `pragma c_code' declaration, unless
	% it's declared to be thread_safe.
:- type thread_safe
	--->	not_thread_safe
	;	thread_safe.

:- type pragma_var    
	--->	pragma_var(prog_var, string, mode).
	  	% variable, name, mode
		% we explicitly store the name because we need the real
		% name in code_gen

%-----------------------------------------------------------------------------%

	% Here's how clauses and goals are represented.
	% a => b --> implies(a, b)
	% a <= b --> implies(b, a) [just flips the goals around!]
	% a <=> b --> equivalent(a, b)

% clause/4 defined above

:- type goal		==	pair(goal_expr, prog_context).

:- type goal_expr	

	% conjunctions
	--->	(goal , goal)	% (non-empty) conjunction
	;	true		% empty conjunction
	;	{goal & goal}	% parallel conjunction
				% (The curly braces just quote the '&'/2.)

	% disjunctions
	;	{goal ; goal}	% (non-empty) disjunction
				% (The curly braces just quote the ';'/2.)
	;	fail		% empty disjunction

	% quantifiers
	;	{ some(prog_vars, goal) }
				% existential quantification
				% (The curly braces just quote the 'some'/2.)
	;	all(prog_vars, goal)	% universal quantification

	% implications
	;	implies(goal, goal)	% A => B
	;	equivalent(goal, goal)	% A <=> B

	% negation and if-then-else
	;	not(goal)
	;	if_then(prog_vars, goal, goal)
	;	if_then_else(prog_vars, goal, goal, goal)

	% atomic goals
	;	call(sym_name, list(prog_term), purity)
	;	unify(prog_term, prog_term).


	% These type equivalences are for the type of program variables
	% and associated structures.

:- type prog_var_type	--->	prog_var_type.
:- type prog_var	==	var(prog_var_type).
:- type prog_varset	==	varset(prog_var_type).
:- type prog_substitution ==	substitution(prog_var_type).
:- type prog_term	==	term(prog_var_type).
:- type prog_vars	==	list(prog_var).

	% A prog_context is just a term__context.

:- type prog_context	==	term__context.

:- type goals		==	list(goal).

%-----------------------------------------------------------------------------%

	% This is how types are represented.

			% one day we might allow types to take
			% value parameters as well as type parameters.

% type_defn/3 define above

:- type type_defn	
	--->	du_type(sym_name, list(type_param), list(constructor),
			maybe(equality_pred)
		)
	;	uu_type(sym_name, list(type_param), list(type))
	;	eqv_type(sym_name, list(type_param), type)
	;	abstract_type(sym_name, list(type_param)).

:- type constructor	
	--->	ctor(
			existq_tvars,
			list(class_constraint),	% existential constraints
			sym_name,
			list(constructor_arg)
		).

:- type constructor_arg	==	pair(string, type).

	% An equality_pred specifies the name of a user-defined predicate
	% used for equality on a type.  See the chapter on them in the
	% Mercury Language Reference Manual.
:- type equality_pred	==	sym_name.

	% probably type parameters should be variables not terms.
:- type type_param	==	term(tvar_type).

	% Module qualified types are represented as ':'/2 terms.
	% Use type_util:type_to_type_id to convert a type to a qualified
	% type_id and a list of arguments.
	% type_util:construct_type to construct a type from a type_id 
	% and a list of arguments.
:- type (type)		==	term(tvar_type).
:- type type_term	==	term(tvar_type).

:- type tvar_type	--->	type_var.
:- type tvar		==	var(tvar_type).
					% used for type variables
:- type tvarset		==	varset(tvar_type).
					% used for sets of type variables
:- type tsubst		==	map(tvar, type). % used for type substitutions

	% existq_tvars is used to record the set of type variables which are
	% existentially quantified
:- type existq_tvars	==	list(tvar).

	% Types may have arbitrary assertions associated with them
	% (eg. you can define a type which represents sorted lists).
	% Similarly, pred declarations can have assertions attached.
	% The compiler will ignore these assertions - they are intended
	% to be used by other tools, such as the debugger.

:- type condition	
	--->	true
	;	where(term).

%-----------------------------------------------------------------------------%

	% This is how instantiatednesses and modes are represented.
	% Note that while we use the normal term data structure to represent 
	% type terms (see above), we need a separate data structure for inst 
	% terms.

:- type inst_var_type	--->	inst_var_type.
:- type inst_var	==	var(inst_var_type).
:- type inst_term	==	term(inst_var_type).
:- type inst_varset	==	varset(inst_var_type).

% inst_defn/3 defined above

:- type inst_defn	
	--->	eqv_inst(sym_name, list(inst_param), inst)
	;	abstract_inst(sym_name, list(inst_param)).

	% probably inst parameters should be variables not terms
:- type inst_param	==	inst_term.

	% An `inst_name' is used as a key for the inst_table.
	% It is either a user-defined inst `user_inst(Name, Args)',
	% or some sort of compiler-generated inst, whose name
	% is a representation of it's meaning.
	%
	% For example, `merge_inst(InstA, InstB)' is the name used for the
	% inst that results from merging InstA and InstB using `merge_inst'.
	% Similarly `unify_inst(IsLive, InstA, InstB, IsReal)' is
	% the name for the inst that results from a call to
	% `abstractly_unify_inst(IsLive, InstA, InstB, IsReal)'.
	% And `ground_inst' and `any_inst' are insts that result
	% from unifying an inst with `ground' or `any', respectively.
	% `typed_inst' is an inst with added type information.
	% `typed_ground(Uniq, Type)' a equivalent to
	% `typed_inst(ground(Uniq, no), Type)'.
	% Note that `typed_ground' is a special case of `typed_inst',
	% and `ground_inst' and `any_inst' are special cases of `unify_inst'.
	% The reason for having the special cases is efficiency.
	
:- type inst_name	
	--->	user_inst(sym_name, list(inst))
	;	merge_inst(inst, inst)
	;	unify_inst(is_live, inst, inst, unify_is_real)
	;	ground_inst(inst_name, is_live, uniqueness, unify_is_real)
	;	any_inst(inst_name, is_live, uniqueness, unify_is_real)
	;	shared_inst(inst_name)
	;	mostly_uniq_inst(inst_name)
	;	typed_ground(uniqueness, type)
	;	typed_inst(type, inst_name).

	% Note: `is_live' records liveness in the sense used by
	% mode analysis.  This is not the same thing as the notion of liveness
	% used by code generation.  See compiler/notes/glossary.html.
:- type is_live		--->	live ; dead.

	% Unifications of insts fall into two categories, "real" and "fake".
	% The "real" inst unifications correspond to real unifications,
	% and are not allowed to unify with `clobbered' insts (unless
	% the unification would be `det').
	% Any inst unification which is associated with some code that
	% will actually examine the contents of the variables in question
	% must be "real".  Inst unifications that are not associated with
	% some real code that examines the variables' values are "fake".
	% "Fake" inst unifications are used for procedure calls in implied
	% modes, where the final inst of the var must be computed by
	% unifying its initial inst with the procedure's final inst,
	% so that if you pass a ground var to a procedure whose mode
	% is `free -> list_skeleton', the result is ground, not list_skeleton.
	% But these fake unifications must be allowed to unify with `clobbered'
	% insts. Hence we pass down a flag to `abstractly_unify_inst' which
	% specifies whether or not to allow unifications with clobbered values.

:- type unify_is_real
	--->	real_unify
	;	fake_unify.

% mode_defn/3 defined above

:- type mode_defn	
	--->	eqv_mode(sym_name, list(inst_param), mode).

:- type (mode)		
	--->	((inst) -> (inst))
	;	user_defined_mode(sym_name, list(inst)).

% mode/4 defined above

:- type argument_modes	--->	argument_modes(inst_table, list(mode)).

%-----------------------------------------------------------------------------%

	% This is how module-system declarations (such as imports
	% and exports) are represented.

:- type module_defn	
	--->	module(module_name)
	;	end_module(module_name)

	;	interface
	;	implementation

	;	private_interface
		% This is used internally by the compiler,
		% to identify items which originally
		% came from an implementation section
		% for a module that contains sub-modules;
		% such items need to be exported to the
		% sub-modules.

	;	imported
		% This is used internally by the compiler,
		% to identify declarations which originally
		% came from some other module imported with 
		% a `:- import_module' declaration.
	;	used
		% This is used internally by the compiler,
		% to identify declarations which originally
		% came from some other module and for which
		% all uses must be module qualified. This
		% applies to items from modules imported using
		% `:- use_module', and items from `.opt'
		% and `.int2' files.
	;	opt_imported
		% This is used internally by the compiler,
		% to identify items which originally
		% came from a .opt file.

	;	external(sym_name_specifier)

	;	export(sym_list)
	;	import(sym_list)
	;	use(sym_list)

	;	include_module(list(module_name)).

:- type sym_list	
	--->	sym(list(sym_specifier))
	;	pred(list(pred_specifier))
	;	func(list(func_specifier))
	;	cons(list(cons_specifier))
	;	op(list(op_specifier))
	;	adt(list(adt_specifier))
	;	type(list(type_specifier))
	;	module(list(module_specifier)).

:- type sym_specifier	
	--->	sym(sym_name_specifier)
	;	typed_sym(typed_cons_specifier)
	;	pred(pred_specifier)
	;	func(func_specifier)
	;	cons(cons_specifier)
	;	op(op_specifier)
	;	adt(adt_specifier)
	;	type(type_specifier)
	;	module(module_specifier).
:- type pred_specifier	
	--->	sym(sym_name_specifier)
	;	name_args(sym_name, list(type)).
:- type func_specifier	==	cons_specifier.
:- type cons_specifier	
	--->	sym(sym_name_specifier)
	;	typed(typed_cons_specifier).
:- type typed_cons_specifier 
	--->	name_args(sym_name, list(type))
	;	name_res(sym_name_specifier, type)
	;	name_args_res(sym_name, list(type), type).
:- type adt_specifier	==	sym_name_specifier.
:- type type_specifier	==	sym_name_specifier.
:- type op_specifier	
	--->	sym(sym_name_specifier)
	% operator fixity specifiers not yet implemented
	;	fixity(sym_name_specifier, fixity).
:- type fixity		
	--->	infix 
	; 	prefix 
	; 	postfix 
	; 	binary_prefix 
	; 	binary_postfix.
:- type sym_name_specifier 
	--->	name(sym_name)
	;	name_arity(sym_name, arity).
:- type sym_name 	
	--->	unqualified(string)
	;	qualified(module_specifier, string).

:- type module_specifier ==	sym_name.
:- type module_name 	== 	sym_name.
:- type arity		==	int.

	% Describes whether an item can be used without an 
	% explicit module qualifier.
:- type need_qualifier
	--->	must_be_qualified
	;	may_be_unqualified.

%-----------------------------------------------------------------------------%

:- implementation.

:- type pragma_c_code_attributes
	--->	attributes(
			may_call_mercury,
			thread_safe
		).

default_attributes(attributes(may_call_mercury, not_thread_safe)).

may_call_mercury(Attrs, MayCallMercury) :-
	Attrs = attributes(MayCallMercury, _).

thread_safe(Attrs, ThreadSafe) :-
	Attrs = attributes(_, ThreadSafe).

set_may_call_mercury(Attrs0, MayCallMercury, Attrs) :-
	Attrs0 = attributes(_, ThreadSafe),
	Attrs  = attributes(MayCallMercury, ThreadSafe).

set_thread_safe(Attrs0, ThreadSafe, Attrs) :-
	Attrs0 = attributes(MayCallMercury, _),
	Attrs  = attributes(MayCallMercury, ThreadSafe).
