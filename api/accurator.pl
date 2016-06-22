:- module(accurator, []).

/** <module> Accurator
*/
:- use_module(library(semweb/rdf_db)).
:- rdf_register_prefix(auis, 'http://accurator.nl/ui/schema#').
:- rdf_register_prefix(aui, 'http://accurator.nl/ui/generic#').
:- rdf_register_prefix(ausr, 'http://accurator.nl/user#').
:- rdf_register_prefix(as, 'http://accurator.nl/schema#').
:- rdf_register_prefix(edm, 'http://www.europeana.eu/schemas/edm/').
:- rdf_register_prefix(gn, 'http://www.geonames.org/ontology#').
:- rdf_register_prefix(txn, 'http://lod.taxonconcept.org/ontology/txn.owl#').
:- rdf_register_prefix(oa, 'http://www.w3.org/ns/oa#').
:- rdf_register_prefix(hoonoh, 'http://hoonoh.com/ontology#').

:- use_module(library(accurator/accurator_user)).
:- use_module(library(accurator/domain)).
:- use_module(library(accurator/expertise)).
:- use_module(library(accurator/recommendation/strategy_random)).
:- use_module(library(accurator/recommendation/strategy_expertise)).
:- use_module(library(accurator/ui_elements)).
:- use_module(library(accurator/annotation)).
:- use_module(library(accurator/subset_selection)).
:- use_module(library(accurator/concept_scheme_selection)).
:- use_module(library(accurator/review)).
:- use_module(library(accurator/statistics)).
:- use_module(library(http/http_dispatch)).
:- use_module(library(http/http_server_files)).
:- use_module(library(http/http_json)).
:- use_module(library(http/http_parameters)).
:- use_module(library(http/html_write)).
:- use_module(user(user_db)).
% load other cpacks
:- use_module(api(cluster_search)).
:- use_module(api(annotation)).    % needed for http api handlers
:- use_module(library(thumbnail)).


http:location(html, cliopatria(html), []).
http:location(img, cliopatria(img), []).
http:location(fonts, cliopatria(fonts), []).
user:file_search_path(html, web(html)).
user:file_search_path(img, web(img)).
user:file_search_path(fonts, web(fonts)).

:- http_handler(root('.'), redirect_to_home, []).
:- http_handler(cliopatria('.'), serve_files_in_directory(html), [prefix]).
:- http_handler(img('.'), serve_files_in_directory(img), [prefix]).
:- http_handler(fonts('.'), serve_files_in_directory(fonts), [prefix]).
:- http_handler(cliopatria('item.html'), page_item, []).
:- http_handler(cliopatria(ui_elements), ui_elements_api, []).
:- http_handler(cliopatria(domains), domains_api, []).
:- http_handler(cliopatria(statistics), statistics_api, []).
:- http_handler(cliopatria(metadata), metadata_api, []).
:- http_handler(cliopatria(annotation_fields), annotation_fields_api, []).
:- http_handler(cliopatria(annotations), annotations_api, []).
:- http_handler(cliopatria(expertise_topics), expertise_topics_api, []).
:- http_handler(cliopatria(expertise_values), expertise_values_api, []).
:- http_handler(cliopatria(register_user), register_user, []).
:- http_handler(cliopatria(get_user), get_user, []).
:- http_handler(cliopatria(get_user_settings), get_user_settings, []).
:- http_handler(cliopatria(save_user_info), save_user_info, []).
:- http_handler(cliopatria(get_user_info), user_info_api, []).
:- http_handler(cliopatria(recommendation), recommendation_api, []).

:- set_setting_default(thumbnail:thumbnail_size, size(350,300)).
:- set_setting_default(thumbnail:medium_size, size(1280,1024)).

locale([en,nl]). % loaded locales

%%	ui_elements_api(+Request)
%
%	Redirect to the intro page.
redirect_to_home(Request) :-
	http_redirect(moved_temporary, 'intro.html', Request).

