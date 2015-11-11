%---------------------------------------------------------------------------%
% vim: ft=mercury ts=4 sw=4 et
%---------------------------------------------------------------------------%
% Copyright (C) 1996-2012 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%---------------------------------------------------------------------------%
%
% File: module_qual.m.
% Main authors: stayl, fjh.
%
% The code in this module performs two tasks.
%
% - It checks for undefined types, typeclasses, insts and modes.
%
% - It module qualifies types, typeclasses, insts and modes within declaration
%   items in the source code of the compilation unit. The heads of all
%   declarations should be module qualified as they are read in by prog_io.m;
%   this module qualifies the bodies of those declarations.
%
%   Note that we don't qualify the parts of the augmented compilation unit
%   that derive from other modules' interface or optimization files, since
%   those parts should be read in fully module qualified already.
%
% The algorithm we use does two passes over all the items in the compilation
% unit. The first pass records the set of modules, types, typeclasses, insts
% and modes that are visible in the compilation unit. The second uses this
% information to actually do this module's job.
%
% If any type, typeclass, inst or mode used in the module is not uniquely
% module qualifiable, i.e. if we either find zero matches for it, or we find
% two or more matches for it, we can generate an error message for it.
% We do so when we are module qualifying a compilation unit; we don't when
% we are qualifying the contents of an interface file.
%
% If the --warn-interface-imports option is set, we generate warnings about
% modules imported in the interface that are not used in the interface.
%
% Note that this module is NOT the only place in the compiler that does module
% qualification. The modes of lambda expressions are qualified in modes.m,
% and predicate and function names are qualified during typecheck, with
% the results recorded during the post_typecheck phase of the purity pass.
% This is because figuring out whether e.g. a call to predicate `p' calls
% module m1's predicate p or module m2's predicate p may require knowing
% the types of the arguments in the call.
%
% Since this module does not and cannot know about the module qualification
% of predicate names, function names and function symbols, it cannot figure out
% which modules are referred to in goals. The only goals that may appear
% in the interface section of a module are in promise declarations.
% If a promise goal contains any unqualified symbols, the second pass
% leaves the symbol unchanged, but since the eventual actual qualification
% of the symbol could refer to any of the modules imported in the interface,
% we consider them *all* of them to be "used".
%
% For the same reason (we don't know what modules predicate names,
% function names and function symbols in goals may refer to), this module
% cannot implement any equivalent of --warn-interface-imports that would
% report unnecessary imports in the *implementation* section of a module.
%
% If the --warn-unused-imports option is set, then unused_imports.m
% can generate all the warnings we would, but it can generate *better*
% messages, since unlike the code here, it can report that an imported module
% is unused *anywhere* in the module. However, even if --warn-unused-imports
% *is* set, the code in unused_imports.m won't be invoked if we stop
% compilation before its normal invocation time, due to e.g. type or more
% errors. What we should do is generate warnings here; print them if we
% stop before the unused_imports pass; throw them away if we *do* get to
% that pass. We don't (yet) do this.
%
%---------------------------------------------------------------------------%

:- module parse_tree.module_qual.
:- interface.

:- import_module libs.globals.
:- import_module mdbcomp.sym_name.
:- import_module parse_tree.error_util.
:- import_module parse_tree.prog_data.
:- import_module parse_tree.prog_item.
:- import_module recompilation.

:- import_module list.
:- import_module maybe.

%---------------------------------------------------------------------------%

:- type maybe_found_undef_type
    --->    did_not_find_undef_type
    ;       found_undef_type.

:- type maybe_found_undef_inst
    --->    did_not_find_undef_inst
    ;       found_undef_inst.

:- type maybe_found_undef_mode
    --->    did_not_find_undef_mode
    ;       found_undef_mode.

:- type maybe_found_undef_typeclass
    --->    did_not_find_undef_typeclass
    ;       found_undef_typeclass.

    % module_qualify_aug_comp_unit(Globals, AugCompUnit0, AugCompUnit,
    %   EventSpecMap0, EventSpecMap, MaybeContext, EventSpecFileName, MQ_Info,
    %   UndefTypes, UndefInsts, UndefModes, UndefTypeClasses, !Specs):
    %
    % AugCompUnit is AugCompUnit0 with all items module qualified
    % as much as possible; likewise for EventSpecMap0 and EventSpecMap.
    %
    % Errors in EventSpecMap0 will be reported as being for EventSpecFileName.
    %
:- pred module_qualify_aug_comp_unit(globals::in,
    aug_compilation_unit::in, aug_compilation_unit::out,
    event_spec_map::in, event_spec_map::out, string::in, mq_info::out,
    maybe_found_undef_type::out, maybe_found_undef_inst::out,
    maybe_found_undef_mode::out, maybe_found_undef_typeclass::out,
    list(error_spec)::in, list(error_spec)::out) is det.

    % module_qualify_parse_tree_int(Globals, ParseTreeInt0, ParseTreeInt,
    %   !Specs):
    %
    % ParseTreeInt is ParseTreeInt0 with all items module qualified
    % as much as possible.
    %
:- pred module_qualify_parse_tree_int(globals::in,
    parse_tree_int::in, parse_tree_int::out,
    list(error_spec)::in, list(error_spec)::out) is det.

%---------------------------------------------------------------------------%

    % When we process types, typeclasses, insts or modes, we need to know
    % whether they occur in the interface of the current module. This is
    % so that if we see e.g. m1.t1 in the interface, we can mark module m1
    % as being used in the interface, so we can avoid generating a warning
    % about m1 being unused in the interface.
    %
:- type mq_in_interface
    --->    mq_not_used_in_interface
    ;       mq_used_in_interface.

    % This is called from make_hlds to qualify the mode of a lambda expression.
    %
:- pred qualify_lambda_mode_list(mq_in_interface::in, prog_context::in,
    list(mer_mode)::in, list(mer_mode)::out, mq_info::in, mq_info::out,
    list(error_spec)::in, list(error_spec)::out) is det.

    % This is called from make_hlds.m to qualify the modes in a
    % clause mode annotation.
    %
:- pred qualify_clause_mode_list(mq_in_interface::in, prog_context::in,
    list(mer_mode)::in, list(mer_mode)::out, mq_info::in, mq_info::out,
    list(error_spec)::in, list(error_spec)::out) is det.

    % This is called from make_hlds to qualify an explicit type qualification.
    %
:- pred qualify_type_qualification(mq_in_interface::in, prog_context::in,
    mer_type::in, mer_type::out, mq_info::in, mq_info::out,
    list(error_spec)::in, list(error_spec)::out) is det.

    % The type mq_info holds information needed for doing module qualification.
    %
:- type mq_info.

:- pred mq_info_get_found_undef_type(mq_info::in,
    maybe_found_undef_type::out) is det.
:- pred mq_info_get_found_undef_inst(mq_info::in,
    maybe_found_undef_inst::out) is det.
:- pred mq_info_get_found_undef_mode(mq_info::in,
    maybe_found_undef_mode::out) is det.
:- pred mq_info_get_found_undef_typeclass(mq_info::in,
    maybe_found_undef_typeclass::out) is det.

:- pred mq_info_get_recompilation_info(mq_info::in,
    maybe(recompilation_info)::out) is det.
:- pred mq_info_set_recompilation_info(maybe(recompilation_info)::in,
    mq_info::in, mq_info::out) is det.

    % The type partial_qualifier_info holds info need for computing which
    % partial quantifiers are visible -- see get_partial_qualifiers/3.
    %
:- type partial_qualifier_info.

:- pred mq_info_get_partial_qualifier_info(mq_info::in,
    partial_qualifier_info::out) is det.

    % Suppose we are processing a definition which defines the symbol
    % foo.bar.baz.quux/1. Then we insert the following symbols
    % into the symbol table:
    %   - if the current value of the NeedQual flag at this point
    %       is `may_be_unqualified',
    %       i.e. module `foo.bar.baz' was imported,
    %       then we insert the fully unqualified symbol quux/1;
    %   - if module `foo.bar.baz' occurs in the "imported" section,
    %       i.e. if module `foo.bar' was imported,
    %       then we insert the partially qualified symbol baz.quux/1;
    %   - if module `foo.bar' occurs in the "imported" section,
    %       i.e. if module `foo' was imported,
    %       then we insert the partially qualified symbol bar.baz.quux/1;
    %   - we always insert the fully qualified symbol foo.bar.baz.quux/1.
    %
    % The predicate `get_partial_qualifiers' returns all of the
    % partial qualifiers for which we need to insert definitions,
    % i.e. all the ones which are visible. For example,
    % given as input `foo.bar.baz', it returns a list containing
    %   (1) `baz', iff `foo.bar' is imported, and
    %   (2) `bar.baz', iff `foo' is imported.
    % Note that the caller will still need to handle the fully-qualified
    % and fully-unqualified versions separately.
    %
:- pred get_partial_qualifiers(module_name::in, partial_qualifier_info::in,
    list(module_name)::out) is det.

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%

:- implementation.

:- import_module libs.options.
:- import_module mdbcomp.prim_data.
:- import_module parse_tree.get_dependencies.
:- import_module parse_tree.prog_io_sym_name.
:- import_module parse_tree.prog_out.
:- import_module parse_tree.prog_util.

:- import_module assoc_list.
:- import_module bool.
:- import_module int.
:- import_module map.
:- import_module pair.
:- import_module require.
:- import_module set.
:- import_module string.
:- import_module term.

%---------------------------------------------------------------------------%

module_qualify_aug_comp_unit(Globals, AugCompUnit0, AugCompUnit,
        EventSpecMap0, EventSpecMap, EventSpecFileName, !:Info,
        UndefTypes, UndefInsts, UndefModes, UndefTypeClasses, !Specs) :-
    AugCompUnit0 = aug_compilation_unit(ModuleName, ModuleNameContext,
        ModuleVersionNumbers, SrcItemBlocks0,
        DirectIntItemBlocks, IndirectIntItemBlocks,
        OptItemBlocks, IntForOptItemBlocks),
    init_mq_info(Globals, ModuleName, SrcItemBlocks0,
        DirectIntItemBlocks ++ IndirectIntItemBlocks,
        OptItemBlocks, IntForOptItemBlocks, should_report_errors, !:Info),
    collect_mq_info_in_item_blocks(src_section_mq_info, SrcItemBlocks0,
        !Info),
    collect_mq_info_in_item_blocks(int_section_mq_info, DirectIntItemBlocks,
        !Info),
    % XXX ITEM_LIST asymmetry: collect from 2, qualify 1
    module_qualify_items_in_src_item_blocks(SrcItemBlocks0, SrcItemBlocks,
        !Info, !Specs),
    AugCompUnit = aug_compilation_unit(ModuleName, ModuleNameContext,
        ModuleVersionNumbers, SrcItemBlocks,
        DirectIntItemBlocks, IndirectIntItemBlocks,
        OptItemBlocks, IntForOptItemBlocks),

    map.to_assoc_list(EventSpecMap0, EventSpecList0),
    qualify_event_specs(mq_not_used_in_interface, EventSpecFileName,
        EventSpecList0, EventSpecList, !Info, !Specs),
    map.from_assoc_list(EventSpecList, EventSpecMap),
    mq_info_get_found_undef_type(!.Info, UndefTypes),
    mq_info_get_found_undef_inst(!.Info, UndefInsts),
    mq_info_get_found_undef_mode(!.Info, UndefModes),
    mq_info_get_found_undef_typeclass(!.Info, UndefTypeClasses),

    % Warn about any unused module imports in the interface.
    % There is a special case involving type class instances that
    % we need to handle here. Consider:
    %
    %   :- module foo.
    %   :- interface.
    %
    %   :- import_module bar.
    %   :- typeclass tc1(T) <= tc2(T).
    %   :- instance tc1(unit).
    %
    % where module bar exports the instance tc2(unit). We must import
    % the module bar in the interface of the module foo in order for
    % the superclass constraint on the instance tc1(unit) to be satisfied.
    % However, at this stage of compilation we do not know that the
    % instance tc2(unit) needs to be visible. (Knowing this would require
    % a more extensive analysis of type classes and instances to be done
    % in this module.)
    %
    % In order to prevent the import of the module bar being erroneously
    % reported as unused, we make the conservative assumption that any
    % imported module that exports a type class instance is used in
    % the interface of the importing module, except if the importing
    % module itself exports _no_ type class instances.
    mq_info_get_as_yet_unused_interface_modules(!.Info, UnusedImportsMap0),
    mq_info_get_exported_instances_flag(!.Info, ModuleExportsInstances),
    (
        ModuleExportsInstances = yes,
        mq_info_get_imported_instance_modules(!.Info, InstanceImports),
        map.delete_list(set.to_sorted_list(InstanceImports),
            UnusedImportsMap0, UnusedImportsMap)
    ;
        ModuleExportsInstances = no,
        UnusedImportsMap = UnusedImportsMap0
    ),
    map.to_assoc_list(UnusedImportsMap, UnusedImports),
    list.foldl(warn_unused_interface_import(ModuleName), UnusedImports,
        !Specs).

module_qualify_parse_tree_int(Globals, ParseTreeInt0, ParseTreeInt, !Specs) :-
    ParseTreeInt0 = parse_tree_int(ModuleName, IntFileKind, ModuleNameContext,
        MaybeVersionNumbers, IntIncls, ImpIncls, IntAvails, ImpAvails,
        IntItems0, ImpItems0),
    IntSrcItemBlocks0 = [item_block(sms_interface, term.context_init,
        IntIncls, IntAvails, IntItems0)],
    ImpSrcItemBlocks0 = [item_block(sms_implementation, term.context_init,
        ImpIncls, ImpAvails, ImpItems0)],
    % XXX ITEM_LIST The completely separate treatment of the interface
    % and implementation part of an interface file preserves old behavior;
    % write_short_interface_file in write_module_interface_files.m used
    % to call module_qualify_items separately on the interface and
    % implementation items. I (zs) this is likely to be a bug, in that
    % the module qualification of the items in the implementation section
    % doesn't see the declarations in the interface section.
    % XXX ITEM_LIST Check whether we can get a nonempty list of implicit
    % dependencies in either call to collect_mq_info_in_aug_item_blocks below.
    DummyItemBlocks = []:list(src_item_block),
    some [!IntInfo] (
        init_mq_info(Globals, ModuleName, IntSrcItemBlocks0,
            DummyItemBlocks, DummyItemBlocks, DummyItemBlocks,
            should_not_report_errors, !:IntInfo),
        collect_mq_info_in_item_blocks(src_section_mq_info, IntSrcItemBlocks0,
            !IntInfo),
        module_qualify_items_loop(mq_used_in_interface,
            IntItems0, IntItems, !.IntInfo, _, !Specs)
    ),
    some [!ImpInfo] (
        init_mq_info(Globals, ModuleName, ImpSrcItemBlocks0,
            DummyItemBlocks, DummyItemBlocks, DummyItemBlocks,
            should_not_report_errors, !:ImpInfo),
        collect_mq_info_in_item_blocks(src_section_mq_info, ImpSrcItemBlocks0,
            !ImpInfo),
        module_qualify_items_loop(mq_not_used_in_interface,
            ImpItems0, ImpItems, !.ImpInfo, _, !Specs)
    ),
    ParseTreeInt = parse_tree_int(ModuleName, IntFileKind, ModuleNameContext,
        MaybeVersionNumbers, IntIncls, ImpIncls, IntAvails, ImpAvails,
        IntItems, ImpItems).

%---------------------------------------------------------------------------%

qualify_lambda_mode_list(InInt, Context, Modes0, Modes, !Info, !Specs) :-
    ErrorContext = mqec_lambda_expr(Context),
    qualify_mode_list(InInt, ErrorContext, Modes0, Modes, !Info, !Specs).

qualify_clause_mode_list(InInt, Context, Modes0, Modes, !Info, !Specs) :-
    ErrorContext = mqec_clause_mode_annotation(Context),
    qualify_mode_list(InInt, ErrorContext, Modes0, Modes, !Info, !Specs).

qualify_type_qualification(InInt, Context, Type0, Type, !Info, !Specs) :-
    ErrorContext = mqec_type_qual(Context),
    qualify_type(InInt, ErrorContext, Type0, Type, !Info, !Specs).

:- type partial_qualifier_info
    --->    partial_qualifier_info(module_id_set).

mq_info_get_partial_qualifier_info(MQInfo, QualifierInfo) :-
    mq_info_get_modules(MQInfo, ModuleIdSet),
    QualifierInfo = partial_qualifier_info(ModuleIdSet).

%---------------------------------------------------------------------------%

get_partial_qualifiers(ModuleName, PartialQualInfo, PartialQualifiers) :-
    PartialQualInfo = partial_qualifier_info(ModuleIdSet),
    (
        ModuleName = unqualified(_),
        PartialQualifiers = []
    ;
        ModuleName = qualified(Parent, Child),
        get_partial_qualifiers_acc(Parent, unqualified(Child),
            ModuleIdSet, [], PartialQualifiers)
    ).

:- pred get_partial_qualifiers_acc(module_name::in, module_name::in,
    module_id_set::in, list(module_name)::in, list(module_name)::out) is det.

get_partial_qualifiers_acc(ImplicitPart, ExplicitPart, ModuleIdSet,
        !Qualifiers) :-
    % If the ImplicitPart module was imported, rather than just being used,
    % then insert the ExplicitPart module into the list of valid partial
    % qualifiers.
    ( if
        parent_module_is_imported(ImplicitPart, ExplicitPart, ModuleIdSet)
    then
        !:Qualifiers = [ExplicitPart | !.Qualifiers]
    else
        true
    ),
    % Recursively try to add the other possible partial qualifiers.
    (
        ImplicitPart = qualified(Parent, Child),
        NextImplicitPart = Parent,
        NextExplicitPart = add_outermost_qualifier(Child, ExplicitPart),
        get_partial_qualifiers_acc(NextImplicitPart, NextExplicitPart,
            ModuleIdSet, !Qualifiers)
    ;
        ImplicitPart = unqualified(_)
    ).

    % Check whether the parent module was imported, given the name of a
    % child (or grandchild, etc.) module occurring in that parent module.
    %
:- pred parent_module_is_imported(module_name::in, module_name::in,
    module_id_set::in) is semidet.

