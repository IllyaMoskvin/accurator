:- module(strategy_expertise, [strategy_expertise/2, cluster_recommender/3]).

:- use_module(library(accurator/accurator_user)).
:- use_module(library(accurator/expertise)).
:- use_module(library(accurator/recommendation/strategy_random)).
:- use_module(library(cluster_search/cs_filter)).
:- use_module(library(cluster_search/rdf_search)).
:- use_module(library(cluster_search/owl_ultra_lite)).
:- use_module(api(cluster_search)).
:- use_module(library(semweb/rdfs)).
:- use_module(library(semweb/rdf_db)).


:- multifile
	cluster_search:predicate_weight/2.

%strategy_expertise(Result, []).

%%	strategy_expertise(-Result, +Options)
%
%	Recommend items based on user expertise.
strategy_expertise(Result, Options0) :-
	option(output_format(OutputFormat), Options0),
	option(user(User), Options0),
	get_attribute(User, domain, Domain),
	Options1 = [domain(Domain) | Options0],
	%set initial max agenda
	Options = [max_agenda(100) | Options1],
	strategy_expertise(OutputFormat, Result, 3, Options).

strategy_expertise(cluster, Clusters, AgendaSize, Options0) :-
	set_expertise_agenda(AgendaSize, Agenda, Options0, Options),
    cluster_recommender(Agenda, State, Options),
	OrganizeOptions = [groupBy(path)],
    organize_resources(State, Clusters, OrganizeOptions).

strategy_expertise(list, Result, AgendaSize, Options) :-
	strategy_expertise_list([], Result, AgendaSize, Options).

strategy_expertise_list(List, List, AgendaSize, Options) :-
	%see if agenda can be extended
	option(max_agenda(Max), Options),
	debug(numbers, 'Agenda ~p Max ~p', [AgendaSize, Max]),
	%stop extending agenda if size extends max
	AgendaSize > Max,
	!.

strategy_expertise_list(List, ShortList, AgendaSize, Options) :-
	option(number(Number), Options),
	length(List, Length),
	debug(numbers, 'Agenda ~p Length list ~p', [AgendaSize, Length]),
	%Stop extending the agenda when the Length is longer than Number
	Length > Number,
	%Should in the end add a check for empty agenda
	!,
	%Shorten the list to number
	append(ShortList, _Tail, List),
	length(ShortList, Number).

strategy_expertise_list(_Result, FinalResult, AgendaSize, Options0) :-
	set_expertise_agenda(AgendaSize, Agenda, Options0, Options),
    cluster_recommender(Agenda, State, Options),
	OrganizeOptions = [groupBy(path)],
    organize_resources(State, Clusters, OrganizeOptions),
	merge_in_list(Clusters, List, Options),
	option(filter(Filter), Options),
	filter(Filter, List, FilteredList, Options),
	NewAgendaSize is AgendaSize + 1,
	strategy_expertise_list(FilteredList, FinalResult, NewAgendaSize, Options).

merge_in_list(clusters(Clusters), ElementsList, _Options) :-
	get_elements_list(Clusters, ElementsList).

get_elements_list([], []) :- !.
get_elements_list([_Path-ElementsDirty|Clusters], ElementsList) :-
	get_elements(ElementsDirty, Elements),
	append(Elements, ElementsList0, ElementsList),
	get_elements_list(Clusters, ElementsList0).

get_elements([], []) :- !.
get_elements([_Score-Item-_Path|Elements], [Item|Items]):-
	get_elements(Elements, Items).

%%	filter(+FilterOption, +Uris, -FilteredUris, +Options)
%
%	Filter the potential candidates.
filter(annotated, SourceList, FilteredUris, Options) :-
	option(user(User), Options),
	get_annotated_user(User, AnnotatedUris),
	subtract(SourceList, AnnotatedUris, FilteredUris).
filter(none, SourceList, SourceList, _Options).

%%	set_expertise_agenda(+MaxNumber, -NumberExpertise, -Agenda,
%	+Options, -NewOptions)
%
%	Set the agenda by retrieving all the expertise values of user given
%	a domain, sort based on the values and pick the highest values with
%	a maximum number.
set_expertise_agenda(MaxNumber, Agenda, [max_agenda(_)|Options0], Options) :-
	option(user(User), Options0),
	option(domain(Domain), Options0),
	get_user_expertise_domain(User, Domain, ExpertiseValues),
	transpose_pairs(ExpertiseValues, SortedExpertiseValues),
	%determine the number of expertise levels to be picked
	length(SortedExpertiseValues, NumberExpertise),
	Options = [max_agenda(NumberExpertise) | Options0],
	number_of_items(NumberExpertise, MaxNumber, NumberItems),
	group_pairs_by_key(SortedExpertiseValues, ReverseGroupedValues),
	reverse(ReverseGroupedValues, GroupedValues),
	expertise_from_bins(GroupedValues, 0, NumberItems, Agenda).

%%	expertise_from_bins(+Bins, +Counter, +MaxN, -Agenda)
%
%	Determine the agenda by picking expertise values from bins. When a
%	bin has multiple expertise areas, pick one at random from that bin.
expertise_from_bins(_Bins, MaxN, MaxN, []).
expertise_from_bins(Bins, N0, MaxN, [Expertise|List]) :-
	N is N0 + 1,
	random_from_bin(Bins, NewBins, Expertise),
	expertise_from_bins(NewBins, N, MaxN, List).