%%	ui_elements_api(+Request)
%
%	Retrieves ui elements, according to the given locale, type and ui
%	screen. First it gets the url parameters, second it queries for the
%	results, after which the data is outputted
%	as json.
ui_elements_api(Request) :-
    get_parameters_elements(Request, Options),
	option(type(Type), Options),
	get_elements(Type, Dic, Options),
	reply_json_dict(Dic).

%%	get_parameters_elements(+Request, -Options)
%
%	Retrieves an option list of parameters from the url.
get_parameters_elements(Request, Options) :-
    http_parameters(Request,
        [ui(UI,
		    [description('UI for which text elements are retrieved'),
			 optional(false)]),
		 locale(Locale,
			[description('Locale of language elements to retrieve'),
			 optional(false)]),
		 type(Type,
			[description('Type of elements to retrieve'),
			 optional(type)])
	]),
	check_locale(Locale, CheckedLocale),
    Options = [ui(UI), locale(CheckedLocale), type(Type)].

%%	check_locale(+Locale, -CheckedLocale)
%
%	Checks whether locale is part of the loaded locales, otherwise sets
%	it to en.
check_locale(Locale, Locale) :-
	locale(LocaleList),
	member(Locale, LocaleList), !.
check_locale(_Locale, en).


%%     domains_api(+Request)
%
%	Retrieves the settings specific to a domain.
domains_api(Request) :-
    get_parameters_domain(Request, Options),
	get_domain_settings(Dic, Options),
	reply_json_dict(Dic).

%%	get_parameters_domain(+Request, -Options)
%
%	Retrieves an option list of parameters from the url.
get_parameters_domain(Request, Options) :-
    http_parameters(Request,
        [domain(Domain,
		    [description('The domain'),
			 optional(true)])]),
    Options = [domain(Domain)].

%%     statistics_api(+Request)
%
%	Retrieves annotation statistics.
statistics_api(Request) :-
    get_parameters_statistics(Request, Options),
	annotation_statistics(Dic, Options),
	reply_json_dict(Dic).

%%	get_parameters_statistics(+Request, -Options)
%
%	Retrieves an option list of parameters from the url.
get_parameters_statistics(Request, Options) :-
    http_parameters(Request,
        [domain(Domain,
		    [description('The domain'),
			 optional(true)])]),
    Options = [domain(Domain)].

%%	metadata_api(+Request)
%
%	Retrieves the metadata for a list of uris or a specific uri, the
%	type to be retrieved can be specified but is full on default.
metadata_api(Request) :-
	http_read_json_dict(Request, JsonIn), !,
	metadata_list(JsonIn, Results),
    reply_json_dict(Results).

metadata_api(Request) :-
    get_parameters_metadata(Request, Options),
    option(uri(Uri), Options),
	option(type(Type), Options),
    metadata(Type, Uri, Metadata),
    reply_json_dict(Metadata).

%%	metadata_list(+JsonDict, -Results)
%
%	Processes a json dict with uris, retrieving either labels or
%	thumbnail information
metadata_list(JsonIn, Results) :-
	get_dict(type, JsonIn, Type),
	Type == "label", !,
	UriStrings = JsonIn.uris,
	maplist(atom_string, Uris, UriStrings),
	maplist(uri_label, Uris, Results).

metadata_list(JsonIn, Results) :-
	UriStrings = JsonIn.uris,
	maplist(atom_string, Uris, UriStrings),
	maplist(metadata(thumbnail), Uris, Results).

%%	get_parameters_metadata(+Request, -Options)
%
%	Retrieves an option list of parameters from the url.
get_parameters_metadata(Request, Options) :-
    http_parameters(Request,
        [uri(Uri,
		    [description('The URI'),
			 optional(false)]),
		 type(Type,
			[description('Type of elements to retrieve'),
			 default(full),
			 optional(type)])]),
    Options = [uri(Uri), type(Type)].


%%	annotations_api(+Request)
%
%	Retrieves the metadata for a specific uri, the type to be retrieved
%	is full on default.
annotations_api(Request) :-
    get_parameters_annotations(Request, Options),
    option(uri(Uri), Options),
	option(type(Type), Options),
	option(enrich(Enrich), Options),
    annotations(Type, Uri, Annotations),
	enrich_annotations(Enrich, Annotations, EnrichedAnnotations),
    reply_json_dict(EnrichedAnnotations).