parent_module_is_imported(ParentModule, ChildModule, ModuleIdSet) :-
    % Find the module name at the start of the ChildModule;
    % this submodule will be a direct sub-module of ParentModule.
    DirectSubModuleName = get_first_module_name(ChildModule),

    % Check that the ParentModule was imported.
    % We do this by looking up the definitions for the direct sub-module
    % and checking that the one in ParentModule came from an
    % imported module.
    Arity = 0,
    map.search(ModuleIdSet, DirectSubModuleName, SubMap),
    map.search(SubMap, Arity, PermissionsMap),
    map.search(PermissionsMap, ParentModule, ParentModulePermissions),
    ParentModulePermissions = module_permissions(_, may_be_unqualified).

    % Given a module name, possibly module-qualified, return the name
    % of the first module in the qualifier list. For example, given
    % `foo.bar.baz', this returns `foo', and given just `baz',
    % it returns `baz'.
    %
:- func get_first_module_name(module_name) = string.

get_first_module_name(unqualified(ModuleName)) = ModuleName.
get_first_module_name(qualified(Parent, _)) = get_first_module_name(Parent).

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%
%
% This section contains the predicates that record what entities are available
% in which modules and with what permissions.
%

    % We record two kinds of permissions for each entity. Whether
    % it may be used in the interface, and whether it may be used
    % without module qualification.
    %
    % An entity may be used in the interface if it is defined in the current
    % module or one of its ancestors, or if it is defined in a module that is
    % imported (or used) in the interface.
    %
    % An entity may be used without module qualification if it is defined
    % in the current module, in one of its ancestors, or in a module
    % that is the subject of an explicit import_module declaration
    % in the current module. It may not be used without qualification
    % if it is made available by a use_module declaration, or if it is
    % defined in a `.opt' and `.trans_opt' file.
:- type module_permissions
    --->    module_permissions(
                use_in_interface,
                need_qualifier
            ).

:- type use_in_interface
    --->    may_not_use_in_interface
    ;       may_use_in_interface.

:- type mq_section
    --->    mq_section_exported
    ;       mq_section_local
    ;       mq_section_imported(import_locn)
    ;       mq_section_abstract_imported.

:- type section_mq_info(MS) == (pred(MS, mq_section, module_permissions)).
:- inst section_mq_info     == (pred(in, out, out) is det).

%---------------------%

:- pred src_section_mq_info(src_module_section::in,
    mq_section::out, module_permissions::out) is det.

src_section_mq_info(SrcSection, MQSection, Permissions) :-
    (
        SrcSection = sms_interface,
        MQSection = mq_section_exported,
        Permissions =
            module_permissions(may_use_in_interface, may_be_unqualified)
    ;
        ( SrcSection = sms_implementation
        ; SrcSection = sms_impl_but_exported_to_submodules
        ),
        MQSection = mq_section_local,
        Permissions =
            module_permissions(may_not_use_in_interface, may_be_unqualified)
    ).

:- pred int_section_mq_info(int_module_section::in,
    mq_section::out, module_permissions::out) is det.

int_section_mq_info(IntSection, MQSection, Permissions) :-
    (
        (
            IntSection = ims_imported(_ModuleName, _IntFileKind, Locn),
            NeedQual = may_be_unqualified
        ;
            IntSection = ims_used(_ModuleName, _IntFileKind, Locn),
            NeedQual = must_be_qualified
        ),
        (
            ( Locn = import_locn_interface
            ; Locn = import_locn_import_by_ancestor
            ; Locn = import_locn_ancestor_private_interface_proper
            ),
            MayUseInInterface = may_use_in_interface
        ;
            Locn = import_locn_implementation,
            MayUseInInterface = may_not_use_in_interface
        ),
        MQSection = mq_section_imported(Locn),
        Permissions = module_permissions(MayUseInInterface, NeedQual)
    ;
        IntSection = ims_abstract_imported(_ModuleName, _IntFileKind),
        MQSection = mq_section_abstract_imported,
        Permissions =
            module_permissions(may_not_use_in_interface, must_be_qualified)
    ).

%---------------------%

    % Pass over the item_block list collecting all defined module, type,
    % inst, mode and class ids, together with their permissions.
    %
:- pred collect_mq_info_in_item_blocks(
    section_mq_info(MS)::in(section_mq_info), list(item_block(MS))::in,
    mq_info::in, mq_info::out) is det.

collect_mq_info_in_item_blocks(_, [], !Info).
collect_mq_info_in_item_blocks(SectionInfo, [ItemBlock | ItemBlocks], !Info) :-
    ItemBlock = item_block(Section, _Context, Incls, Avails, Items),
    SectionInfo(Section, MQSection, Permissions),

    % The usual case is Incls = []; optimize for it.
    (
        Incls = []
    ;
        Incls = [_ | _],
        mq_info_get_modules(!.Info, Modules0),
        list.foldl(collect_mq_info_in_item_include(Permissions), Incls,
            Modules0, Modules),
        mq_info_set_modules(Modules, !Info)
    ),

    % The usual case is Avails = [_ | _]. Testing for that would be
    % unnecessary overhead in most cases.
    mq_info_get_imported_modules(!.Info, ImportedModules0),
    mq_info_get_as_yet_unused_interface_modules(!.Info, UnusedIntModules0),
    list.foldl2(collect_mq_info_in_item_avail(MQSection, Permissions), Avails,
        ImportedModules0, ImportedModules,
        UnusedIntModules0, UnusedIntModules),
    mq_info_set_imported_modules(ImportedModules, !Info),
    mq_info_set_as_yet_unused_interface_modules(UnusedIntModules, !Info),

    collect_mq_info_in_items(MQSection, Permissions, Items, !Info),
    collect_mq_info_in_item_blocks(SectionInfo, ItemBlocks, !Info).

    % For submodule definitions (whether nested or separate,
    % i.e. either `:- module foo.' or `:- include_module foo.'),
    % add the module id to the module_id_set.
    %
    % We don't actually handle nested submodules here. Nested submodules
    % were separated out and replaced with the internal representation of
    % the `:- include_module' declaration that would correspond to it
    % by the code that created the module's raw_compilation_unit, which
    % was later transformed into the aug_compilation_unit whose items
    % we process here.
    %
:- pred collect_mq_info_in_item_include(module_permissions::in,
    item_include::in, module_id_set::in, module_id_set::out) is det.

collect_mq_info_in_item_include(Permissions, Incl, !Modules) :-
    Incl = item_include(IncludedModuleName, _Context, _SeqNum),
    Arity = 0,
    id_set_insert(Permissions, mq_id(IncludedModuleName, Arity), !Modules).

    % For import declarations (`:- import_module' or `:- use_module'),
    % if we are currently in the interface section, then add the
    % imported modules to the as_yet_unused_interface_modules list.
    %
    % XXX ITEM_LIST Why do we base this decision on the status we get
    % from the mq_info, instead of directly on the current section's
    % section kind?
    %
:- pred collect_mq_info_in_item_avail(mq_section::in, module_permissions::in,
    item_avail::in, set(module_name)::in, set(module_name)::out,
    map(module_name, one_or_more(prog_context))::in,
    map(module_name, one_or_more(prog_context))::out) is det.

collect_mq_info_in_item_avail(MQSection, _Permissions, Avail,
        !ImportedModules, !UnusedIntModules) :-
    % Modules imported from the the proper private interface of ancestors of
    % the current module are treated as if they were directly imported
    % by the current module.
    %
    % We check that all modules imported in the interface are used
    % in the interface.
    ( Avail = avail_import(avail_import_info(ModuleName, Context, _SeqNum))
    ; Avail = avail_use(avail_use_info(ModuleName, Context, _SeqNum))
    ),
    (
        ( MQSection = mq_section_local
        ; MQSection = mq_section_imported(
            import_locn_ancestor_private_interface_proper)
        ),
        set.insert(ModuleName, !ImportedModules)
    ;
        MQSection = mq_section_exported,
        set.insert(ModuleName, !ImportedModules),
        % Most of the time, ModuleName does not occur in !.UnusedIntModules.
        % We therefore try the insertion first, and only if the insertion
        % fails do we look up and update the existing entry (OldContexts)
        % that caused that failure.
        OnlyNewContexts = one_or_more(Context, []),
        ( if map.insert(ModuleName, OnlyNewContexts, !UnusedIntModules) then
            true
        else
            map.lookup(!.UnusedIntModules, ModuleName, OldContexts),
            OldContexts = one_or_more(OldHeadContext, OldTailContexts),
            NewContexts = one_or_more(Context,
                [OldHeadContext | OldTailContexts]),
            map.det_update(ModuleName, NewContexts, !UnusedIntModules)
        )
    ;
        ( MQSection = mq_section_imported(import_locn_interface)
        ; MQSection = mq_section_imported(import_locn_implementation)
        ; MQSection = mq_section_imported(import_locn_import_by_ancestor)
        ; MQSection = mq_section_abstract_imported
        )
    ).

    % Pass over the item list collecting all defined module, type, mode and
    % inst ids, all module synonym definitions, and the names of all
    % modules imported in the interface.
    %
:- pred collect_mq_info_in_items(mq_section::in, module_permissions::in,
    list(item)::in, mq_info::in, mq_info::out) is det.

collect_mq_info_in_items(_, _, [], !Info).
collect_mq_info_in_items(MQSection, Permissions, [Item | Items], !Info) :-
    collect_mq_info_in_item(MQSection, Permissions, Item, !Info),
    collect_mq_info_in_items(MQSection, Permissions, Items, !Info).

:- pred collect_mq_info_in_item(mq_section::in, module_permissions::in,
    item::in, mq_info::in, mq_info::out) is det.

collect_mq_info_in_item(MQSection, Permissions, Item, !Info) :-
    (
        Item = item_type_defn(ItemTypeDefn),
        ItemTypeDefn = item_type_defn_info(SymName, Params, _, _, _, _),
        ( if MQSection = mq_section_abstract_imported then
            % This item is not visible in the current module.
            true
        else
            list.length(Params, Arity),
            mq_info_get_types(!.Info, Types0),
            id_set_insert(Permissions, mq_id(SymName, Arity), Types0, Types),
            mq_info_set_types(Types, !Info)
        )
    ;
        Item = item_inst_defn(ItemInstDefn),
        ItemInstDefn = item_inst_defn_info(SymName, Params, _, _, _, _, _),
        ( if MQSection = mq_section_abstract_imported then
            % This item is not visible in the current module.
            true
        else
            list.length(Params, Arity),
            mq_info_get_insts(!.Info, Insts0),
            id_set_insert(Permissions, mq_id(SymName, Arity), Insts0, Insts),
            mq_info_set_insts(Insts, !Info)
        )
    ;
        Item = item_mode_defn(ItemModeDefn),
        ItemModeDefn = item_mode_defn_info(SymName, Params, _, _, _, _),
        ( if MQSection = mq_section_abstract_imported then
            % This item is not visible in the current module.
            true
        else
            list.length(Params, Arity),
            mq_info_get_modes(!.Info, Modes0),
            id_set_insert(Permissions, mq_id(SymName, Arity), Modes0, Modes),
            mq_info_set_modes(Modes, !Info)
        )
    ;
        Item = item_promise(ItemPromise),
        ItemPromise = item_promise_info(_PromiseType, Goal, _ProgVarSet,
            _UnivVars, _Context, _SeqNum),
        collect_used_modules_in_promise_goal(Goal,
            set.init, UsedModuleNames, no, FoundUnqual),
        (
            FoundUnqual = no,
            InInt = mq_section_to_in_interface(MQSection),
            set.fold(mq_info_set_module_used(InInt), UsedModuleNames, !Info)
        ;
            % Any unqualified symbol in the promise might come from *any* of
            % the imported modules. There is no way for us to tell which ones,
            % so we conservatively assume that it uses *all* of them.
            FoundUnqual = yes,
            map.init(UnusedModules),
            mq_info_set_as_yet_unused_interface_modules(UnusedModules, !Info)
        )
    ;
        Item = item_typeclass(ItemTypeClass),
        ItemTypeClass = item_typeclass_info(SymName, Params, _, _, _, _, _, _),
        ( if MQSection = mq_section_abstract_imported then
            % This item is not visible in the current module.
            true
        else
            list.length(Params, Arity),
            mq_info_get_classes(!.Info, Classes0),
            id_set_insert(Permissions, mq_id(SymName, Arity),
                Classes0, Classes),
            mq_info_set_classes(Classes, !Info)
        )
    ;
        Item = item_instance(ItemInstance),
        ( if MQSection = mq_section_imported(_) then
            InstanceModule = ItemInstance ^ ci_module_containing_instance,
            mq_info_get_imported_instance_modules(!.Info,
                ImportedInstanceModules0),
            set.insert(InstanceModule,
                ImportedInstanceModules0, ImportedInstanceModules),
            mq_info_set_imported_instance_modules(ImportedInstanceModules,
                !Info)
        else
            true
        )
    ;
        ( Item = item_clause(_)
        ; Item = item_pred_decl(_)
        ; Item = item_mode_decl(_)
        ; Item = item_pragma(_)
        ; Item = item_initialise(_)
        ; Item = item_finalise(_)
        ; Item = item_mutable(_)
        ; Item = item_nothing(_)
        )
        % Do nothing.
    ).

:- func mq_section_to_in_interface(mq_section) = mq_in_interface.

mq_section_to_in_interface(mq_section_exported) = mq_used_in_interface.
mq_section_to_in_interface(mq_section_local) = mq_not_used_in_interface.
mq_section_to_in_interface(mq_section_imported(_)) = mq_not_used_in_interface.
mq_section_to_in_interface(mq_section_abstract_imported) =
    mq_not_used_in_interface.

%---------------------%

    % Scan Goal. Add the set of module names found in the qualified symbols
    % in Goal to !UsedModuleNames. If there exists a single unqualified symbol,
    % in Goal, set !Success to no.
    %
:- pred collect_used_modules_in_promise_goal(goal::in,
    set(module_name)::in, set(module_name)::out, bool::in, bool::out) is det.

collect_used_modules_in_promise_goal(Goal, !UsedModuleNames, !FoundUnqual) :-
    (
        ( Goal = conj_expr(_, SubGoalA, SubGoalB)
        ; Goal = par_conj_expr(_, SubGoalA, SubGoalB)
        ; Goal = disj_expr(_, SubGoalA, SubGoalB)
        ; Goal = implies_expr(_, SubGoalA, SubGoalB)
        ; Goal = equivalent_expr(_, SubGoalA, SubGoalB)
        ),
        collect_used_modules_in_promise_goal(SubGoalA,
            !UsedModuleNames, !FoundUnqual),
        collect_used_modules_in_promise_goal(SubGoalB,
            !UsedModuleNames, !FoundUnqual)
    ;
        ( Goal = true_expr(_)
        ; Goal = fail_expr(_)
        )
    ;
        ( Goal = not_expr(_, SubGoal)
        ; Goal = some_expr(_, _, SubGoal)
        ; Goal = some_state_vars_expr(_, _, SubGoal)
        ; Goal = all_expr(_, _, SubGoal)
        ; Goal = all_state_vars_expr(_, _, SubGoal)
        ; Goal = promise_purity_expr(_, _, SubGoal)
        ; Goal = promise_equivalent_solutions_expr(_, _, _, _, _, SubGoal)
        ; Goal = promise_equivalent_solution_sets_expr(_, _, _, _, _, SubGoal)
        ; Goal = promise_equivalent_solution_arbitrary_expr(_, _, _, _, _,
            SubGoal)
        ; Goal = require_detism_expr(_, _, SubGoal)
        ; Goal = require_complete_switch_expr(_, _, SubGoal)
        ; Goal = require_switch_arms_detism_expr(_, _, _, SubGoal)
        ; Goal = trace_expr(_, _, _, _, _, SubGoal)
        ),
        collect_used_modules_in_promise_goal(SubGoal,
            !UsedModuleNames, !FoundUnqual)
    ;
        Goal = try_expr(_, _, SubGoal, ThenGoal, MaybeElseGoal, Catches,
            MaybeCatchAny),
        collect_used_modules_in_promise_goal(SubGoal,
            !UsedModuleNames, !FoundUnqual),
        collect_used_modules_in_promise_goal(ThenGoal,
            !UsedModuleNames, !FoundUnqual),
        (
            MaybeElseGoal = no
        ;
            MaybeElseGoal = yes(ElseGoal),
            collect_used_modules_in_promise_goal(ElseGoal,
                !UsedModuleNames, !FoundUnqual)
        ),
        list.foldl2(collect_used_modules_in_promise_catch, Catches,
            !UsedModuleNames, !FoundUnqual),
        (
            MaybeCatchAny = no
        ;
            MaybeCatchAny = yes(catch_any_expr(_, CatchAnyGoal)),
            collect_used_modules_in_promise_goal(CatchAnyGoal,
                !UsedModuleNames, !FoundUnqual)
        )
    ;
        Goal = atomic_expr(_, _, _, _, MainGoal, OrElseGoals),
        collect_used_modules_in_promise_goal(MainGoal,
            !UsedModuleNames, !FoundUnqual),
        collect_used_modules_in_promise_goals(OrElseGoals,
            !UsedModuleNames, !FoundUnqual)
    ;
        Goal = if_then_else_expr(_, _, _, CondGoal, ThenGoal, ElseGoal),
        collect_used_modules_in_promise_goal(CondGoal,
            !UsedModuleNames, !FoundUnqual),
        collect_used_modules_in_promise_goal(ThenGoal,
            !UsedModuleNames, !FoundUnqual),
        collect_used_modules_in_promise_goal(ElseGoal,
            !UsedModuleNames, !FoundUnqual)
    ;
        Goal = event_expr(_, _Name, ArgTerms0),
        list.map(term.coerce, ArgTerms0, ArgTerms),
        collect_used_modules_in_terms(ArgTerms, !UsedModuleNames, !FoundUnqual)
    ;
        Goal = call_expr(_, SymName, ArgTerms0, _Purity),
        (
            SymName = qualified(ModuleName, _),
            set.insert(ModuleName, !UsedModuleNames)
        ;
            SymName = unqualified(_),
            !:FoundUnqual = yes
        ),
        list.map(term.coerce, ArgTerms0, ArgTerms),
        collect_used_modules_in_terms(ArgTerms, !UsedModuleNames, !FoundUnqual)
    ;
        Goal = unify_expr(_, LHS0, RHS0, _Purity),
        term.coerce(LHS0, LHS),
        term.coerce(RHS0, RHS),
        collect_used_modules_in_term(LHS, !UsedModuleNames, !FoundUnqual),
        collect_used_modules_in_term(RHS, !UsedModuleNames, !FoundUnqual)
    ).

    % Performs collect_used_modules_in_promise_goal on a list of goals.
    %
:- pred collect_used_modules_in_promise_goals(list(goal)::in,
    set(module_name)::in, set(module_name)::out, bool::in, bool::out) is det.

collect_used_modules_in_promise_goals([], !UsedModuleNames, !FoundUnqual).
collect_used_modules_in_promise_goals([Goal | Goals],
        !UsedModuleNames, !FoundUnqual) :-
    collect_used_modules_in_promise_goal(Goal,
        !UsedModuleNames, !FoundUnqual),
    collect_used_modules_in_promise_goals(Goals,
        !UsedModuleNames, !FoundUnqual).