%%	number_of_items(+NumberExpertise, +Number0, -NumberExpertise)
%
%	Determine the maximum number of agenda items.
number_of_items(NumberExpertise, Number0, NumberExpertise) :-
	NumberExpertise < Number0, !.
number_of_items(_NumberExpertise, Number0, Number0).

cluster_recommender(Agenda, State, Options) :-
	option(target(Target), Options),
	filter_to_goal([type(Target)], R, Goal, Options),
	%unbound steps for now
	Steps = -1,
	%constructed search goal
	TargetCond = target_goal(Goal, R),
	%define edges used
	Expand = rdf_backward_search:edge,
	%add that to options, set threshold low to enable graph traphersal
	SearchOptions = [edge_limit(100), threshold(0.0001),
					 expand_node(Expand), graphOutput(spo)],
	%init search state
	rdf_init_state(TargetCond, State, SearchOptions),
	%start the search with set agenda (instead of keyword)
	rdf_start_search(Agenda, State),
	%do the steps
	steps(0, Steps, State),
	%prune the graph
	prune(State, []).

steps(Steps, Steps, _) :- !.
steps(I, Steps, Graph) :-
	I2 is I + 1,
	(   rdf_extend_search(Graph)
	->  (   debugging(rdf_search)
	    ->  debug(rdf_search, 'After cycle ~D', [I2]),
		forall(debug_property(P),
		       (   rdf_search_property(Graph, P),
			   debug(rdf_search, '\t~p', [P])))
	    ;   true
	    ),
	    steps(I2, Steps, Graph)
	;   debug(rdf_search, 'Agenda is empty after ~D steps~n', [I])
	).

debug_property(target_count(_)).
debug_property(graph_size(_)).

prune(State, Options) :-
    rdf_prune_search(State, Options),
    rdf_search_property(State, graph_size(Nodes)),
    debug(rdf_search, 'After prune: ~D nodes in graph', [Nodes]).


%%	edge(+Node, +Score, -Link) is nondet.
%
%	Generate links from Object Node, consisting of a Subject,
%	Predicate and Weight.

edge(O, _, i(S,P,W)) :-
	edge(O, S, P, W),
	debug(myedge, 'Expanding ~2f ~p ~p ~p~n', [W, O, P, S]),
	W > 0.0001.

edge(O, S, P, W) :-
	setof(S, i_edge(O, S, P), Ss),
	(   predicate_weight(P, W)
	->  member(S, Ss)
	;   length(Ss, Len),
	    member(S, Ss),
	    subject_weight(S, Len, W)
	).


%%	i_edge(+O, -S, -P)
%
%	Find Subject that is connected through Predicate.

% annotation edge hack: translate the connection between object and
% subject through an annotation into a dc:subject predicate.
i_edge(O, S, P) :-
	rdf(S, P, O).
i_edge(O, S, P) :-
	rdf(O, P0, S),
	atom(S),
	(   owl_ultra_lite:inverse_predicate(P0, P)
	->  true
	;   predicate_weight(P0, 1)
	->  P = P0
	).

%EXPERIMENT: do not consider annotations
%i_edge(O, S, P) :-
%	rdf(Annotation, oa:hasBody, O),
%        rdf(Annotation, oa:hasTarget, S),
%	rdf_equal(P, dc:subject).


%i_edge(O, S, P) :-
%	rdf(S, P, O),
	% ignore annotations connected by hasTarget
%	\+ rdf_equal(S, oa:hasTarget).
%i_edge(O, S, P) :-
%	rdf(O, P0, S),
%	atom(S),
%	(   owl_ultra_lite:inverse_predicate(P0, P)
%	->  true
%	;   predicate_weight(P0, 1)
%	->  P = P0
%	),
	% ignore annotations connected by hasTarget
%	\+ rdf_equal(S, oa:hasTarget).

%%	predicate_weight(+Predicate, -Weight) is semidet.
%
%	Weight based on the meaning of   Predicate. This predicate deals
%	with RDF predicates that have a  well defined meaning.
%
%	Additional weights (or overwrites) can be defined in
%	cluster_search:predicate_weight/2,
%
%	Note that rdfs:comment is not searched as  it   is  supposed to
%	be comment about the graph, and not part of the graph itself.

predicate_weight(P, Weight) :-
	catch(cluster_search:predicate_weight(P, Weight), _, fail), !.

predicate_weight(P, 1) :-
	rdfs_subproperty_of(P, rdfs:label), !.
predicate_weight(P, 1) :-
	rdfs_subproperty_of(P, rdf:value), !.
predicate_weight(P, 1) :-
	rdf_equal(P, owl:sameAs), !.
predicate_weight(P, 1) :-
	rdf_equal(P, skos:exactMatch), !.
predicate_weight(P, 0) :-
	rdfs_subproperty_of(P, rdfs:comment), !.

subject_weight(S, _, 1) :-
	rdf_is_bnode(S), !.
subject_weight(_, Count, W) :-
	W is 1/max(3, Count).