%%	get_parameters_annotations(+Request, -Options)
%
%	Retrieves an option list of parameters from the url.
get_parameters_annotations(Request, Options) :-
    http_parameters(Request,
        [uri(Uri,
		    [description('The URI of the object of user'),
			 optional(false)]),
		 enrich(Enrich,
		    [description('Boolean indicating whether annotations should be enriched'),
			 optional(true),
			 default(false)]),
		 type(Type,
			[description('Type of elements to retrieve'),
			 default(full),
			 optional(type)])]),
    Options = [uri(Uri), type(Type), enrich(Enrich)].

%%	annotation_fields_api(+Request)
%
%	Retrieves the fields for a specified locale and domain
annotation_fields_api(Request) :-
    get_parameters_annotation_fields(Request, Options),
    annotation_fields(Fields, Options),
    reply_json_dict(Fields).

%%	get_parameters_annotations(+Request, -Options)
%
%	Retrieves an option list of parameters from the url.
get_parameters_annotation_fields(Request, Options) :-
    http_parameters(Request,
        [annotation_ui(UI,
			[description('UI for which fields are retrieved'),
			 optional(false)]),
		 locale(Locale,
				[description('Locale of field descriptions to retrieve'),
				 optional(false)]),
		 domain(Domain,
				[description('Domain of field descriptions to retrieve'),
				 optional(false)])]),
	check_locale(Locale, CheckedLocale),
    Options = [annotation_ui(UI), locale(CheckedLocale), domain(Domain)].


%%	expertise_topics_api(+Request)
%
%	Retrieves a list of expertise topics.
expertise_topics_api(Request) :-
    get_parameters_expertise(Request, Options0),
	logged_on(User),
	Options1 = [user(User) | Options0],
	get_attribute(User, domain, Domain),
	Options = [domain(Domain) | Options1],
	get_expertise_topics(Dic, Options),
	reply_json_dict(Dic).

%%	get_parameters_expertise(+Request, -Options)
%
%	Retrieves an option list of parameters from the url.
get_parameters_expertise(Request, Options) :-
    http_parameters(Request,
        [locale(Locale,
		    [description('Locale of language elements to retrieve'),
			 optional(false)]),
		target(Target,
			[default('http://www.europeana.eu/schemas/edm/ProvidedCHO')]),
		taxonomy(Taxonomy,
			[description('Domain specific taxonomy.'),
			 optional(false)]),
		number_of_topics(NumberOfTopicsString,
			[description('The maximum number of topics to retrive'),
			 optional(false)]),
		top_concept(TopConcept,
			[description('The top concept to start searching form.'),
			 optional(false)]),
		number_of_children_shown(NumberOfChildrenString,
			[description('The number of child concepts shown.'),
			 optional(true),
			 default(3)])]),
    atom_number(NumberOfTopicsString, NumberOfTopics),
	atom_number(NumberOfChildrenString, NumberOfChildren),
	check_locale(Locale, CheckedLocale),
	Options = [locale(CheckedLocale), target(Target), taxonomy(Taxonomy),
			   topConcept(TopConcept), numberOfTopics(NumberOfTopics),
			   numberOfChildren(NumberOfChildren)].

%%  expertise_values_api(+Request)
%
%	Depending on the request either save or retrieve the user expertise
%	values.
expertise_values_api(Request) :-
	member(method(get), Request),
	logged_on(User),
	get_attribute(User, domain, Domain),
	get_user_expertise_domain(User, Domain, ExpertiseValues),
	dict_pairs(ExpertiseDict, elements, ExpertiseValues),
	reply_json_dict(ExpertiseDict).