:- pred collect_used_modules_in_promise_catch(catch_expr::in,
    set(module_name)::in, set(module_name)::out, bool::in, bool::out) is det.

collect_used_modules_in_promise_catch(CatchExpr,
        !UsedModuleNames, !FoundUnqual) :-
    CatchExpr = catch_expr(Pattern0, Goal),
    term.coerce(Pattern0, Pattern),
    collect_used_modules_in_term(Pattern, !UsedModuleNames, !FoundUnqual),
    collect_used_modules_in_promise_goal(Goal, !UsedModuleNames, !FoundUnqual).

    % Add all the module names in qualified sym_names in Term to
    % !UsedModuleNames, and set !FoundUnqual to true if any of the sym_names
    % in Term is unqualified.
    %
:- pred collect_used_modules_in_term(term::in,
    set(module_name)::in, set(module_name)::out, bool::in, bool::out) is det.

collect_used_modules_in_term(Term, !UsedModuleNames, !FoundUnqual) :-
    ( if try_parse_sym_name_and_args(Term, SymName, ArgTerms) then
        (
            SymName = qualified(ModuleName, _),
            set.insert(ModuleName, !UsedModuleNames)
        ;
            SymName = unqualified(_),
            !:FoundUnqual = yes
        ),
        collect_used_modules_in_terms(ArgTerms, !UsedModuleNames, !FoundUnqual)
    else
        true
    ).

:- pred collect_used_modules_in_terms(list(term)::in,
    set(module_name)::in, set(module_name)::out, bool::in, bool::out) is det.

collect_used_modules_in_terms([], !UsedModuleNames, !FoundUnqual).
collect_used_modules_in_terms([Term | Terms],
        !UsedModuleNames, !FoundUnqual) :-
    collect_used_modules_in_term(Term, !UsedModuleNames, !FoundUnqual),
    collect_used_modules_in_terms(Terms, !UsedModuleNames, !FoundUnqual).

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%

    % Iterate over the items in the given blocks, module qualifying
    % all declarations. Stop when we reach a section that is imported,
    % since imported declarations should already be module qualified.
    % (An imported block should never be followed by an unimported block.)
    %
:- pred module_qualify_items_in_src_item_blocks(
    list(src_item_block)::in, list(src_item_block)::out,
    mq_info::in, mq_info::out,
    list(error_spec)::in, list(error_spec)::out) is det.

module_qualify_items_in_src_item_blocks([], [], !Info, !Specs).
module_qualify_items_in_src_item_blocks([SrcItemBlock0 | SrcItemBlocks0],
        [SrcItemBlock | SrcItemBlocks], !Info, !Specs) :-
    SrcItemBlock0 = item_block(SrcSection, Context, Incls, Avails, Items0),
    (
        SrcSection = sms_interface,
        InInt = mq_used_in_interface
    ;
        ( SrcSection = sms_implementation
        ; SrcSection = sms_impl_but_exported_to_submodules
        ),
        InInt = mq_not_used_in_interface
    ),
    (
        Incls = []
    ;
        Incls = [_ | _],
        % The submodule might make use of *any* of the imported modules.
        % There is no way for us to tell which ones. So we conservatively
        % assume that it uses *all* of them.
        % XXX ITEM_LIST Fix this too-conservative behavior.
        % If a submodule needs a module that the parent doesn't,
        % it should import it for itself. Anything else may lead to
        % unnecessary recompilations.
        map.init(UnusedModules),
        mq_info_set_as_yet_unused_interface_modules(UnusedModules, !Info)
    ),
    module_qualify_items_loop(InInt, Items0, Items, !Info, !Specs),
    SrcItemBlock = item_block(SrcSection, Context, Incls, Avails, Items),
    module_qualify_items_in_src_item_blocks(SrcItemBlocks0, SrcItemBlocks,
        !Info, !Specs).

:- pred module_qualify_items_loop(mq_in_interface::in,
    list(item)::in, list(item)::out, mq_info::in, mq_info::out,
    list(error_spec)::in, list(error_spec)::out) is det.

module_qualify_items_loop(_InInt, [], [], !Info, !Specs).
module_qualify_items_loop(InInt, [HeadItem0 | TailItems0], Items,
        !Info, !Specs) :-
    module_qualify_item(InInt, HeadItem0, HeadItem, !Info, !Specs),
    module_qualify_items_loop(InInt, TailItems0, TailItems, !Info, !Specs),
    Items = [HeadItem | TailItems]. % lcmc

    % Module qualify a single item.
    %
:- pred module_qualify_item(mq_in_interface::in, item::in, item::out,
    mq_info::in, mq_info::out,
    list(error_spec)::in, list(error_spec)::out) is det.

module_qualify_item(InInt, Item0, Item, !Info, !Specs) :-
    (
        ( Item0 = item_clause(_)
        ; Item0 = item_initialise(_)
        ; Item0 = item_finalise(_)
        ; Item0 = item_promise(_)
        ; Item0 = item_nothing(_)
        ),
        Item = Item0
    ;
        Item0 = item_type_defn(ItemTypeDefn0),
        ItemTypeDefn0 = item_type_defn_info(SymName, Params, TypeDefn0,
            TVarSet, Context, SeqNum),
        list.length(Params, Arity),
        TypeCtor = type_ctor(SymName, Arity),
        qualify_type_defn(InInt, Context, TypeCtor, TypeDefn0, TypeDefn,
            !Info, !Specs),
        ItemTypeDefn = item_type_defn_info(SymName, Params, TypeDefn,
            TVarSet, Context, SeqNum),
        Item = item_type_defn(ItemTypeDefn)
    ;
        Item0 = item_inst_defn(ItemInstDefn0),
        ItemInstDefn0 = item_inst_defn_info(SymName, Params, MaybeForTypeCtor0,
            InstDefn0, InstVarSet, Context, SeqNum),
        list.length(Params, Arity),
        ErrorContext = mqec_inst(Context, mq_id(SymName, Arity)),
        qualify_inst_defn(InInt, ErrorContext, InstDefn0, InstDefn,
            !Info, !Specs),
        (
            MaybeForTypeCtor0 = yes(ForTypeCtor0),
            qualify_type_ctor(InInt, ErrorContext, ForTypeCtor0, ForTypeCtor,
                !Info, !Specs),
            MaybeForTypeCtor = yes(ForTypeCtor)
        ;
            MaybeForTypeCtor0 = no,
            MaybeForTypeCtor = no
        ),
        ItemInstDefn = item_inst_defn_info(SymName, Params, MaybeForTypeCtor,
            InstDefn, InstVarSet, Context, SeqNum),
        Item = item_inst_defn(ItemInstDefn)
    ;
        Item0 = item_mode_defn(ItemModeDefn0),
        ItemModeDefn0 = item_mode_defn_info(SymName, Params, ModeDefn0,
            InstVarSet, Context, SeqNum),
        list.length(Params, Arity),
        ErrorContext = mqec_mode(Context, mq_id(SymName, Arity)),
        qualify_mode_defn(InInt, ErrorContext, ModeDefn0, ModeDefn,
            !Info, !Specs),
        ItemModeDefn = item_mode_defn_info(SymName, Params, ModeDefn,
            InstVarSet, Context, SeqNum),
        Item = item_mode_defn(ItemModeDefn)
    ;
        Item0 = item_pred_decl(ItemPredDecl0),
        ItemPredDecl0 = item_pred_decl_info(SymName, PredOrFunc,
            TypesAndModes0, MaybeWithType0, MaybeWithInst0, MaybeDetism,
            Origin, TypeVarSet, InstVarSet, ExistQVars, Purity,
            Constraints0, Context, SeqNum),
        list.length(TypesAndModes0, Arity),
        ErrorContext = mqec_pred_or_func(Context, PredOrFunc,
            mq_id(SymName, Arity)),
        qualify_types_and_modes(InInt, ErrorContext,
            TypesAndModes0, TypesAndModes, !Info, !Specs),
        ConstraintErrorContext = mqcec_pred_decl(Context, PredOrFunc,
            SymName, Arity),
        qualify_prog_constraints(InInt, ConstraintErrorContext,
            Constraints0, Constraints, !Info, !Specs),
        (
            MaybeWithType0 = yes(WithType0),
            % XXX We could pass a more specific error context.
            qualify_type(InInt, ErrorContext, WithType0, WithType,
                !Info, !Specs),
            MaybeWithType = yes(WithType)
        ;
            MaybeWithType0 = no,
            MaybeWithType = no
        ),
        (
            MaybeWithInst0 = yes(WithInst0),
            % XXX We could pass a more specific error context.
            qualify_inst(InInt, ErrorContext, WithInst0, WithInst,
                !Info, !Specs),
            MaybeWithInst = yes(WithInst)
        ;
            MaybeWithInst0 = no,
            MaybeWithInst = no
        ),
        ItemPredDecl = item_pred_decl_info(SymName, PredOrFunc,
            TypesAndModes, MaybeWithType, MaybeWithInst, MaybeDetism,
            Origin, TypeVarSet, InstVarSet, ExistQVars, Purity,
            Constraints, Context, SeqNum),
        Item = item_pred_decl(ItemPredDecl)
    ;
        Item0 = item_mode_decl(ItemModeDecl0),
        ItemModeDecl0 = item_mode_decl_info(SymName, PredOrFunc, Modes0,
            MaybeWithInst0, MaybeDetism, InstVarSet, Context, SeqNum),
        list.length(Modes0, Arity),
        ErrorContext = mqec_pred_or_func_mode(Context, PredOrFunc,
            mq_id(SymName, Arity)),
        qualify_mode_list(InInt, ErrorContext, Modes0, Modes, !Info, !Specs),
        (
            MaybeWithInst0 = yes(WithInst0),
            % XXX We could pass a more specific error context.
            qualify_inst(InInt, ErrorContext, WithInst0, WithInst,
                !Info, !Specs),
            MaybeWithInst = yes(WithInst)
        ;
            MaybeWithInst0 = no,
            MaybeWithInst = no
        ),
        ItemModeDecl = item_mode_decl_info(SymName, PredOrFunc, Modes,
            MaybeWithInst, MaybeDetism, InstVarSet, Context, SeqNum),
        Item = item_mode_decl(ItemModeDecl)
    ;
        Item0 = item_typeclass(ItemTypeClass0),
        ItemTypeClass0 = item_typeclass_info(Name, Vars, Constraints0, FunDeps,
            Interface0, VarSet, Context, SeqNum),
        list.length(Vars, Arity),
        ConstraintErrorContext = mqcec_class_defn(Context, Name, Arity),
        qualify_prog_constraint_list(InInt, ConstraintErrorContext,
            Constraints0, Constraints, !Info, !Specs),
        (
            Interface0 = class_interface_abstract,
            Interface = class_interface_abstract
        ;
            Interface0 = class_interface_concrete(Methods0),
            ErrorContext = mqec_class(Context, mq_id(Name, Arity)),
            qualify_class_methods(InInt, ErrorContext, Methods0, Methods,
                !Info, !Specs),
            Interface = class_interface_concrete(Methods)
        ),
        ItemTypeClass = item_typeclass_info(Name, Vars, Constraints, FunDeps,
            Interface, VarSet, Context, SeqNum),
        Item = item_typeclass(ItemTypeClass)
    ;
        Item0 = item_instance(ItemInstance0),
        ItemInstance0 = item_instance_info(Name0, Types0, OriginalTypes0,
            Constraints0, Body0, VarSet, ModName, Context, SeqNum),
        list.length(Types0, Arity),
        Id0 = mq_id(Name0, Arity),
        ErrorContext = mqec_instance(Context, Id0),

        (
            InInt = mq_used_in_interface,
            mq_info_set_exported_instances_flag(yes, !Info)
        ;
            InInt = mq_not_used_in_interface
        ),

        % We don't qualify the implementation yet, since that requires
        % us to resolve overloading.
        ConstraintErrorContext = mqcec_instance_defn(Context, Name0,
            OriginalTypes0),
        qualify_prog_constraint_list(InInt, ConstraintErrorContext,
            Constraints0, Constraints, !Info, !Specs),
        qualify_class_name(InInt, ErrorContext, Id0, Name, !Info, !Specs),
        % XXX We don't want to keep the errors from the expansion of both
        % forms of the instance types, since printing two error messages about
        % one instance definition that make apparently contradictory
        % assumptions about whether the instance types are equiv-type-expanded
        % or not would be confusing. However, I (zs) cannot think of any
        % compelling reason right now for preferring the error messages
        % from one version of the types over the other.
        qualify_type_list(InInt, ErrorContext, Types0, Types,
            !Info, !Specs),
        qualify_type_list(InInt, ErrorContext, OriginalTypes0, OriginalTypes,
            !Info, !.Specs, _),
        qualify_instance_body(Name, Body0, Body),
        ItemInstance = item_instance_info(Name, Types, OriginalTypes,
            Constraints, Body, VarSet, ModName, Context, SeqNum),
        Item = item_instance(ItemInstance)
    ;
        Item0 = item_mutable(ItemMutable0),
        qualify_mutable(InInt, ItemMutable0, ItemMutable, !Info, !Specs),
        Item = item_mutable(ItemMutable)
    ;
        Item0 = item_pragma(ItemPragma0),
        ItemPragma0 = item_pragma_info(Pragma0, Origin, Context, SeqNum),
        qualify_pragma(InInt, Context, Pragma0, Pragma, !Info, !Specs),
        ItemPragma = item_pragma_info(Pragma, Origin, Context, SeqNum),
        Item = item_pragma(ItemPragma)
    ).

%---------------------------------------------------------------------------%
%
% Module qualify type definitions and types.
%

    % Qualify the constructors or other types in a type definition.
    %
:- pred qualify_type_defn(mq_in_interface::in,
    prog_context::in, type_ctor::in, type_defn::in, type_defn::out,
    mq_info::in, mq_info::out,
    list(error_spec)::in, list(error_spec)::out) is det.

qualify_type_defn(InInt, Context, TypeCtor, TypeDefn0, TypeDefn,
        !Info, !Specs) :-
    (
        TypeDefn0 = parse_tree_du_type(Ctors0, MaybeUserEqComp0,
            MaybeDirectArgCtors0),
        qualify_constructors(InInt, TypeCtor, Ctors0, Ctors, !Info, !Specs),
        % User-defined equality pred names will be converted into predicate
        % calls and then module-qualified after type analysis (during mode
        % analysis). That way, they get full type overloading resolution, etc.
        % Thus we don't module-qualify them here.
        MaybeUserEqComp = MaybeUserEqComp0,
        MaybeDirectArgCtors = MaybeDirectArgCtors0,
        TypeDefn = parse_tree_du_type(Ctors, MaybeUserEqComp,
            MaybeDirectArgCtors)
    ;
        TypeDefn0 = parse_tree_eqv_type(Type0),
        ErrorContext = mqec_type_defn(Context, TypeCtor),
        qualify_type(InInt, ErrorContext, Type0, Type, !Info, !Specs),
        TypeDefn = parse_tree_eqv_type(Type)
    ;
        TypeDefn0 = parse_tree_abstract_type(_),
        TypeDefn = TypeDefn0
    ;
        TypeDefn0 = parse_tree_foreign_type(_, _, _),
        TypeDefn = TypeDefn0
    ;
        TypeDefn0 = parse_tree_solver_type(SolverTypeDetails0,
            MaybeUserEqComp),
        SolverTypeDetails0 = solver_type_details(RepnType0, InitPred,
            GroundInst0, AnyInst0, MutableItems0),
        ErrorContext = mqec_type_defn(Context, TypeCtor),
        qualify_type(InInt, ErrorContext, RepnType0, RepnType,
            !Info, !Specs),
        qualify_inst(InInt, ErrorContext, GroundInst0, GroundInst,
            !Info, !Specs),
        qualify_inst(InInt, ErrorContext, AnyInst0, AnyInst,
            !Info, !Specs),
        qualify_constraint_stores(InInt, MutableItems0, MutableItems,
            !Info, !Specs),
        SolverTypeDetails  = solver_type_details(RepnType, InitPred,
            GroundInst, AnyInst, MutableItems),
        TypeDefn = parse_tree_solver_type(SolverTypeDetails,
            MaybeUserEqComp)
    ).

:- pred qualify_constraint_stores(mq_in_interface::in,
    list(item_mutable_info)::in, list(item_mutable_info)::out,
    mq_info::in, mq_info::out,
    list(error_spec)::in, list(error_spec)::out) is det.

qualify_constraint_stores(_InInt, [], [], !Info, !Specs).
qualify_constraint_stores(InInt,
        [Mutable0 | Mutables0], [Mutable | Mutables], !Info, !Specs) :-
    qualify_mutable(InInt, Mutable0, Mutable, !Info, !Specs),
    qualify_constraint_stores(InInt, Mutables0, Mutables, !Info, !Specs).

:- pred qualify_constructors(mq_in_interface::in, type_ctor::in,
    list(constructor)::in, list(constructor)::out,
    mq_info::in, mq_info::out,
    list(error_spec)::in, list(error_spec)::out) is det.

qualify_constructors(_InInt, _ContainingTypeCtor, [], [], !Info, !Specs).
qualify_constructors(InInt, ContainingTypeCtor,
        [Ctor0 | Ctors0], [Ctor | Ctors], !Info, !Specs) :-
    qualify_constructor(InInt, ContainingTypeCtor, Ctor0, Ctor,
        !Info, !Specs),
    qualify_constructors(InInt, ContainingTypeCtor, Ctors0, Ctors,
        !Info, !Specs).

:- pred qualify_constructor(mq_in_interface::in, type_ctor::in,
    constructor::in, constructor::out,
    mq_info::in, mq_info::out,
    list(error_spec)::in, list(error_spec)::out) is det.

qualify_constructor(InInt, ContainingTypeCtor, Ctor0, Ctor, !Info, !Specs) :-
    Ctor0 = ctor(ExistQVars, Constraints0, FunctionSymbolSymName, Args0,
        Arity, Context),
    FunctionSymbolName = unqualify_name(FunctionSymbolSymName),
    ConstraintErrorContext = mqcec_type_defn_constructor(Context,
        ContainingTypeCtor, FunctionSymbolName),
    qualify_prog_constraint_list(InInt, ConstraintErrorContext,
        Constraints0, Constraints, !Info, !Specs),
    qualify_constructor_args(InInt, ContainingTypeCtor, FunctionSymbolName,
        0, Args0, Args, !Info, !Specs),
    Ctor = ctor(ExistQVars, Constraints, FunctionSymbolSymName, Args,
        Arity, Context).

:- pred qualify_constructor_args(mq_in_interface::in,
    type_ctor::in, string::in, int::in,
    list(constructor_arg)::in, list(constructor_arg)::out,
    mq_info::in, mq_info::out,
    list(error_spec)::in, list(error_spec)::out) is det.