expertise_values_api(Request) :-
	member(method(post), Request),
	http_read_json_dict(Request, JsonIn), !,
	atom_string(User, JsonIn.user),
	Expertise = JsonIn.expertise,
	dict_pairs(Expertise, elements, ExpertisePairs),
	maplist(assert_expertise_relationship(User), ExpertisePairs),
	reply_html_page(/,
					title('Assert expertise values'),
						h1('Successfully asserted expertise values')).

%%  recommendation_api(+Request)
%
%
recommendation_api(Request) :-
    get_recommendation_parameters(Request, Options),
    option(strategy(Strategy), Options),
    strategy(Strategy, Options).

%%	get_parameters(+Request, -Parameters)
%
%   Retrieves an option object of parameters from the url.
get_recommendation_parameters(Request, Options) :-
	logged_on(User),
    http_parameters(Request,
        [strategy(Strategy,
		    [default(random),
			 oneof([random, ranked_random, expertise])]),
		 target(Target,
			[default('http://www.europeana.eu/schemas/edm/ProvidedCHO')]),
		 number(Number,
			[integer, default(20)]),
		 filter(Filter,
		    [default(annotated),
			 oneof([none, annotated])]),
		 output_format(OutputFormat,
		    [default(cluster),
			 oneof([cluster, list])])
		]),
    Options = [strategy(Strategy), user(User),
			   target(Target), number(Number),
			   filter(Filter), output_format(OutputFormat)].

%%	strategy(+Strategy, +Options)
%
%   Selects objects according to the specified strategy.
strategy(random, Options) :-
    strategy_random(Result, Options),
	reply_json_dict(Result).

strategy(ranked_random, Options) :-
    strategy_user_ranked_random(Result, Options),
	reply_json_dict(Result).

strategy(expertise, Options) :-
    strategy_expertise(Results, Options),
	option(output_format(OutputFormat), Options),
	reply_expertise_results(OutputFormat, Results).

reply_expertise_results(cluster, Clusters) :-
	reply_clusters(Clusters).

reply_expertise_results(list, List) :-
	reply_json_dict(List).

%%	user_info_api(+Request)
%
%	Retrieves the value in the user profile for specified attribute
user_info_api(Request) :-
    get_parameters_user_info(Request, Options),
    get_user_info(Options).

%%	get_parameters_user_info(+Request, -Options)
%
%	Retrieves an option list of parameters from the url.
get_parameters_user_info(Request, Options) :-
	logged_on(LoggedinUser),
    http_parameters(Request,
        [attribute(Attribute,
			[description('Attribute for which values are retrieved'),
			 optional(false),
			 oneof(form_personal_shown, form_internet_shown)]),
		 user(User,
			[description('User for which values are retrieved'),
			 default(LoggedinUser)])]),
    Options = [attribute(Attribute), user(User)].

%%	page_item(+Request)
%
%	Replies html page
page_item(Request) :-
    get_parameters_page(Request, Options),
	option(uri(Uri), Options),
	reply_html_page(\head, \content(Uri)).

%%	get_parameters_elements(+Request, -Options)
%
%	Retrieves an option list of parameters from the url.
get_parameters_page(Request, Options) :-
    http_parameters(Request,
        [uri(Uri,
		    [description('Uri of the item'),
			 optional(false)])
		]),
    Options = [uri(Uri)].

head -->
html({|html||
<title>Item</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<link rel="shortcut icon" href="img/favicon.ico">
<link type="text/css" rel="stylesheet" media="screen" href="css/bootstrap.min.css" />
<link type="text/css" rel="stylesheet" href="css/annotorious.css" />
<link type="text/css" rel="stylesheet" media="screen" href="css/accurator.css" />
|}).

content(Uri) -->
	{image_url(Uri, ImageUrl)},
html({|html(ImageUrl)||
<!-- Navbar -->
<nav class="navbar navbar-inverse navbar-fixed-top" role="navigation">
     <div class="container-fluid">
        <div class="navbar-header">
            <button type="button" class="navbar-toggle collapsed" data-toggle="collapse" data-target="#navbarDivMenu">
                <span class="icon-bar"></span>
                <span class="icon-bar"></span>
            </button>
            <a class="navbar-brand" href="intro.html">
                <img id="navbarImgLogo" src="img/accurator.png" alt="Accurator">
            </a>
        </div>
        <div class="collapse navbar-collapse" id="navbarDivMenu">
            <ul class="nav navbar-nav navbar-right navbarLstFlag">
            </ul>
            <ul class="nav navbar-nav navbar-right navbarLstUser">
            </ul>
            <div class="navbar-form navbar-nav" id="navbarFrmSearch">
                <div class="form-group">
                    <input type="text" class="form-control" id="navbarInpSearch">
                </div>
                <button id="navbarBtnSearch" class="btn btn-default">
                </button>
            </div>
            <button class="btn navbar-btn navbar-right btn-primary" id="navbarBtnRecommend">
            </button>
        </div>
    </div>
</nav>

<!-- Events -->
<div class="container" id="eventsDiv">
</div>

<div class="container">
	<!-- Image -->
	<div class="row" id="itemDivImage">
		<img class="itemImg annotatable" src="ImageUrl" alt="" />
	</div>

	<!-- Annotation field(s) -->
	<div class="row" id="itemDivAnnotationFields">
		<div class="col-md-6" id="itemDivFields"></div>
	</div>

	<!-- Navigation -->
	<div class="row" id="itemDivClusterNavigation">
		<div class="itemDivNavigationButton col-md-2 col-xs-6">
			<button class="btn btn-default itemBtnNavigation" id="itemBtnPrevious">
				<span class="glyphicon glyphicon-chevron-left"></span>
			</button>
		</div>
		<div class="itemDivNavigationButton col-md-2 col-xs-6 col-md-push-8" id="itemDivAlignButton">
			<button class="btn btn-default itemBtnNavigation" id="itemBtnNext">
				<span class="glyphicon glyphicon-chevron-right"></span>
			</button>
		</div>
		<div class="col-md-8 col-md-pull-2" id="itemDivPath">
		</div>
	</div>

	<!-- Metadata -->
	<div id="itemDivMetadata"></div>
</div>

<!-- Login modal -->
<div class="modal fade" id="loginDivLogin">
	<div class="modal-dialog">
		<div class="modal-content">
			<div class="modal-header">
				<button type="button" class="close" id="loginBtnClose">&times;</button>
				<h4 id="loginHdrTitle">
				</h4>
			</div>
			<div class="modal-body">
				<form role="form">
					<div class="form-group">
						<label id="loginLblUsername" for="loginInpUsername">
						</label>
						<input type="text" class="form-control" id="loginInpUsername">
					</div>
					<div class="form-group">
						<label id="loginLblPassword" for="password">
						</label>
						<input type="password" class="form-control" id="loginInpPassword">
					</div>
					<p class="text-warning" id="loginTxtWarning">
					</p>
				</form>
			</div>
			<div class="modal-footer">
				<button class="btn btn-primary" id="loginBtnLogin">
				</button>
				<button class="btn btn-link" id="mdlBtnIntro">
				</button>
			</div>
		</div>
	</div>
</div>

<!-- Annotorious Annotation field(s) -->
<div class="itemDivHidden"></div>

<!-- Added Script -->
<script type="text/javascript" src="js/lib/jquery.min.js"></script>
<script type="text/javascript" src="js/lib/bootstrap.min.js"></script>
<script type="text/javascript" src="js/lib/laconic.js"></script>
<script type="text/javascript" src="js/lib/bloodhound.js"></script>
<script type="text/javascript" src="js/lib/typeahead.js"></script>
<script type="text/javascript" src="js/lib/annotorious.min.js"></script>
<script type="text/javascript" src="js/components/path.js"></script>
<script type="text/javascript" src="js/components/deniche-plugin.js"></script>
<script type="text/javascript" src="js/components/utilities.js"></script>
<script type="text/javascript" src="js/components/annotations.js"></script>
<script type="text/javascript" src="js/components/field.js"></script>
<script type="text/javascript" src="js/components/form.js"></script>
<script type="text/javascript" src="js/item.js"></script>
<script>itemInit()</script>
|}).