qualify_constructor_args(_InInt, _, _, _, [], [], !Info, !Specs).
qualify_constructor_args(InInt, ContainingTypeCtor, FunctionSymbol,
        LastArgNum, [Arg0 | Args0], [Arg | Args], !Info, !Specs) :-
    CurArgNum = LastArgNum + 1,
    qualify_constructor_arg(InInt, ContainingTypeCtor, FunctionSymbol,
        CurArgNum, Arg0, Arg, !Info, !Specs),
    qualify_constructor_args(InInt, ContainingTypeCtor, FunctionSymbol,
        CurArgNum, Args0, Args, !Info, !Specs).

:- pred qualify_constructor_arg(mq_in_interface::in,
    type_ctor::in, string::in, int::in,
    constructor_arg::in, constructor_arg::out, mq_info::in, mq_info::out,
    list(error_spec)::in, list(error_spec)::out) is det.

qualify_constructor_arg(InInt, ContainingTypeCtor, FunctionSymbol, ArgNum,
        Arg0, Arg, !Info, !Specs) :-
    Arg0 = ctor_arg(MaybeFieldName, Type0, Width, Context),
    ErrorContext = mqec_constructor_arg(Context, ContainingTypeCtor,
        FunctionSymbol, ArgNum, MaybeFieldName),
    qualify_type(InInt, ErrorContext, Type0, Type, !Info, !Specs),
    Arg = ctor_arg(MaybeFieldName, Type, Width, Context).

:- pred qualify_type_list(mq_in_interface::in, mq_error_context::in,
    list(mer_type)::in, list(mer_type)::out, mq_info::in, mq_info::out,
    list(error_spec)::in, list(error_spec)::out) is det.

qualify_type_list(_InInt, _ErrorContext, [], [], !Info, !Specs).
qualify_type_list(InInt, ErrorContext, [Type0 | Types0], [Type | Types],
        !Info, !Specs) :-
    qualify_type(InInt, ErrorContext, Type0, Type, !Info, !Specs),
    qualify_type_list(InInt, ErrorContext, Types0, Types, !Info, !Specs).

:- pred qualify_maybe_type(mq_in_interface::in, mq_error_context::in,
    maybe(mer_type)::in, maybe(mer_type)::out, mq_info::in, mq_info::out,
    list(error_spec)::in, list(error_spec)::out) is det.

qualify_maybe_type(_InInt, _ErrorContext, no, no, !Info, !Specs).
qualify_maybe_type(InInt, ErrorContext, yes(Type0), yes(Type),
        !Info, !Specs) :-
    qualify_type(InInt, ErrorContext, Type0, Type, !Info, !Specs).

    % Qualify a type and its argument types.
    %
:- pred qualify_type(mq_in_interface::in, mq_error_context::in,
    mer_type::in, mer_type::out, mq_info::in, mq_info::out,
    list(error_spec)::in, list(error_spec)::out) is det.

qualify_type(InInt, ErrorContext, Type0, Type, !Info, !Specs) :-
    (
        Type0 = type_variable(_Var, _Kind),
        Type = Type0
    ;
        Type0 = defined_type(SymName0, Args0, Kind),
        Arity = list.length(Args0),
        TypeCtorId0 = mq_id(SymName0, Arity),
        mq_info_get_types(!.Info, Types),
        find_unique_match(InInt, ErrorContext, Types, type_id,
            TypeCtorId0, SymName, !Info, !Specs),
        % XXX We could pass a more specific error context.
        qualify_type_list(InInt, ErrorContext, Args0, Args, !Info, !Specs),
        Type = defined_type(SymName, Args, Kind)
    ;
        Type0 = builtin_type(BuiltinType),
        % The types `int', `float', and `string' are builtin types,
        % defined by the compiler, but arguably they ought to be defined
        % in int.m, float.m, and string.m, and so if someone uses the type
        % `int' in the interface, then we don't want to warn about
        % `import_module int' in the interface. We don't do the same for
        % `character', since the corresponding library module `char'
        % will be flagged as used in the interface if the type `char' is used.
        (
            BuiltinType = builtin_type_int,
            mq_info_set_module_used(InInt, unqualified("int"), !Info)
        ;
            BuiltinType = builtin_type_float,
            mq_info_set_module_used(InInt, unqualified("float"), !Info)
        ;
            BuiltinType = builtin_type_string,
            mq_info_set_module_used(InInt, unqualified("string"), !Info)
        ;
            BuiltinType = builtin_type_char
        ),
        Type = Type0
    ;
        Type0 = higher_order_type(Args0, MaybeRet0, Purity, EvalMethod),
        % XXX We could pass a more specific error context.
        qualify_type_list(InInt, ErrorContext, Args0, Args, !Info, !Specs),
        % XXX We could pass a more specific error context.
        qualify_maybe_type(InInt, ErrorContext, MaybeRet0, MaybeRet,
            !Info, !Specs),
        Type = higher_order_type(Args, MaybeRet, Purity, EvalMethod)
    ;
        Type0 = tuple_type(Args0, Kind),
        % XXX We could pass a more specific error context.
        qualify_type_list(InInt, ErrorContext, Args0, Args, !Info, !Specs),
        Type = tuple_type(Args, Kind)
    ;
        Type0 = apply_n_type(Var, Args0, Kind),
        % XXX We could pass a more specific error context.
        qualify_type_list(InInt, ErrorContext, Args0, Args, !Info, !Specs),
        Type = apply_n_type(Var, Args, Kind)
    ;
        Type0 = kinded_type(SubType0, Kind),
        % XXX We could pass a more specific error context.
        qualify_type(InInt, ErrorContext, SubType0, SubType, !Info, !Specs),
        Type = kinded_type(SubType, Kind)
    ).

:- pred qualify_type_ctor(mq_in_interface::in, mq_error_context::in,
    type_ctor::in, type_ctor::out, mq_info::in, mq_info::out,
    list(error_spec)::in, list(error_spec)::out) is det.

qualify_type_ctor(InInt, ErrorContext, TypeCtor0, TypeCtor,
        !Info, !Specs) :-
    TypeCtor0 = type_ctor(SymName0, Arity),
    ( if is_builtin_atomic_type(TypeCtor0) then
        SymName = SymName0
    else
        TypeCtorId0 = mq_id(SymName0, Arity),
        mq_info_get_types(!.Info, Types),
        % XXX We could pass a more specific error context.
        find_unique_match(InInt, ErrorContext, Types, type_id,
            TypeCtorId0, SymName, !Info, !Specs)
    ),
    TypeCtor = type_ctor(SymName, Arity).

    % is_builtin_atomic_type(TypeCtor):
    %
    % Succeeds iff 'TypeCtor' is the type_ctor of a builtin atomic type.
    %
:- pred is_builtin_atomic_type(type_ctor::in) is semidet.

is_builtin_atomic_type(type_ctor(unqualified("int"), 0)).
is_builtin_atomic_type(type_ctor(unqualified("float"), 0)).
is_builtin_atomic_type(type_ctor(unqualified("string"), 0)).
is_builtin_atomic_type(type_ctor(unqualified("character"), 0)).

%---------------------------------------------------------------------------%
%
% Module qualify inst definitions and insts.
%

    % Qualify the inst parameters of an inst definition.
    %
:- pred qualify_inst_defn(mq_in_interface::in, mq_error_context::in,
    inst_defn::in, inst_defn::out, mq_info::in, mq_info::out,
    list(error_spec)::in, list(error_spec)::out) is det.

qualify_inst_defn(InInt, ErrorContext, InstDefn0, InstDefn,
        !Info, !Specs) :-
    (
        InstDefn0 = eqv_inst(Inst0),
        qualify_inst(InInt, ErrorContext, Inst0, Inst, !Info, !Specs),
        InstDefn = eqv_inst(Inst)
    ;
        InstDefn0 = abstract_inst,
        InstDefn = abstract_inst
    ).

    % Qualify a single inst.
    %
:- pred qualify_inst(mq_in_interface::in, mq_error_context::in,
    mer_inst::in, mer_inst::out, mq_info::in, mq_info::out,
    list(error_spec)::in, list(error_spec)::out) is det.

qualify_inst(InInt, ErrorContext, Inst0, Inst, !Info, !Specs) :-
    (
        Inst0 = any(Uniq, HOInstInfo0),
        qualify_ho_inst_info(InInt, ErrorContext, HOInstInfo0, HOInstInfo,
            !Info, !Specs),
        Inst = any(Uniq, HOInstInfo)
    ;
        ( Inst0 = free
        ; Inst0 = not_reached
        ; Inst0 = inst_var(_)
        ),
        Inst = Inst0
    ;
        Inst0 = free(_),
        unexpected($module, $pred, "compiler generated inst not expected")
    ;
        Inst0 = bound(Uniq, InstResults0, BoundInsts0),
        (
            ( InstResults0 = inst_test_results_fgtc
            ; InstResults0 = inst_test_no_results
            )
        ;
            InstResults0 = inst_test_results(_, _, _, _, _, _),
            unexpected($module, $pred, "compiler generated inst not expected")
        ),
        % XXX We could pass a more specific error context.
        qualify_bound_insts(InInt, ErrorContext, BoundInsts0, BoundInsts,
            !Info, !Specs),
        Inst = bound(Uniq, InstResults0, BoundInsts)
    ;
        Inst0 = ground(Uniq, HOInstInfo0),
        % XXX We could pass a more specific error context.
        qualify_ho_inst_info(InInt, ErrorContext, HOInstInfo0, HOInstInfo,
            !Info, !Specs),
        Inst = ground(Uniq, HOInstInfo)
    ;
        Inst0 = constrained_inst_vars(Vars, SubInst0),
        % XXX We could pass a more specific error context.
        qualify_inst(InInt, ErrorContext, SubInst0, SubInst, !Info, !Specs),
        Inst = constrained_inst_vars(Vars, SubInst)
    ;
        Inst0 = defined_inst(InstName0),
        % XXX We could pass a more specific error context.
        qualify_inst_name(InInt, ErrorContext, InstName0, InstName,
            !Info, !Specs),
        Inst = defined_inst(InstName)
    ;
        Inst0 = abstract_inst(Name, Args0),
        % XXX We could pass a more specific error context.
        qualify_inst_list(InInt, ErrorContext, Args0, Args, !Info, !Specs),
        Inst = abstract_inst(Name, Args)
    ).

:- pred qualify_inst_list(mq_in_interface::in, mq_error_context::in,
    list(mer_inst)::in, list(mer_inst)::out, mq_info::in, mq_info::out,
    list(error_spec)::in, list(error_spec)::out) is det.

qualify_inst_list(_InInt, _ErrorContext, [], [], !Info, !Specs).
qualify_inst_list(InInt, ErrorContext, [Inst0 | Insts0], [Inst | Insts],
        !Info, !Specs) :-
    qualify_inst(InInt, ErrorContext, Inst0, Inst, !Info, !Specs),
    qualify_inst_list(InInt, ErrorContext, Insts0, Insts, !Info, !Specs).

:- pred qualify_ho_inst_info(mq_in_interface::in, mq_error_context::in,
    ho_inst_info::in, ho_inst_info::out, mq_info::in, mq_info::out,
    list(error_spec)::in, list(error_spec)::out) is det.

qualify_ho_inst_info(InInt, ErrorContext, HOInstInfo0, HOInstInfo,
        !Info, !Specs) :-
    (
        HOInstInfo0 = higher_order(pred_inst_info(PredOrFunc, Modes0,
            MaybeArgRegs, Detism)),
        qualify_mode_list(InInt, ErrorContext, Modes0, Modes, !Info, !Specs),
        HOInstInfo = higher_order(pred_inst_info(PredOrFunc, Modes,
            MaybeArgRegs, Detism))
    ;
        HOInstInfo0 = none,
        HOInstInfo = none
    ).

    % Find the unique inst_id that matches this inst, and qualify
    % the argument insts.
    %
:- pred qualify_inst_name(mq_in_interface::in, mq_error_context::in,
    inst_name::in, inst_name::out, mq_info::in, mq_info::out,
    list(error_spec)::in, list(error_spec)::out) is det.

qualify_inst_name(InInt, ErrorContext, InstName0, InstName,
        !Info, !Specs) :-
    (
        InstName0 = user_inst(SymName0, Insts0),
        qualify_inst_list(InInt, ErrorContext, Insts0, Insts,
            !Info, !Specs),
        ( if
            % Check for a variable inst constructor.
            SymName0 = unqualified("")
        then
            report_invalid_user_inst(SymName0, Insts, ErrorContext, !Specs),
            mq_info_set_found_undef_inst(!Info),
            SymName = SymName0
        else
            list.length(Insts0, Arity),
            mq_info_get_insts(!.Info, InstIdSet),
            find_unique_match(InInt, ErrorContext, InstIdSet, inst_id,
                mq_id(SymName0, Arity), SymName, !Info, !Specs)
        ),
        InstName = user_inst(SymName, Insts)
    ;
        ( InstName0 = unify_inst(_, _, _, _)
        ; InstName0 = merge_inst(_, _)
        ; InstName0 = ground_inst(_, _, _, _)
        ; InstName0 = any_inst(_, _, _, _)
        ; InstName0 = shared_inst(_)
        ; InstName0 = mostly_uniq_inst(_)
        ; InstName0 = typed_ground(_, _)
        ; InstName0 = typed_inst(_, _)
        ),
        unexpected($module, $pred, "unexpected compiler generated inst_name")
    ).

:- pred qualify_bound_insts(mq_in_interface::in, mq_error_context::in,
    list(bound_inst)::in, list(bound_inst)::out, mq_info::in, mq_info::out,
    list(error_spec)::in, list(error_spec)::out) is det.

qualify_bound_insts(_InInt, _ErrorContext, [], [], !Info, !Specs).
qualify_bound_insts(InInt, ErrorContext,
        [BoundInst0 | BoundInsts0], [BoundInst | BoundInsts],
        !Info, !Specs) :-
    qualify_bound_inst(InInt, ErrorContext, BoundInst0, BoundInst,
        !Info, !Specs),
    qualify_bound_insts(InInt, ErrorContext, BoundInsts0, BoundInsts,
        !Info, !Specs).

    % Qualify an inst of the form bound(functor(...)).
    %
:- pred qualify_bound_inst(mq_in_interface::in, mq_error_context::in,
    bound_inst::in, bound_inst::out, mq_info::in, mq_info::out,
    list(error_spec)::in, list(error_spec)::out) is det.

qualify_bound_inst(InInt, ErrorContext, BoundInst0, BoundInst,
        !Info, !Specs) :-
    BoundInst0 = bound_functor(ConsId, Insts0),
    (
        ConsId = cons(Name, Arity, _),
        Id = item_name(Name, Arity),
        update_recompilation_info(
            recompilation.record_used_item(functor_item, Id, Id), !Info)
    ;
        ( ConsId = tuple_cons(_)
        ; ConsId = closure_cons(_, _)
        ; ConsId = int_const(_)
        ; ConsId = float_const(_)
        ; ConsId = char_const(_)
        ; ConsId = string_const(_)
        ; ConsId = impl_defined_const(_)
        ; ConsId = type_ctor_info_const(_, _, _)
        ; ConsId = base_typeclass_info_const(_, _, _, _)
        ; ConsId = type_info_cell_constructor(_)
        ; ConsId = typeclass_info_cell_constructor
        ; ConsId = type_info_const(_)
        ; ConsId = typeclass_info_const(_)
        ; ConsId = ground_term_const(_, _)
        ; ConsId = tabling_info_const(_)
        ; ConsId = table_io_entry_desc(_)
        ; ConsId = deep_profiling_proc_layout(_)
        )
    ),
    qualify_inst_list(InInt, ErrorContext, Insts0, Insts, !Info, !Specs),
    BoundInst = bound_functor(ConsId, Insts).

%---------------------------------------------------------------------------%
%
% Module qualify mode definitions and modes.
%

    % Qualify the mode parameter of an equivalence mode definition.
    %
:- pred qualify_mode_defn(mq_in_interface::in, mq_error_context::in,
    mode_defn::in, mode_defn::out, mq_info::in, mq_info::out,
    list(error_spec)::in, list(error_spec)::out) is det.

qualify_mode_defn(InInt, ErrorContext, eqv_mode(Mode0), eqv_mode(Mode),
        !Info, !Specs) :-
    qualify_mode(InInt, ErrorContext, Mode0, Mode, !Info, !Specs).

:- pred qualify_mode(mq_in_interface::in, mq_error_context::in,
    mer_mode::in, mer_mode::out, mq_info::in, mq_info::out,
    list(error_spec)::in, list(error_spec)::out) is det.

qualify_mode(InInt, ErrorContext, Mode0, Mode, !Info, !Specs) :-
    (
        Mode0 = (InstA0 -> InstB0),
        qualify_inst(InInt, ErrorContext, InstA0, InstA, !Info, !Specs),
        qualify_inst(InInt, ErrorContext, InstB0, InstB, !Info, !Specs),
        Mode = (InstA -> InstB)
    ;
        Mode0 = user_defined_mode(SymName0, Insts0),
        qualify_inst_list(InInt, ErrorContext, Insts0, Insts,
            !Info, !Specs),
        list.length(Insts, Arity),
        mq_info_get_modes(!.Info, Modes),
        find_unique_match(InInt, ErrorContext, Modes, mode_id,
            mq_id(SymName0, Arity), SymName, !Info, !Specs),
        Mode = user_defined_mode(SymName, Insts)
    ).

:- pred qualify_mode_list(mq_in_interface::in, mq_error_context::in,
    list(mer_mode)::in, list(mer_mode)::out, mq_info::in, mq_info::out,
    list(error_spec)::in, list(error_spec)::out) is det.

qualify_mode_list(_InInt, _ErrorContext, [], [], !Info, !Specs).
qualify_mode_list(InInt, ErrorContext, [Mode0 | Modes0], [Mode | Modes],
        !Info, !Specs) :-
    qualify_mode(InInt, ErrorContext, Mode0, Mode, !Info, !Specs),
    qualify_mode_list(InInt, ErrorContext, Modes0, Modes, !Info, !Specs).

%---------------------------------------------------------------------------%
%
% Module qualify the components of predicate declarations.
%

    % Qualify a list of items of the form Type::Mode, as in a
    % predicate declaration.
    %
:- pred qualify_types_and_modes(mq_in_interface::in, mq_error_context::in,
    list(type_and_mode)::in, list(type_and_mode)::out,
    mq_info::in, mq_info::out,
    list(error_spec)::in, list(error_spec)::out) is det.

qualify_types_and_modes(_InInt, _ErrorContext, [], [], !Info, !Specs).
qualify_types_and_modes(InInt, ErrorContext,
        [TypeAndMode0 | TypesAndModes0], [TypeAndMode | TypesAndModes],
        !Info, !Specs) :-
    qualify_type_and_mode(InInt, ErrorContext,
        TypeAndMode0, TypeAndMode, !Info, !Specs),
    qualify_types_and_modes(InInt, ErrorContext,
        TypesAndModes0, TypesAndModes, !Info, !Specs).

:- pred qualify_type_and_mode(mq_in_interface::in, mq_error_context::in,
    type_and_mode::in, type_and_mode::out, mq_info::in, mq_info::out,
    list(error_spec)::in, list(error_spec)::out) is det.

qualify_type_and_mode(InInt, ErrorContext, TypeAndMode0, TypeAndMode,
        !Info, !Specs) :-
    (
        TypeAndMode0 = type_only(Type0),
        qualify_type(InInt, ErrorContext, Type0, Type, !Info, !Specs),
        TypeAndMode = type_only(Type)
    ;
        TypeAndMode0 = type_and_mode(Type0, Mode0),
        qualify_type(InInt, ErrorContext, Type0, Type, !Info, !Specs),
        qualify_mode(InInt, ErrorContext, Mode0, Mode, !Info, !Specs),
        TypeAndMode = type_and_mode(Type, Mode)
    ).

%---------------------------------------------------------------------------%
%
% Module qualify the components of typeclass declarations and typeclass
% constraints.
%

:- pred qualify_prog_constraints(mq_in_interface::in,
    mq_constraint_error_context::in,
    prog_constraints::in, prog_constraints::out, mq_info::in, mq_info::out,
    list(error_spec)::in, list(error_spec)::out) is det.

qualify_prog_constraints(InInt, ConstraintErrorContext,
        Constraints0, Constraints, !Info, !Specs) :-
    Constraints0 = constraints(UnivCs0, ExistCs0),
    % XXX We could pass a more specific error context.
    qualify_prog_constraint_list(InInt, ConstraintErrorContext,
        UnivCs0, UnivCs, !Info, !Specs),
    qualify_prog_constraint_list(InInt, ConstraintErrorContext,
        ExistCs0, ExistCs, !Info, !Specs),
    Constraints = constraints(UnivCs, ExistCs).

:- pred qualify_prog_constraint_list(mq_in_interface::in,
    mq_constraint_error_context::in,
    list(prog_constraint)::in, list(prog_constraint)::out,
    mq_info::in, mq_info::out,
    list(error_spec)::in, list(error_spec)::out) is det.

qualify_prog_constraint_list(_InInt, _ConstraintErrorContext,
        [], [], !Info, !Specs).
qualify_prog_constraint_list(InInt, ConstraintErrorContext,
        [Constraint0 | Constraints0], [Constraint | Constraints],
        !Info, !Specs) :-
    qualify_prog_constraint(InInt, ConstraintErrorContext,
        Constraint0, Constraint, !Info, !Specs),
    qualify_prog_constraint_list(InInt, ConstraintErrorContext,
        Constraints0, Constraints, !Info, !Specs).

:- pred qualify_prog_constraint(mq_in_interface::in,
    mq_constraint_error_context::in,
    prog_constraint::in, prog_constraint::out, mq_info::in, mq_info::out,
    list(error_spec)::in, list(error_spec)::out) is det.

qualify_prog_constraint(InInt, ContainingErrorContext,
        Constraint0, Constraint, !Info, !Specs) :-
    Constraint0 = constraint(ClassName0, Types0),
    list.length(Types0, Arity),
    OutsideContext = mqec_typeclass_constraint_name(ContainingErrorContext),
    qualify_class_name(InInt, OutsideContext,
        mq_id(ClassName0, Arity), ClassName, !Info, !Specs),
    ErrorContext = mqec_typeclass_constraint(ClassName0, Arity,
        ContainingErrorContext),
    qualify_type_list(InInt, ErrorContext, Types0, Types, !Info, !Specs),
    Constraint = constraint(ClassName, Types).

:- pred qualify_class_name(mq_in_interface::in, mq_error_context::in,
    mq_id::in, sym_name::out, mq_info::in, mq_info::out,
    list(error_spec)::in, list(error_spec)::out) is det.

qualify_class_name(InInt, ErrorContext, Class0, Name, !Info, !Specs) :-
    mq_info_get_classes(!.Info, ClassIdSet),
    find_unique_match(InInt, ErrorContext, ClassIdSet, class_id, Class0, Name,
        !Info, !Specs).

%---------------------%

:- pred qualify_class_methods(mq_in_interface::in, mq_error_context::in,
    list(class_method)::in, list(class_method)::out,
    mq_info::in, mq_info::out,
    list(error_spec)::in, list(error_spec)::out) is det.

qualify_class_methods(_InInt, _ErrorContext, [], [], !Info, !Specs).
qualify_class_methods(InInt, ErrorContext,
        [Method0 | Methods0], [Method | Methods], !Info, !Specs) :-
    % XXX We could pass a more specific error context.
    qualify_class_method(InInt, ErrorContext, Method0, Method,
        !Info, !Specs),
    qualify_class_methods(InInt, ErrorContext, Methods0, Methods,
        !Info, !Specs).

:- pred qualify_class_method(mq_in_interface::in, mq_error_context::in,
    class_method::in, class_method::out, mq_info::in, mq_info::out,
    list(error_spec)::in, list(error_spec)::out) is det.

qualify_class_method(InInt, ErrorContext, Method0, Method, !Info, !Specs) :-
    % There is no need to qualify the method name, since that is done
    % when the item is parsed.
    (
        Method0 = method_pred_or_func(Name, PredOrFunc, TypesAndModes0,
            MaybeWithType0, MaybeWithInst0, MaybeDetism,
            TypeVarset, InstVarset, ExistQVars,
            Purity, Constraints0, Context),
        % XXX We could pass a more specific error context.
        qualify_types_and_modes(InInt, ErrorContext,
            TypesAndModes0, TypesAndModes, !Info, !Specs),
        ConstraintErrorContext = mqcec_class_method(Context, PredOrFunc,
            unqualify_name(Name)),
        qualify_prog_constraints(InInt, ConstraintErrorContext,
            Constraints0, Constraints, !Info, !Specs),
        (
            MaybeWithType0 = yes(WithType0),
            % XXX We could pass a more specific error context.
            qualify_type(InInt, ErrorContext, WithType0, WithType,
                !Info, !Specs),
            MaybeWithType = yes(WithType)
        ;
            MaybeWithType0 = no,
            MaybeWithType = no
        ),
        (
            MaybeWithInst0 = yes(WithInst0),
            % XXX We could pass a more specific error context.
            qualify_inst(InInt, ErrorContext, WithInst0, WithInst,
                !Info, !Specs),
            MaybeWithInst = yes(WithInst)
        ;
            MaybeWithInst0 = no,
            MaybeWithInst = no
        ),
        Method = method_pred_or_func(Name, PredOrFunc, TypesAndModes,
            MaybeWithType, MaybeWithInst, MaybeDetism,
            TypeVarset, InstVarset, ExistQVars,
            Purity, Constraints, Context)
    ;
        Method0 = method_pred_or_func_mode(PredOrFunc, Name, Modes0,
            MaybeWithInst0, MaybeDetism, Varset, Context),
        qualify_mode_list(InInt, ErrorContext, Modes0, Modes, !Info, !Specs),
        (
            MaybeWithInst0 = yes(WithInst0),
            % XXX We could pass a more specific error context.
            qualify_inst(InInt, ErrorContext, WithInst0, WithInst,
                !Info, !Specs),
            MaybeWithInst = yes(WithInst)
        ;
            MaybeWithInst0 = no,
            MaybeWithInst = no
        ),
        Method = method_pred_or_func_mode(PredOrFunc, Name, Modes,
            MaybeWithInst, MaybeDetism, Varset, Context)
    ).

%---------------------------------------------------------------------------%
%
% Module qualify instance definitions.
%

:- pred qualify_instance_body(sym_name::in,
    instance_body::in, instance_body::out) is det.

qualify_instance_body(ClassName, InstanceBody0, InstanceBody) :-
    (
        InstanceBody0 = instance_body_abstract,
        InstanceBody = instance_body_abstract
    ;
        InstanceBody0 = instance_body_concrete(Methods0),
        (
            ClassName = unqualified(_),
            InstanceBody = InstanceBody0
        ;
            ClassName = qualified(_, _),
            sym_name_get_module_name_default(ClassName, unqualified(""),
                DefaultModuleName),
            list.map(qualify_instance_method(DefaultModuleName),
                Methods0, Methods),
            InstanceBody = instance_body_concrete(Methods)
        )
    ).

:- pred qualify_instance_method(module_name::in,
    instance_method::in, instance_method::out) is det.

qualify_instance_method(DefaultModuleName, InstanceMethod0, InstanceMethod) :-
    % XXX InstanceProcDef may contain a list of clauses.
    % Why aren't those clauses module qualified?
    InstanceMethod0 = instance_method(PredOrFunc, MethodSymName0,
        InstanceProcDef, Arity, DeclContext),
    (
        MethodSymName0 = unqualified(Name),
        MethodSymName = qualified(DefaultModuleName, Name)
    ;
        MethodSymName0 = qualified(MethodModuleName, MethodBaseName),
        ( if
            partial_sym_name_matches_full(MethodModuleName, DefaultModuleName)
        then
            MethodSymName = qualified(DefaultModuleName, MethodBaseName)
        else
            % This case is an error. The user must have written something like
            %   :- instance foo.bar(some_type) where [
            %       pred(baz.p/1) is q
            %   ].
            % where the module qualifier on the pred or func in the instance
            % (baz) does not match the qualifier for the class name (foo).
            %
            % We don't report the error here, we just leave the original
            % module qualifier intact so that the error can be reported
            % later on. XXX Where is the code that does this reporting?
            MethodSymName = MethodSymName0
        )
    ),
    InstanceMethod = instance_method(PredOrFunc, MethodSymName,
        InstanceProcDef, Arity, DeclContext).

%---------------------------------------------------------------------------%
%
% Module qualify the definitions of mutables.
%

:- pred qualify_mutable(mq_in_interface::in,
    item_mutable_info::in, item_mutable_info::out, mq_info::in, mq_info::out,
    list(error_spec)::in, list(error_spec)::out) is det.

qualify_mutable(InInt, ItemMutable0, ItemMutable, !Info, !Specs) :-
    ItemMutable0 = item_mutable_info(Name, OrigType0, Type0, OrigInst0, Inst0,
        InitTerm, Attrs, Varset, Context, SeqNum),
    ErrorContext = mqec_mutable(Context, Name),
    qualify_type(InInt, ErrorContext, OrigType0, OrigType, !Info, [], _),
    qualify_type(InInt, ErrorContext, Type0, Type, !Info, !Specs),
    qualify_inst(InInt, ErrorContext, OrigInst0, OrigInst, !Info, [], _),
    qualify_inst(InInt, ErrorContext, Inst0, Inst, !Info, !Specs),
    ItemMutable = item_mutable_info(Name, OrigType, Type, OrigInst, Inst,
        InitTerm, Attrs, Varset, Context, SeqNum).

%---------------------------------------------------------------------------%
%
% Module qualify pragmas.
%

:- pred qualify_pragma(mq_in_interface::in, prog_context::in,
    pragma_type::in, pragma_type::out, mq_info::in, mq_info::out,
    list(error_spec)::in, list(error_spec)::out) is det.

qualify_pragma(InInt, Context, Pragma0, Pragma, !Info, !Specs) :-
    (
        ( Pragma0 = pragma_foreign_decl(_)
        ; Pragma0 = pragma_foreign_code(_)
        ; Pragma0 = pragma_foreign_import_module(_)
        ; Pragma0 = pragma_external_proc(_)
          % The predicate name in the pragma_external_proc is constructed
          % already qualified.
        ; Pragma0 = pragma_inline(_)
        ; Pragma0 = pragma_no_inline(_)
        ; Pragma0 = pragma_obsolete(_)
        ; Pragma0 = pragma_no_detism_warning(_)
        ; Pragma0 = pragma_unused_args(_)
        ; Pragma0 = pragma_exceptions(_)
        ; Pragma0 = pragma_trailing_info(_)
        ; Pragma0 = pragma_mm_tabling_info(_)
        ; Pragma0 = pragma_fact_table(_)
        ; Pragma0 = pragma_promise_pure(_)
        ; Pragma0 = pragma_promise_semipure(_)
        ; Pragma0 = pragma_promise_eqv_clauses(_)
        ; Pragma0 = pragma_terminates(_)
        ; Pragma0 = pragma_does_not_terminate(_)
        ; Pragma0 = pragma_check_termination(_)
        ; Pragma0 = pragma_mode_check_clauses(_)
        ; Pragma0 = pragma_require_feature_set(_)
        ),
        Pragma = Pragma0
    ;
        Pragma0 = pragma_reserve_tag(_TypeCtor0),
        % XXX We should be module qualifying TypeCtor0 here,
        % not in add_pragma.m. However, the code in add_pragma.m
        % does generate better error messages than qualify_type_ctor does;
        % this implies we should fix qualify_type_ctor.
        Pragma = Pragma0
    ;
        Pragma0 = pragma_foreign_export_enum(FEEInfo0),
        FEEInfo0 = pragma_info_foreign_export_enum(Lang, TypeCtor0,
            Attributes, Overrides),
        ErrorContext = mqec_pragma(Context, Pragma0),
        qualify_type_ctor(InInt, ErrorContext, TypeCtor0, TypeCtor,
            !Info, !Specs),
        FEEInfo = pragma_info_foreign_export_enum(Lang, TypeCtor,
            Attributes, Overrides),
        Pragma = pragma_foreign_export_enum(FEEInfo)
    ;
        Pragma0 = pragma_foreign_enum(FEInfo0),
        FEInfo0 = pragma_info_foreign_enum(Lang, TypeCtor0, Values),
        ErrorContext = mqec_pragma(Context, Pragma0),
        qualify_type_ctor(InInt, ErrorContext, TypeCtor0, TypeCtor,
            !Info, !Specs),
        FEInfo = pragma_info_foreign_enum(Lang, TypeCtor, Values),
        Pragma = pragma_foreign_enum(FEInfo)
    ;
        Pragma0 = pragma_foreign_proc(FPInfo0),
        FPInfo0 = pragma_info_foreign_proc(Attrs0, Name, PredOrFunc,
            Vars0, Varset, InstVarset, Impl),
        ErrorContext = mqec_pragma(Context, Pragma0),
        qualify_pragma_vars(InInt, ErrorContext, Vars0, Vars, !Info, !Specs),
        UserSharing0 = get_user_annotated_sharing(Attrs0),
        qualify_user_sharing(InInt, ErrorContext, UserSharing0, UserSharing,
            !Info, !Specs),
        set_user_annotated_sharing(UserSharing, Attrs0, Attrs),
        FPInfo = pragma_info_foreign_proc(Attrs, Name, PredOrFunc,
            Vars, Varset, InstVarset, Impl),
        Pragma = pragma_foreign_proc(FPInfo)
    ;
        Pragma0 = pragma_oisu(OISUInfo0),
        OISUInfo0 = pragma_info_oisu(TypeCtor0, CreatorPreds,
            MutatorPreds, DestructorPreds),
        % XXX Preds
        ErrorContext = mqec_pragma(Context, Pragma0),
        qualify_type_ctor(InInt, ErrorContext, TypeCtor0, TypeCtor,
            !Info, !Specs),
        OISUInfo = pragma_info_oisu(TypeCtor, CreatorPreds,
            MutatorPreds, DestructorPreds),
        Pragma = pragma_oisu(OISUInfo)
    ;
        Pragma0 = pragma_tabled(TabledInfo0),
        TabledInfo0 = pragma_info_tabled(EvalMethod, PredNameArityPF,
            MModes0, Attrs),
        (
            MModes0 = yes(Modes0),
            ErrorContext = mqec_pragma(Context, Pragma0),
            qualify_mode_list(InInt, ErrorContext, Modes0, Modes,
                !Info, !Specs),
            MModes = yes(Modes)
        ;
            MModes0 = no,
            MModes = no
        ),
        TabledInfo = pragma_info_tabled(EvalMethod, PredNameArityPF,
            MModes, Attrs),
        Pragma = pragma_tabled(TabledInfo)
    ;
        Pragma0 = pragma_foreign_proc_export(FPEInfo0),
        FPEInfo0 = pragma_info_foreign_proc_export(Lang, PredNameModesPF0,
            CFunc),
        PredNameModesPF0 = pred_name_modes_pf(Name, Modes0, PredOrFunc),
        ErrorContext = mqec_pragma(Context, Pragma0),
        qualify_mode_list(InInt, ErrorContext, Modes0, Modes,
            !Info, !Specs),
        PredNameModesPF = pred_name_modes_pf(Name, Modes, PredOrFunc),
        FPEInfo = pragma_info_foreign_proc_export(Lang, PredNameModesPF,
            CFunc),
        Pragma = pragma_foreign_proc_export(FPEInfo)
    ;
        Pragma0 = pragma_type_spec(TypeSpecInfo0),
        TypeSpecInfo0 = pragma_info_type_spec(PredName, SpecializedPredName,
            Arity, PredOrFunc, MaybeModes0, Subst0, TVarSet, Items),
        ErrorContext = mqec_pragma(Context, Pragma0),
        (
            MaybeModes0 = yes(Modes0),
            qualify_mode_list(InInt, ErrorContext, Modes0, Modes,
                !Info, !Specs),
            MaybeModes = yes(Modes)
        ;
            MaybeModes0 = no,
            MaybeModes = no
        ),
        qualify_type_spec_subst(InInt, ErrorContext, Subst0, Subst,
            !Info, !Specs),
        TypeSpecInfo = pragma_info_type_spec(PredName, SpecializedPredName,
            Arity, PredOrFunc, MaybeModes, Subst, TVarSet, Items),
        Pragma = pragma_type_spec(TypeSpecInfo)
    ;
        Pragma0 = pragma_termination_info(TermInfo0),
        TermInfo0 = pragma_info_termination_info(PredNameModesPF0, Args, Term),
        PredNameModesPF0 = pred_name_modes_pf(SymName, ModeList0, PredOrFunc),
        ErrorContext = mqec_pragma(Context, Pragma0),
        qualify_mode_list(InInt, ErrorContext, ModeList0, ModeList,
            !Info, !Specs),
        PredNameModesPF = pred_name_modes_pf(SymName, ModeList, PredOrFunc),
        TermInfo = pragma_info_termination_info(PredNameModesPF, Args, Term),
        Pragma = pragma_termination_info(TermInfo)
    ;
        Pragma0 = pragma_structure_sharing(SharingInfo0),
        SharingInfo0 = pragma_info_structure_sharing(PredNameModesPF0,
            Vars, Types, Sharing),
        PredNameModesPF0 = pred_name_modes_pf(SymName, ModeList0, PredOrFunc),
        ErrorContext = mqec_pragma(Context, Pragma0),
        qualify_mode_list(InInt, ErrorContext, ModeList0, ModeList,
            !Info, !Specs),
        PredNameModesPF = pred_name_modes_pf(SymName, ModeList, PredOrFunc),
        SharingInfo = pragma_info_structure_sharing(PredNameModesPF,
            Vars, Types, Sharing),
        Pragma = pragma_structure_sharing(SharingInfo)
    ;
        Pragma0 = pragma_structure_reuse(ReuseInfo0),
        ReuseInfo0 = pragma_info_structure_reuse(PredNameModesPF0,
            Vars, Types, ReuseTuples),
        PredNameModesPF0 = pred_name_modes_pf(SymName, ModeList0, PredOrFunc),
        ErrorContext = mqec_pragma(Context, Pragma0),
        qualify_mode_list(InInt, ErrorContext, ModeList0, ModeList,
            !Info, !Specs),
        PredNameModesPF = pred_name_modes_pf(SymName, ModeList, PredOrFunc),
        ReuseInfo = pragma_info_structure_reuse(PredNameModesPF,
            Vars, Types, ReuseTuples),
        Pragma = pragma_structure_reuse(ReuseInfo)
    ;
        Pragma0 = pragma_termination2_info(Term2Info0),
        Term2Info0 = pragma_info_termination2_info(PredNameModesPF0,
            SuccessArgs, FailureArgs, Term),
        PredNameModesPF0 = pred_name_modes_pf(SymName, ModeList0, PredOrFunc),
        ErrorContext = mqec_pragma(Context, Pragma0),
        qualify_mode_list(InInt, ErrorContext, ModeList0, ModeList,
            !Info, !Specs),
        PredNameModesPF = pred_name_modes_pf(SymName, ModeList, PredOrFunc),
        Term2Info = pragma_info_termination2_info(PredNameModesPF,
            SuccessArgs, FailureArgs, Term),
        Pragma = pragma_termination2_info(Term2Info)
    ).

:- pred qualify_pragma_vars(mq_in_interface::in, mq_error_context::in,
    list(pragma_var)::in, list(pragma_var)::out, mq_info::in, mq_info::out,
    list(error_spec)::in, list(error_spec)::out) is det.

qualify_pragma_vars(_InInt, _ErrorContext, [], [], !Info, !Specs).
qualify_pragma_vars(InInt, ErrorContext,
        [PragmaVar0 | PragmaVars0], [PragmaVar | PragmaVars], !Info, !Specs) :-
    % XXX We could pass a more specific error context.
    qualify_pragma_var(InInt, ErrorContext, PragmaVar0, PragmaVar,
        !Info, !Specs),
    qualify_pragma_vars(InInt, ErrorContext, PragmaVars0, PragmaVars,
        !Info, !Specs).

:- pred qualify_pragma_var(mq_in_interface::in, mq_error_context::in,
    pragma_var::in, pragma_var::out, mq_info::in, mq_info::out,
    list(error_spec)::in, list(error_spec)::out) is det.

qualify_pragma_var(InInt, ErrorContext, PragmaVar0, PragmaVar,
        !Info, !Specs) :-
    PragmaVar0 = pragma_var(Var, Name, Mode0, Box),
    % XXX We could pass a more specific error context.
    qualify_mode(InInt, ErrorContext, Mode0, Mode, !Info, !Specs),
    PragmaVar = pragma_var(Var, Name, Mode, Box).

:- pred qualify_type_spec_subst(mq_in_interface::in, mq_error_context::in,
    assoc_list(tvar, mer_type)::in, assoc_list(tvar, mer_type)::out,
    mq_info::in, mq_info::out,
    list(error_spec)::in, list(error_spec)::out) is det.

qualify_type_spec_subst(_InInt, _ErrorContext, [], [], !Info, !Specs).
qualify_type_spec_subst(InInt, ErrorContext,
        [Var - Type0 |  Subst0], [Var - Type | Subst], !Info, !Specs) :-
    % XXX We could pass a more specific error context.
    qualify_type(InInt, ErrorContext, Type0, Type, !Info, !Specs),
    qualify_type_spec_subst(InInt, ErrorContext, Subst0, Subst,
        !Info, !Specs).

:- pred qualify_user_sharing(mq_in_interface::in, mq_error_context::in,
    user_annotated_sharing::in, user_annotated_sharing::out,
    mq_info::in, mq_info::out,
    list(error_spec)::in, list(error_spec)::out) is det.

qualify_user_sharing(InInt, ErrorContext, UserSharing0, UserSharing,
        !Info, !Specs) :-
    (
        UserSharing0 = no_user_annotated_sharing,
        UserSharing = UserSharing0
    ;
        UserSharing0 = user_sharing(Sharing, MaybeTypes0),
        (
            MaybeTypes0 = yes(user_type_info(Types0, TVarset)),
            qualify_type_list(InInt, ErrorContext, Types0, Types,
                !Info, !Specs),
            MaybeTypes = yes(user_type_info(Types, TVarset)),
            UserSharing = user_sharing(Sharing, MaybeTypes)
        ;
            MaybeTypes0 = no,
            UserSharing = UserSharing0
        )
    ).

%---------------------------------------------------------------------------%
%
% Module qualify event specifications.
%

:- pred qualify_event_specs(mq_in_interface::in, string::in,
    assoc_list(string, event_spec)::in, assoc_list(string, event_spec)::out,
    mq_info::in, mq_info::out,
    list(error_spec)::in, list(error_spec)::out) is det.

qualify_event_specs(_InInt, _, [], [], !Info, !Specs).
qualify_event_specs(InInt, FileName,
        [Name - Spec0 | NameSpecs0], [Name - Spec | NameSpecs],
        !Info, !Specs) :-
    qualify_event_spec(InInt, FileName, Spec0, Spec, !Info, !Specs),
    qualify_event_specs(InInt, FileName, NameSpecs0, NameSpecs, !Info, !Specs).

:- pred qualify_event_spec(mq_in_interface::in, string::in,
    event_spec::in, event_spec::out, mq_info::in, mq_info::out,
    list(error_spec)::in, list(error_spec)::out) is det.

qualify_event_spec(InInt, FileName, EventSpec0, EventSpec,
        !Info, !Specs) :-
    EventSpec0 = event_spec(EventNumber, EventName, EventLineNumber,
        Attrs0, SynthAttrNumOrder),
    list.map_foldl2(
        qualify_event_attr(InInt, EventName, FileName, EventLineNumber),
        Attrs0, Attrs, !Info, !Specs),
    EventSpec = event_spec(EventNumber, EventName, EventLineNumber,
        Attrs, SynthAttrNumOrder).

:- pred qualify_event_attr(mq_in_interface::in,
    string::in, string::in, int::in,
    event_attribute::in, event_attribute::out, mq_info::in, mq_info::out,
    list(error_spec)::in, list(error_spec)::out) is det.

qualify_event_attr(InInt, EventName, FileName, LineNumber,
        Attr0, Attr, !Info, !Specs) :-
    Attr0 = event_attribute(AttrNum, AttrName, AttrType0, AttrMode0,
        MaybeSynthCall),
    Context = context(FileName, LineNumber),
    ErrorContext = mqec_event_spec_attr(Context, EventName, AttrName),
    qualify_type(InInt, ErrorContext, AttrType0, AttrType, !Info, !Specs),
    qualify_mode(InInt, ErrorContext, AttrMode0, AttrMode, !Info, !Specs),
    Attr = event_attribute(AttrNum, AttrName, AttrType, AttrMode,
        MaybeSynthCall).

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%
%
% Define a type for representing sets of ids during module qualification,
% to allow efficient retrieval of all the modules which define an id
% with a certain name and arity.
%

:- type id_type
    --->    type_id
    ;       mode_id
    ;       inst_id
    ;       class_id.

:- type mq_id
    --->    mq_id(sym_name, int).

:- type id_set == map(string, map(arity, permissions_map)).
:- type permissions_map == map(module_name, module_permissions).

:- type type_id_set == id_set.
:- type inst_id_set == id_set.
:- type mode_id_set == id_set.
:- type class_id_set == id_set.
    % Modules don't have an arity, but for simplicity we use the same
    % data structure for modules as for types etc, assigning arity zero
    % to all module names.
:- type module_id_set == id_set.

:- pred id_set_init(id_set::out) is det.

id_set_init(IdSet) :-
    map.init(IdSet).

    % Insert an mq_id into an id_set, aborting with an error if the
    % mq_id is not module qualified.
    %
:- pred id_set_insert(module_permissions::in, mq_id::in,
    id_set::in, id_set::out) is det.

id_set_insert(Permissions, MQId, !IdSet) :-
    MQId = mq_id(SymName, Arity),
    (
        SymName = unqualified(_),
        unexpected($module, $pred, "unqualified id")
    ;
        SymName = qualified(ModuleName, BaseName),
        % Most of the time, BaseName does not occur in !.IdSet.
        % We therefore try the insertion first, and only if it fails
        % do we update the existing entry that caused that failure.
        FreshPermissionsMap = map.singleton(ModuleName, Permissions),
        FreshSubMap = map.singleton(Arity, FreshPermissionsMap),
        ( if map.insert(BaseName, FreshSubMap, !IdSet) then
            true
        else
            map.lookup(!.IdSet, BaseName, SubMap0),
            ( if map.search(SubMap0, Arity, PermissionsMap0) then
                insert_into_permissions_map(Permissions, ModuleName,
                    PermissionsMap0, PermissionsMap),
                map.det_update(Arity, PermissionsMap, SubMap0, SubMap),
                map.det_update(BaseName, SubMap, !IdSet)
            else
                map.det_insert(Arity, FreshPermissionsMap, SubMap0, SubMap),
                map.det_update(BaseName, SubMap, !IdSet)
            )
        )
    ).

:- pred insert_into_permissions_map(module_permissions::in, module_name::in,
    permissions_map::in, permissions_map::out) is det.

insert_into_permissions_map(NewPermissions, ModuleName, !PermissionsMap) :-
    ( if map.search(!.PermissionsMap, ModuleName, OldPermissions) then
        OldPermissions = module_permissions(OldMayUseInInterface, OldNeedQual),
        NewPermissions = module_permissions(NewMayUseInInterface, NewNeedQual),
        % Grant the permissions granted by either OldPermissions or
        % NewPermissions.
        (
            OldMayUseInInterface = may_use_in_interface,
            MayUseInInterface = OldMayUseInInterface
        ;
            OldMayUseInInterface = may_not_use_in_interface,
            MayUseInInterface = NewMayUseInInterface
        ),
        (
            OldNeedQual = may_be_unqualified,
            NeedQual = OldNeedQual
        ;
            OldNeedQual = must_be_qualified,
            NeedQual = NewNeedQual
        ),
        % Update the entry only if it changed.
        ( if
            MayUseInInterface = OldMayUseInInterface,
            NeedQual = OldNeedQual
        then
            true
        else
            Permissions = module_permissions(MayUseInInterface, NeedQual),
            map.det_update(ModuleName, Permissions, !PermissionsMap)
        )
    else
        map.det_insert(ModuleName, NewPermissions, !PermissionsMap)
    ).

:- pred id_set_search_sym_arity(id_set::in, module_id_set::in,
    sym_name::in, int::in, assoc_list(module_name, module_permissions)::out)
    is det.

id_set_search_sym_arity(IdSet, ModuleIdSet, SymName, Arity,
        MatchingModuleNamesPermissions) :-
    UnqualName = unqualify_name(SymName),
    ( if
        map.search(IdSet, UnqualName, SubMap),
        map.search(SubMap, Arity, PermissionsMap)
    then
        find_matches_in_permissions_map(SymName, ModuleIdSet, PermissionsMap,
            MatchingModuleNamesPermissions)
    else
        MatchingModuleNamesPermissions = []
    ).

:- pred id_set_search_sym(id_set::in, module_id_set::in, sym_name::in,
    set(int)::out) is det.

id_set_search_sym(IdSet, ModuleIdSet, SymName, PossibleArities) :-
    UnqualName = unqualify_name(SymName),
    ( if
        map.search(IdSet, UnqualName, SubMap)
    then
        map.to_assoc_list(SubMap, SubMapPairs),
        find_matching_arities(SymName, ModuleIdSet, SubMapPairs,
            set.init, PossibleArities)
    else
        set.init(PossibleArities)
    ).

:- pred find_matching_arities(sym_name::in, module_id_set::in,
    assoc_list(int, permissions_map)::in, set(int)::in, set(int)::out) is det.

find_matching_arities(_SymName, _ModuleIdSet, [], !PossibleArities).
find_matching_arities(SymName, ModuleIdSet, [Pair | Pairs],
        !PossibleArities) :-
    Pair = Arity - PermissionsMap,
    find_matches_in_permissions_map(SymName, ModuleIdSet, PermissionsMap,
        MatchingModuleNamesPermissions),
    (
        MatchingModuleNamesPermissions = []
    ;
        MatchingModuleNamesPermissions = [_ | _],
        set.insert(Arity, !PossibleArities)
    ),
    find_matching_arities(SymName, ModuleIdSet, Pairs, !PossibleArities).

:- pred find_matches_in_permissions_map(sym_name::in, module_id_set::in,
    permissions_map::in,
    assoc_list(module_name, module_permissions)::out) is det.

find_matches_in_permissions_map(SymName, ModuleIdSet, PermissionsMap,
        MatchingModuleNamesPermissions) :-
    (
        SymName = unqualified(_),
        map.foldr(add_may_be_unqualified_modules, PermissionsMap,
            [], MatchingModuleNamesPermissions)
    ;
        SymName = qualified(ModuleName, _),

        % Compute the set of modules that this module specifier
        % could possibly refer to.
        %
        % Do a recursive search to find nested modules that match
        % the specified module name.
        ModuleArity = 0,
        id_set_search_sym_arity(ModuleIdSet, ModuleIdSet,
            ModuleName, ModuleArity, MatchingParentModuleNamesPermissions),
        ModuleBaseName = unqualify_name(ModuleName),
        AppendModuleBaseName = (pred(X::in, Y::out) is det :-
            Y = qualified(X, ModuleBaseName)
        ),
        assoc_list.keys(MatchingParentModuleNamesPermissions,
            MatchingParentModuleNames),
        list.map(AppendModuleBaseName,
            MatchingParentModuleNames, MatchingNestedModuleNames),

        % Add the specified module name itself, in case it refers to
        % a top-level (unnested) module name, since top-level modules
        % don't get inserted into the module_id_set.
        set.list_to_set([ModuleName | MatchingNestedModuleNames],
            MatchingModuleNamesSet),

        map.foldr(add_modules_in_set(MatchingModuleNamesSet), PermissionsMap,
            [], MatchingModuleNamesPermissions)
    ).

:- pred add_may_be_unqualified_modules(module_name::in, module_permissions::in,
    assoc_list(module_name, module_permissions)::in,
    assoc_list(module_name, module_permissions)::out) is det.

add_may_be_unqualified_modules(ModuleName, Permissions, !NamesPermissions) :-
    Permissions = module_permissions(_, NeedQual),
    (
        NeedQual = may_be_unqualified,
        !:NamesPermissions = [ModuleName - Permissions | !.NamesPermissions]
    ;
        NeedQual = must_be_qualified
    ).

:- pred add_modules_in_set(set(module_name)::in,
    module_name::in, module_permissions::in,
    assoc_list(module_name, module_permissions)::in,
    assoc_list(module_name, module_permissions)::out) is det.

add_modules_in_set(MatchingModuleNames, ModuleName, Permissions,
        !NamesPermissions) :-
    ( if set.member(ModuleName, MatchingModuleNames) then
        !:NamesPermissions = [ModuleName - Permissions | !.NamesPermissions]
    else
        true
    ).

%---------------------------------------------------------------------------%

    % Find the unique match in the current name space for a given mq_id
    % from a list of ids. If none exists, either because no match was found
    % or multiple matches were found, report an error.
    %
    % This predicate assumes that type_ids, inst_ids, mode_ids and
    % class_ids have the same representation.
    %
:- pred find_unique_match(mq_in_interface::in, mq_error_context::in,
    id_set::in, id_type::in, mq_id::in, sym_name::out,
    mq_info::in, mq_info::out,
    list(error_spec)::in, list(error_spec)::out) is det.

find_unique_match(InInt, ErrorContext, IdSet, IdType, Id0, SymName,
        !Info, !Specs) :-
    % Find all IDs which match the current id.
    Id0 = mq_id(SymName0, Arity),
    mq_info_get_modules(!.Info, Modules),
    id_set_search_sym_arity(IdSet, Modules, SymName0, Arity,
        ModuleNamesPermissions),
    (
        ModuleNamesPermissions = [],
        % No matches for this id.
        MaybeUniqModuleName = no,
        mq_info_get_should_report_errors(!.Info, ReportErrors),
        (
            ReportErrors = should_report_errors,
            id_set_search_sym(IdSet, Modules, SymName0, PossibleArities),
            report_undefined_mq_id(!.Info, ErrorContext, Id0, IdType,
                [], PossibleArities, !Specs),
            mq_info_record_undef_mq_id(IdType, !Info)
        ;
            ReportErrors = should_not_report_errors
        )
    ;
        ModuleNamesPermissions = [ModuleName - ModulePermissions],
        % A unique match for this ID.
        ModulePermissions = module_permissions(MayUseInInterface, _),
        ( if
            InInt = mq_used_in_interface,
            MayUseInInterface = may_not_use_in_interface
        then
            MaybeUniqModuleName = no,
            mq_info_get_should_report_errors(!.Info, ReportErrors),
            (
                ReportErrors = should_report_errors,
                BadBaseName = unqualify_name(SymName0),
                BadSymName = qualified(ModuleName, BadBaseName),
                mq_info_get_this_module(!.Info, ThisModuleName),
                ( if ModuleName = ThisModuleName then
                    report_may_not_use_in_interface(ErrorContext, IdType,
                        BadSymName, Arity, !Specs)
                else
                    id_set_search_sym(IdSet, Modules, SymName0,
                        PossibleArities),
                    report_undefined_mq_id(!.Info, ErrorContext, Id0, IdType,
                        [ModuleName], PossibleArities, !Specs)
                ),
                mq_info_record_undef_mq_id(IdType, !Info)
            ;
                ReportErrors = should_not_report_errors
            )
        else
            MaybeUniqModuleName = yes(ModuleName)
        )
    ;
        ModuleNamesPermissions = [_, _ | _],
        (
            InInt = mq_used_in_interface,
            which_modules_may_be_used_in_interface(ModuleNamesPermissions,
                UsableModuleNamesPermissions, NonUsableModuleNames)
        ;
            InInt = mq_not_used_in_interface,
            UsableModuleNamesPermissions = ModuleNamesPermissions,
            NonUsableModuleNames = []
        ),
        (
            UsableModuleNamesPermissions = [],
            % There are several matches, but none is usable from the interface.
            MaybeUniqModuleName = no,
            mq_info_get_should_report_errors(!.Info, ReportErrors),
            (
                ReportErrors = should_report_errors,
                id_set_search_sym(IdSet, Modules, SymName0, PossibleArities),
                report_undefined_mq_id(!.Info, ErrorContext, Id0, IdType,
                    NonUsableModuleNames, PossibleArities, !Specs),
                mq_info_record_undef_mq_id(IdType, !Info)
            ;
                ReportErrors = should_not_report_errors
            )
        ;
            UsableModuleNamesPermissions = [ModuleName - _Permissions],
            MaybeUniqModuleName = yes(ModuleName)
        ;
            UsableModuleNamesPermissions = [_, _ | _],
            MaybeUniqModuleName = no,
            mq_info_get_should_report_errors(!.Info, ReportErrors),
            (
                ReportErrors = should_report_errors,
                assoc_list.keys(UsableModuleNamesPermissions,
                    UsableModuleNames),
                report_ambiguous_match(ErrorContext, Id0, IdType,
                    UsableModuleNames, NonUsableModuleNames, !Specs),
                mq_info_record_undef_mq_id(IdType, !Info)
            ;
                ReportErrors = should_not_report_errors
            )
        )
    ),
    (
        MaybeUniqModuleName = no,
        % Returning any SymName is fine, since it won't be used.
        Id0 = mq_id(SymName, _)
    ;
        MaybeUniqModuleName = yes(UniqModuleName),
        BaseName = unqualify_name(SymName0),
        SymName = qualified(UniqModuleName, BaseName),
        mq_info_set_module_used(InInt, UniqModuleName, !Info),
        ItemType = convert_simple_item_type(IdType),
        ItemName0 = item_name(SymName0, Arity),
        ItemName = item_name(SymName, Arity),
        update_recompilation_info(
            recompilation.record_used_item(ItemType, ItemName0, ItemName),
            !Info)
    ).

:- pred which_modules_may_be_used_in_interface(
    assoc_list(module_name, module_permissions)::in,
    assoc_list(module_name, module_permissions)::out,
    list(module_name)::out) is det.

which_modules_may_be_used_in_interface([], [], []).
which_modules_may_be_used_in_interface([Pair | Pairs],
        MayUsePairs, MayNotUseNames) :-
    which_modules_may_be_used_in_interface(Pairs,
        MayUsePairsTail, MayNotUseNamesTail),
    Pair = ModuleName - module_permissions(MayUseInInterface, _),
    (
        MayUseInInterface = may_use_in_interface,
        MayUsePairs = [Pair | MayUsePairsTail],
        MayNotUseNames = MayNotUseNamesTail
    ;
        MayUseInInterface = may_not_use_in_interface,
        MayUsePairs = MayUsePairsTail,
        MayNotUseNames = [ModuleName | MayNotUseNamesTail]
    ).

:- func convert_simple_item_type(id_type) = item_type.

convert_simple_item_type(type_id) = type_abstract_item.
convert_simple_item_type(mode_id) = mode_item.
convert_simple_item_type(inst_id) = inst_item.
convert_simple_item_type(class_id) = typeclass_item.

%---------------------------------------------------------------------------%
%
% Facilities for recording the contexts of errors.
%

:- type mq_constraint_error_context
    --->    mqcec_class_defn(prog_context,
                % The name of the type class beging defined, and its arity.
                class_name,
                int
            )
    ;       mqcec_class_method(prog_context,
                % The identity of the class method the constraint is on:
                % whether it is predicate or function, and its name.
                % Its arity would be nice, but it is tricky to calculate
                % in the presence of with_type.
                pred_or_func,
                string
            )
    ;       mqcec_instance_defn(prog_context,
                % The name of the class the instance is for, and the
                % instance type vector.
                class_name,
                list(mer_type)
            )
    ;       mqcec_type_defn_constructor(prog_context,
                % The name of the type whose definition the constraint is in.
                type_ctor,

                % The function symbol the constraint is on.
                string
            )
    ;       mqcec_pred_decl(prog_context,
                % The identity of the entity the constraint is on:
                % whether it is predicate or function, and its name.
                % Its arity would be nice, but it is tricky to calculate
                % in the presence of with_type.
                pred_or_func,
                sym_name,
                int
            ).

:- type mq_error_context
    --->    mqec_type_defn(prog_context,
                % The name of the type constructor whose definition we are in.
                type_ctor
            )
    ;       mqec_constructor_arg(prog_context,
                % The name of the type constructor whose definition we are in.
                type_ctor,

                % The name of the function symbol.
                string,

                % The argument number of the type.
                int,

                % The name of the field, if it has one.
                maybe(ctor_field_name)
            )
    ;       mqec_typeclass_constraint_name(
                % The context the constraint is in.
                mq_constraint_error_context
            )
    ;       mqec_typeclass_constraint(
                % The name and arity of the typeclass the constraint is for.
                sym_name,
                int,

                % The context the constraint is in.
                mq_constraint_error_context
            )
    ;       mqec_inst(prog_context,
                % The name of the inst.
                mq_id
            )
    ;       mqec_mode(prog_context,
                % The name of the mode.
                mq_id
            )
    ;       mqec_pred_or_func(prog_context,
                % Whether it is a predicate or function declaration, ...
                pred_or_func,

                % and its name.
                mq_id
            )
    ;       mqec_pred_or_func_mode(prog_context,
                maybe(pred_or_func),
                mq_id
            )
    ;       mqec_pragma(prog_context,
                pragma_type
            )
    ;       mqec_lambda_expr(prog_context)
    ;       mqec_clause_mode_annotation(prog_context)
    ;       mqec_type_qual(prog_context)
    ;       mqec_class(prog_context,
                mq_id
            )
    ;       mqec_instance(prog_context,
                mq_id
            )
    ;       mqec_mutable(prog_context,
                string
            )
    ;       mqec_event_spec_attr(prog_context,
                % The event name.
                string,

                % The attribute name.
                string
            ).

:- func id_to_sym_name_and_arity(mq_id) = sym_name_and_arity.

id_to_sym_name_and_arity(mq_id(SymName, Arity)) = SymName / Arity.

%---------------------------------------------------------------------------%
%
% Error reporting predicates.
%

    % Report an undefined type, inst or mode.
    %
:- pred report_undefined_mq_id(mq_info::in, mq_error_context::in,
    mq_id::in, id_type::in, list(module_name)::in, set(int)::in,
    list(error_spec)::in, list(error_spec)::out) is det.

report_undefined_mq_id(Info, ErrorContext, Id, IdType,
        UnusableModules, PossibleAritiesSet, !Specs) :-
    mq_error_context_to_pieces(ErrorContext, Context, ErrorContextPieces),
    id_type_to_string(IdType, IdStr),
    Pieces1 = [words("In")] ++ ErrorContextPieces ++ [suffix(":"), nl,
        words("error: undefined"), fixed(IdStr),
        sym_name_and_arity(id_to_sym_name_and_arity(Id)), suffix("."), nl],
    ( if
        % If it is a qualified symbol, then check whether the specified module
        % has been imported.

        Id = mq_id(qualified(ModuleName, _), _Arity),
        mq_info_get_this_module(Info, ThisModuleName),
        mq_info_get_imported_modules(Info, ImportedModuleNames),
        AvailModuleNames =
            [ThisModuleName | set.to_sorted_list(ImportedModuleNames)],
        module_name_matches_some(ModuleName, AvailModuleNames) = no
    then
        Pieces2 = [words("(The module"), sym_name(ModuleName),
            words("has not been imported.)"), nl]
    else
        (
            UnusableModules = [],
            Pieces2 = []
        ;
            UnusableModules = [_ | UnusableModulesTail],
            (
                UnusableModulesTail = [],
                ModuleWord = "module",
                HasWord = "has"
            ;
                UnusableModulesTail = [_ | _],
                ModuleWord = "modules",
                HasWord = "have"
            ),
            UnusableSymNames = list.map(wrap_module_name, UnusableModules),
            Pieces2 = [words("(The"), fixed(ModuleWord)] ++
                component_list_to_pieces(UnusableSymNames) ++
                [fixed(HasWord),
                    words("not been imported in the interface.)"), nl]
        )
    ),
    set.to_sorted_list(PossibleAritiesSet, PossibleArities),
    ( if
        PossibleArities = [_ | _],
        Pieces2 = []
    then
        Id = mq_id(SymName, _),
        id_types_to_string(IdType, IdsStr),
        IsAre = choose_number(PossibleArities, "is a", "are"),
        KindKinds = choose_number(PossibleArities, IdStr, IdsStr),
        ArityArities = choose_number(PossibleArities, "arity", "arities"),
        list.map(string.int_to_string, PossibleArities, PossibleArityStrs),
        PossibleAritiesPieces = list_to_pieces(PossibleArityStrs),
        Pieces3 = [words("(There"), words(IsAre), words(KindKinds),
            words("named"), quote(unqualify_name(SymName)),
            words("with"), words(ArityArities)] ++
            PossibleAritiesPieces ++ [suffix(".)"), nl]
    else
        Pieces3 = []
    ),
    Msg = simple_msg(Context, [always(Pieces1 ++ Pieces2 ++ Pieces3)]),
    Spec = error_spec(severity_error, phase_parse_tree_to_hlds, [Msg]),
    !:Specs = [Spec | !.Specs].

:- func module_name_matches_some(module_name, list(module_name)) = bool.

module_name_matches_some(_SearchModuleName, []) = no.
module_name_matches_some(SearchModuleName, [ModuleName | ModuleNames]) =
        Matches :-
    ( if partial_sym_name_matches_full(SearchModuleName, ModuleName) then
        Matches = yes
    else
        Matches = module_name_matches_some(SearchModuleName, ModuleNames)
    ).

    % Report an error where a type, inst, mode or typeclass had
    % multiple possible matches.
    %
:- pred report_ambiguous_match(mq_error_context::in, mq_id::in, id_type::in,
    list(module_name)::in, list(module_name)::in,
    list(error_spec)::in, list(error_spec)::out) is det.

report_ambiguous_match(ErrorContext, Id, IdType,
        UsableModuleNames, UnusableModuleNames, !Specs) :-
    mq_error_context_to_pieces(ErrorContext, Context, ErrorContextPieces),
    id_type_to_string(IdType, IdStr),
    UsableModuleSymNames = list.map(wrap_module_name, UsableModuleNames),
    MainPieces = [words("In")] ++ ErrorContextPieces ++ [suffix(":"), nl,
        words("ambiguity error: multiple possible matches for"),
        fixed(IdStr), wrap_id(Id), suffix("."), nl,
        words("The possible matches are in modules")] ++
        UsableModuleSymNames ++ [suffix("."), nl],
    (
        UnusableModuleNames = [],
        UnusablePieces = []
    ;
        (
            UnusableModuleNames = [_],
            MatchWord = "match"
        ;
            UnusableModuleNames = [_, _ | _],
            MatchWord = "matches"
        ),
        UnusableModuleSymNames =
            list.map(wrap_module_name, UnusableModuleNames),
        UnusablePieces = [words("The"), words(MatchWord),
            words("in modules")] ++ UnusableModuleSymNames ++
            [words("may not be used in the interface."), nl]
    ),
    VerbosePieces = [words("An explicit module qualifier"),
        words("may be necessary."), nl],
    Msg = simple_msg(Context,
        [always(MainPieces), always(UnusablePieces),
        verbose_only(verbose_always, VerbosePieces)]),
    Spec = error_spec(severity_error, phase_parse_tree_to_hlds, [Msg]),
    !:Specs = [Spec | !.Specs].

:- pred report_may_not_use_in_interface(mq_error_context::in,
    id_type::in, sym_name::in, arity::in,
    list(error_spec)::in, list(error_spec)::out) is det.

report_may_not_use_in_interface(ErrorContext, IdType,
        BadSymName, BadArity, !Specs) :-
    mq_error_context_to_pieces(ErrorContext, Context, ErrorContextPieces),
    id_type_to_string(IdType, IdStr),
    SNA = sym_name_and_arity(BadSymName / BadArity),
    MainPieces = [words("In")] ++ ErrorContextPieces ++ [suffix(":"), nl,
        words("error: the"), fixed(IdStr), SNA, words("is not exported,"),
        words("and thus it may not be used in the interface."), nl],
    Msg = simple_msg(Context, [always(MainPieces)]),
    Spec = error_spec(severity_error, phase_parse_tree_to_hlds, [Msg]),
    !:Specs = [Spec | !.Specs].

%---------------------------------------------------------------------------%

:- pred mq_constraint_error_context_to_pieces(mq_constraint_error_context::in,
    prog_context::out, string::out, list(format_component)::out) is det.

mq_constraint_error_context_to_pieces(ConstraintErrorContext,
        Context, Start, Pieces) :-
    (
        ConstraintErrorContext = mqcec_class_defn(Context, ClassName, Arity),
        Start = "in",
        Pieces = [words("definition of type class"),
            sym_name_and_arity(ClassName / Arity)]
    ;
        ConstraintErrorContext = mqcec_class_method(Context,
            PredOrFunc, MethodName),
        Start = "on",
        Pieces = [words("class method"),
            p_or_f(PredOrFunc), quote(MethodName)]
    ;
        ConstraintErrorContext = mqcec_instance_defn(Context,
            ClassName, ArgTypes),
        Start = "on",
        Pieces = [words("instance definition for"),
            sym_name_and_arity(ClassName / list.length(ArgTypes))]
    ;
        ConstraintErrorContext = mqcec_type_defn_constructor(Context,
            TypeCtor, FunctionSymbol),
        Start = "on",
        TypeCtor = type_ctor(TypeCtorSymName, TypeCtorArity),
        Pieces = [words("function symbol"), quote(FunctionSymbol),
            words("for type constructor"),
            sym_name_and_arity(TypeCtorSymName / TypeCtorArity)]
    ;
        ConstraintErrorContext = mqcec_pred_decl(Context,
            PredOrFunc, SymName, OrigArity),
        Start = "on",
        adjust_func_arity(PredOrFunc, OrigArity, Arity),
        Pieces = [words("declaration of "),
            fixed(pred_or_func_to_full_str(PredOrFunc)),
            sym_name_and_arity(SymName / Arity)]
    ).

:- pred mq_error_context_to_pieces(mq_error_context::in,
    prog_context::out, list(format_component)::out) is det.

mq_error_context_to_pieces(ErrorContext, Context,Pieces) :-
    (
        ErrorContext = mqec_type_defn(Context, TypeCtor),
        Pieces = [words("definition of type"), wrap_type_ctor(TypeCtor)]
    ;
        ErrorContext = mqec_constructor_arg(Context, ContainingTypeCtor,
            FunctionSymbol, ArgNum, MaybeCtorFieldName),
        (
            MaybeCtorFieldName = no,
            FieldNamePieces = []
        ;
            MaybeCtorFieldName = yes(CtorFieldName),
            CtorFieldName = ctor_field_name(FieldSymName, _FieldContext),
            FieldNamePieces = [words("(field name"),
                quote(unqualify_name(FieldSymName)), suffix(")")]
        ),
        Pieces = [words("the"), nth_fixed(ArgNum), words("argument of"),
            words("function symbol"), quote(FunctionSymbol)] ++
            FieldNamePieces ++
            [words("of the type"), wrap_type_ctor(ContainingTypeCtor)]
    ;
        ErrorContext = mqec_typeclass_constraint_name(ConstraintErrorContext),
        mq_constraint_error_context_to_pieces(ConstraintErrorContext,
            Context, _Start, Pieces)
    ;
        ErrorContext = mqec_typeclass_constraint(ClassName, Arity,
            ConstraintErrorContext),
        mq_constraint_error_context_to_pieces(ConstraintErrorContext,
            Context, Start, ConstraintErrorContextPieces),
        Pieces = [words("type class constraint for "),
            sym_name_and_arity(ClassName / Arity), words(Start) |
            ConstraintErrorContextPieces]
    ;
        ErrorContext = mqec_mode(Context, Id),
        Pieces = [words("definition of mode"), wrap_id(Id)]
    ;
        ErrorContext = mqec_inst(Context, Id),
        Pieces = [words("definition of inst"), wrap_id(Id)]
    ;
        ErrorContext = mqec_pred_or_func(Context, PredOrFunc, Id),
        Id = mq_id(SymName, OrigArity),
        adjust_func_arity(PredOrFunc, OrigArity, Arity),
        Pieces = [words("declaration of "),
            fixed(pred_or_func_to_full_str(PredOrFunc)),
            sym_name_and_arity(SymName / Arity)]
    ;
        ErrorContext = mqec_pred_or_func_mode(Context, MaybePredOrFunc, Id),
        Id = mq_id(SymName, OrigArity),
        (
            MaybePredOrFunc = yes(PredOrFunc),
            adjust_func_arity(PredOrFunc, OrigArity, Arity),
            Pieces = [words("mode declaration for"),
                fixed(pred_or_func_to_full_str(PredOrFunc)),
                sym_name_and_arity(SymName / Arity)]
        ;
            MaybePredOrFunc = no,
            Pieces = [words("mode declaration for"),
                sym_name_and_arity(SymName / OrigArity)]
        )
    ;
        ErrorContext = mqec_lambda_expr(Context),
        Pieces = [words("mode declaration for lambda expression")]
    ;
        ErrorContext = mqec_clause_mode_annotation(Context),
        Pieces = [words("clause mode annotation")]
    ;
        ErrorContext = mqec_pragma(Context, Pragma),
        (
            Pragma = pragma_foreign_decl(_),
            PragmaName = "foreign_decl"
        ;
            Pragma = pragma_foreign_code(_),
            PragmaName = "foreign_code"
        ;
            Pragma = pragma_foreign_proc(_),
            PragmaName = "foreign_proc"
        ;
            Pragma = pragma_foreign_import_module(_),
            PragmaName = "foreign_import_module"
        ;
            Pragma = pragma_foreign_proc_export(_),
            PragmaName = "foreign_proc_export"
        ;
            Pragma = pragma_foreign_export_enum(_),
            PragmaName = "foreign_export_enum"
        ;
            Pragma = pragma_foreign_enum(_),
            PragmaName = "foreign_enum"
        ;
            Pragma = pragma_external_proc(_),
            PragmaName = "external_proc"
        ;
            Pragma = pragma_type_spec(_),
            PragmaName = "type_spec"
        ;
            Pragma = pragma_inline(_),
            PragmaName = "inline"
        ;
            Pragma = pragma_no_inline(_),
            PragmaName = "no_inline"
        ;
            Pragma = pragma_unused_args(_),
            PragmaName = "unused_args"
        ;
            Pragma = pragma_exceptions(_),
            PragmaName = "exceptions"
        ;
            Pragma = pragma_trailing_info(_),
            PragmaName = "trailing_info"
        ;
            Pragma = pragma_mm_tabling_info(_),
            PragmaName = "mm_tabling_info"
        ;
            Pragma = pragma_obsolete(_),
            PragmaName = "obsolete"
        ;
            Pragma = pragma_no_detism_warning(_),
            PragmaName = "no_detism_warning"
        ;
            Pragma = pragma_tabled(_),
            PragmaName = "tabled"
        ;
            Pragma = pragma_fact_table(_),
            PragmaName = "fact_table"
        ;
            Pragma = pragma_reserve_tag(_),
            PragmaName = "reserve_tag"
        ;
            Pragma = pragma_oisu(_),
            PragmaName = "oisu"
        ;
            Pragma = pragma_promise_eqv_clauses(_),
            PragmaName = "promise_equivalent_clauses"
        ;
            Pragma = pragma_promise_pure(_),
            PragmaName = "promise_pure"
        ;
            Pragma = pragma_promise_semipure(_),
            PragmaName = "promise_semipure"
        ;
            Pragma = pragma_termination_info(_),
            PragmaName = "termination_info"
        ;
            Pragma = pragma_termination2_info(_),
            PragmaName = "termination2_info"
        ;
            Pragma = pragma_terminates(_),
            PragmaName = "terminates"
        ;
            Pragma = pragma_does_not_terminate(_),
            PragmaName = "does_not_terminate"
        ;
            Pragma = pragma_check_termination(_),
            PragmaName = "check_termination"
        ;
            Pragma = pragma_mode_check_clauses(_),
            PragmaName = "mode_check_clauses"
        ;
            Pragma = pragma_structure_sharing(_),
            PragmaName = "structure_sharing"
        ;
            Pragma = pragma_structure_reuse(_),
            PragmaName = "structure_reuse"
        ;
            Pragma = pragma_require_feature_set(_),
            PragmaName = "require_feature_set"
        ),
        Pieces = [words("pragma"), words(PragmaName)]
    ;
        ErrorContext = mqec_type_qual(Context),
        Pieces = [words("explicit type qualification")]
    ;
        ErrorContext = mqec_class(Context, Id),
        Pieces = [words("declaration of typeclass"), wrap_id(Id)]
    ;
        ErrorContext = mqec_instance(Context, Id),
        Pieces = [words("declaration of instance of typeclass"), wrap_id(Id)]
    ;
        ErrorContext = mqec_mutable(Context, Name),
        Pieces = [words("declaration for mutable "), quote(Name)]
    ;
        ErrorContext = mqec_event_spec_attr(Context, EventName, AttrName),
        Pieces = [words("attribute"), quote(AttrName),
            words("for"), quote(EventName)]
    ).

:- pred id_type_to_string(id_type::in, string::out) is det.

id_type_to_string(type_id, "type").
id_type_to_string(mode_id, "mode").
id_type_to_string(inst_id, "inst").
id_type_to_string(class_id, "typeclass").

:- pred id_types_to_string(id_type::in, string::out) is det.

id_types_to_string(type_id, "types").
id_types_to_string(mode_id, "modes").
id_types_to_string(inst_id, "insts").
id_types_to_string(class_id, "typeclasses").

    % Warn about a module imported in the interface that is not used
    % in the interface.
    %
:- pred warn_unused_interface_import(module_name::in,
    pair(module_name, one_or_more(prog_context))::in,
    list(error_spec)::in, list(error_spec)::out) is det.

warn_unused_interface_import(ParentModuleName,
        ImportedModuleName - ImportContexts, !Specs) :-
    ImportContexts = one_or_more(HeadContext, TailContexts),
    HeadPieces =
        [words("In module"), sym_name(ParentModuleName), suffix(":"), nl,
        words("warning: module"), sym_name(ImportedModuleName),
        words("is imported in the interface,"),
        words("but it is not used in the interface."), nl],
    HeadMsg = simple_msg(HeadContext,
        [option_is_set(warn_interface_imports, yes, [always(HeadPieces)])]),
    % TailContexts is almost always [], we add TailMsgs just in case it isn't.
    list.map(warn_redundant_import_context(ImportedModuleName),
        TailContexts, TailMsgs),
    Severity = severity_conditional(warn_interface_imports, yes,
        severity_warning, no),
    Spec = error_spec(Severity, phase_parse_tree_to_hlds,
        [HeadMsg | TailMsgs]),
    !:Specs = [Spec | !.Specs].

:- pred warn_redundant_import_context(module_name::in, prog_context::in,
    error_msg::out) is det.

warn_redundant_import_context(ImportedModuleName, Context, Msg) :-
    Pieces = [words("Module"), sym_name(ImportedModuleName),
        words("is also redundantly imported here."), nl],
    Msg = simple_msg(Context,
        [option_is_set(warn_interface_imports, yes, [always(Pieces)])]).

    % Output an error message about an ill-formed user_inst.
    %
:- pred report_invalid_user_inst(sym_name::in, list(mer_inst)::in,
    mq_error_context::in, list(error_spec)::in, list(error_spec)::out) is det.

report_invalid_user_inst(_SymName, _Insts, ErrorContext, !Specs) :-
    mq_error_context_to_pieces(ErrorContext, Context, ErrorContextPieces),
    Pieces = [words("In")] ++ ErrorContextPieces ++ [suffix(":"), nl,
        words("error: variable used as inst constructor."), nl],
    Msg = simple_msg(Context, [always(Pieces)]),
    Spec = error_spec(severity_error, phase_parse_tree_to_hlds, [Msg]),
    !:Specs = [Spec | !.Specs].

%---------------------------------------------------------------------------%

:- func wrap_module_name(module_name) = format_component.

wrap_module_name(SymName) = sym_name(SymName).

:- func wrap_type_ctor(type_ctor) = format_component.

wrap_type_ctor(type_ctor(SymName, Arity)) =
    sym_name_and_arity(SymName / Arity).

:- func wrap_id(mq_id) = format_component.

wrap_id(mq_id(SymName, Arity)) = sym_name_and_arity(SymName / Arity).

%---------------------------------------------------------------------------%

    % If the current item is in the interface, remove its module name from
    % the list of modules not used in the interface, and if the module name
    % is itself module-qualified, mark its ancestor modules as used as well.
    %
:- pred mq_info_set_module_used(mq_in_interface::in, module_name::in,
    mq_info::in, mq_info::out) is det.

mq_info_set_module_used(InInt, ModuleName, !Info) :-
    (
        InInt = mq_used_in_interface,
        mq_info_get_as_yet_unused_interface_modules(!.Info, AsYetUnused0),
        ( if map.remove(ModuleName, _, AsYetUnused0, AsYetUnused) then
            mq_info_set_as_yet_unused_interface_modules(AsYetUnused, !Info)
        else
            % ModuleName was not in AsYetUnused0.
            true
        ),
        (
            ModuleName = qualified(ParentModule, _),
            mq_info_set_module_used(InInt, ParentModule, !Info)
        ;
            ModuleName = unqualified(_)
        )
    ;
        InInt = mq_not_used_in_interface
    ).

%---------------------------------------------------------------------------%
%
% Access and initialisation predicates.
%

:- type maybe_should_report_errors
    --->    should_not_report_errors
    ;       should_report_errors.

:- type mq_sub_info
    --->    mq_sub_info(
                % The name of the current module.
                mqsi_this_module                :: module_name,

                % Modules which have been imported or used, i.e. the ones
                % for which there was a `:- import_module' or `:- use_module'
                % declaration in this module.
                mqsi_imported_modules           :: set(module_name),

                % Modules from which `:- instance' declarations have
                % been imported.
                mqsi_imported_instance_modules  :: set(module_name),

                % Does this module export any type class instances?
                mqsi_exported_instances_flag    :: bool,

                % Are there any undefined types, insts, modes or typeclasses?
                mqsi_found_undef_type           :: maybe_found_undef_type,
                mqsi_found_undef_inst           :: maybe_found_undef_inst,
                mqsi_found_undef_mode           :: maybe_found_undef_mode,
                mqsi_found_undef_typeclass      :: maybe_found_undef_typeclass,

                % Do we want to report errors.
                mqsi_should_report_errors       :: maybe_should_report_errors,

                % The number of errors found.
                mqsi_num_errors                 :: int
            ).

:- type mq_info
    --->    mq_info(
                mqi_sub_info                    :: mq_sub_info,

                % Sets of all modules, types, insts, modes, and typeclasses
                % visible in this module.
                mqi_modules                     :: module_id_set,
                mqi_types                       :: type_id_set,
                mqi_insts                       :: inst_id_set,
                mqi_modes                       :: mode_id_set,
                mqi_classes                     :: class_id_set,

                % Map each modules known to be imported in the interface
                % that is not yet known to be needed in the interface
                % to the location (or sometimes, locations) of the import.
                mqi_as_yet_unused_interface_modules :: map(module_name,
                                                    one_or_more(prog_context)),

                mqi_maybe_recompilation_info    :: maybe(recompilation_info)
            ).

:- pred init_mq_info(globals::in, module_name::in,
    list(item_block(MS1))::in,
    list(item_block(MS2))::in,
    list(item_block(MS3))::in,
    list(item_block(MS4))::in,
    maybe_should_report_errors::in, mq_info::out) is det.

init_mq_info(Globals, ModuleName, ItemBlocksA, ItemBlocksB, ItemBlocksC,
        ItemBlocksD, ReportErrors, Info) :-
    get_implicit_dependencies_in_item_blocks(Globals, ItemBlocksA,
        ImportDepsA, UseDepsA),
    get_implicit_dependencies_in_item_blocks(Globals, ItemBlocksB,
        ImportDepsB, UseDepsB),
    get_implicit_dependencies_in_item_blocks(Globals, ItemBlocksC,
        ImportDepsC, UseDepsC),
    get_implicit_dependencies_in_item_blocks(Globals, ItemBlocksD,
        ImportDepsD, UseDepsD),
    ImportedModules = set.union_list(
        [ImportDepsA, ImportDepsB, ImportDepsC, ImportDepsD,
        UseDepsA, UseDepsB, UseDepsC, UseDepsD]),
    set.init(InstanceModules),
    ExportedInstancesFlag = no,
    SubInfo = mq_sub_info(ModuleName, ImportedModules, InstanceModules,
        ExportedInstancesFlag, did_not_find_undef_type,
        did_not_find_undef_inst, did_not_find_undef_mode,
        did_not_find_undef_typeclass, ReportErrors, 0),

    id_set_init(ModuleIdSet),
    id_set_init(TypeIdSet),
    id_set_init(InstIdSet),
    id_set_init(ModeIdSet),
    id_set_init(ClassIdSet),
    map.init(AsYetUnusedInterfaceModules),
    globals.lookup_bool_option(Globals, smart_recompilation,
        SmartRecompilation),
    (
        SmartRecompilation = no,
        MaybeRecompInfo = no
    ;
        SmartRecompilation = yes,
        MaybeRecompInfo = yes(init_recompilation_info(ModuleName))
    ),
    Info = mq_info(SubInfo, ModuleIdSet,
        TypeIdSet, InstIdSet, ModeIdSet, ClassIdSet,
        AsYetUnusedInterfaceModules, MaybeRecompInfo).

:- pred mq_info_get_modules(mq_info::in, module_id_set::out) is det.
:- pred mq_info_get_types(mq_info::in, type_id_set::out) is det.
:- pred mq_info_get_insts(mq_info::in, inst_id_set::out) is det.
:- pred mq_info_get_modes(mq_info::in, mode_id_set::out) is det.
:- pred mq_info_get_classes(mq_info::in, class_id_set::out) is det.
:- pred mq_info_get_as_yet_unused_interface_modules(mq_info::in,
    map(module_name, one_or_more(prog_context))::out) is det.
% mq_info_get_recompilation_info is exported

:- pred mq_info_get_this_module(mq_info::in, module_name::out) is det.
:- pred mq_info_get_imported_modules(mq_info::in, set(module_name)::out)
    is det.
:- pred mq_info_get_imported_instance_modules(mq_info::in,
    set(module_name)::out) is det.
:- pred mq_info_get_exported_instances_flag(mq_info::in, bool::out) is det.
% mq_info_get_type_error_flag is exported
% mq_info_get_mode_error_flag is exported
:- pred mq_info_get_should_report_errors(mq_info::in,
    maybe_should_report_errors::out) is det.

mq_info_get_modules(Info, X) :-
    X = Info ^ mqi_modules.
mq_info_get_types(Info, X) :-
    X = Info ^ mqi_types.
mq_info_get_insts(Info, X) :-
    X = Info ^ mqi_insts.
mq_info_get_modes(Info, X) :-
    X = Info ^ mqi_modes.
mq_info_get_classes(Info, X) :-
    X = Info ^ mqi_classes.
mq_info_get_as_yet_unused_interface_modules(Info, X) :-
    X = Info ^ mqi_as_yet_unused_interface_modules.
mq_info_get_recompilation_info(Info, X) :-
    X = Info ^ mqi_maybe_recompilation_info.

mq_info_get_this_module(Info, X) :-
    X = Info ^ mqi_sub_info ^ mqsi_this_module.
mq_info_get_imported_modules(Info, X) :-
    X = Info ^ mqi_sub_info ^ mqsi_imported_modules.
mq_info_get_imported_instance_modules(Info, X) :-
    X = Info ^ mqi_sub_info ^ mqsi_imported_instance_modules.
mq_info_get_exported_instances_flag(Info, X) :-
    X = Info ^ mqi_sub_info ^ mqsi_exported_instances_flag.
mq_info_get_found_undef_type(Info, X) :-
    X = Info ^ mqi_sub_info ^ mqsi_found_undef_type.
mq_info_get_found_undef_inst(Info, X) :-
    X = Info ^ mqi_sub_info ^ mqsi_found_undef_inst.
mq_info_get_found_undef_mode(Info, X) :-
    X = Info ^ mqi_sub_info ^ mqsi_found_undef_mode.
mq_info_get_found_undef_typeclass(Info, X) :-
    X = Info ^ mqi_sub_info ^ mqsi_found_undef_typeclass.
mq_info_get_should_report_errors(Info, X) :-
    X = Info ^ mqi_sub_info ^ mqsi_should_report_errors.

:- pred mq_info_set_modules(module_id_set::in,
    mq_info::in, mq_info::out) is det.
:- pred mq_info_set_types(type_id_set::in,
    mq_info::in, mq_info::out) is det.
:- pred mq_info_set_insts(inst_id_set::in,
    mq_info::in, mq_info::out) is det.
:- pred mq_info_set_modes(mode_id_set::in,
    mq_info::in, mq_info::out) is det.
:- pred mq_info_set_classes(class_id_set::in,
    mq_info::in, mq_info::out) is det.
:- pred mq_info_set_as_yet_unused_interface_modules(
    map(module_name, one_or_more(prog_context))::in,
    mq_info::in, mq_info::out) is det.
% mq_info_get_recompilation_info is exported

:- pred mq_info_set_imported_instance_modules(set(module_name)::in,
    mq_info::in, mq_info::out) is det.
:- pred mq_info_set_imported_modules(set(module_name)::in,
    mq_info::in, mq_info::out) is det.
:- pred mq_info_set_exported_instances_flag(bool::in,
    mq_info::in, mq_info::out) is det.
:- pred mq_info_set_found_undef_type(mq_info::in, mq_info::out) is det.
:- pred mq_info_set_found_undef_inst(mq_info::in, mq_info::out) is det.
:- pred mq_info_set_found_undef_mode(mq_info::in, mq_info::out) is det.
:- pred mq_info_set_found_undef_typeclass(mq_info::in, mq_info::out) is det.

mq_info_set_modules(X, !Info) :-
    !Info ^ mqi_modules := X.
mq_info_set_types(X, !Info) :-
    !Info ^ mqi_types := X.
mq_info_set_insts(X, !Info) :-
    !Info ^ mqi_insts := X.
mq_info_set_modes(X, !Info) :-
    !Info ^ mqi_modes := X.
mq_info_set_classes(X, !Info) :-
    !Info ^ mqi_classes := X.
mq_info_set_as_yet_unused_interface_modules(X, !Info) :-
    !Info ^ mqi_as_yet_unused_interface_modules := X.
mq_info_set_recompilation_info(X, !Info) :-
    !Info ^ mqi_maybe_recompilation_info := X.

mq_info_set_imported_modules(X, !Info) :-
    !Info ^ mqi_sub_info ^ mqsi_imported_modules := X.
mq_info_set_imported_instance_modules(X, !Info) :-
    !Info ^ mqi_sub_info ^ mqsi_imported_instance_modules := X.
mq_info_set_exported_instances_flag(X, !Info) :-
    !Info ^ mqi_sub_info ^ mqsi_exported_instances_flag := X.
mq_info_set_found_undef_type(!Info) :-
    X = found_undef_type,
    !Info ^ mqi_sub_info ^ mqsi_found_undef_type := X.
mq_info_set_found_undef_inst(!Info) :-
    X = found_undef_inst,
    !Info ^ mqi_sub_info ^ mqsi_found_undef_inst := X.
mq_info_set_found_undef_mode(!Info) :-
    X = found_undef_mode,
    !Info ^ mqi_sub_info ^ mqsi_found_undef_mode := X.
mq_info_set_found_undef_typeclass(!Info) :-
    X = found_undef_typeclass,
    !Info ^ mqi_sub_info ^ mqsi_found_undef_typeclass := X.

:- pred mq_info_record_undef_mq_id(id_type::in,
    mq_info::in, mq_info::out) is det.

mq_info_record_undef_mq_id(IdType, !Info) :-
    (
        IdType = type_id,
        mq_info_set_found_undef_type(!Info)
    ;
        IdType = inst_id,
        mq_info_set_found_undef_inst(!Info)
    ;
        IdType = mode_id,
        mq_info_set_found_undef_mode(!Info)
    ;
        IdType = class_id,
        mq_info_set_found_undef_typeclass(!Info)
    ).

%---------------------%

:- pred update_recompilation_info(
    pred(recompilation_info, recompilation_info)::in(pred(in, out) is det),
    mq_info::in, mq_info::out) is det.

update_recompilation_info(Pred, !Info) :-
    mq_info_get_recompilation_info(!.Info, MaybeRecompInfo0),
    (
        MaybeRecompInfo0 = yes(RecompInfo0),
        Pred(RecompInfo0, RecompInfo),
        mq_info_set_recompilation_info(yes(RecompInfo), !Info)
    ;
        MaybeRecompInfo0 = no
    ).

%---------------------------------------------------------------------------%
:- end_module parse_tree.module_qual.
%---------------------------------------------------------------------------%
