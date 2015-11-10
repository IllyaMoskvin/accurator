/*******************************************************************************
Accurator Annotate
Code for extending functionallity annotation page.
*******************************************************************************/
var query, locale, experiment, domain, user, ui, uri;
var vntFirstTitle, vntFirstText;

displayOptions = {
	showMetadata: true,
	showAnnotations: true,
}

function annotateInit() {
	locale = getLocale();
	domain = getDomain();
	experiment = getExperiment();
	uri = getParameterByName("uri");

	populateFlags(locale);

	// Make sure user is logged in
	onLoggedIn = function(loginData) {
		setLinkLogo("profile");

		// Get domain settings before populating ui
		onDomain = function(domainData) {
			user = loginData.user;
			var userName = getUserName(loginData.user);
			ui = domainData.ui + "annotate";

			maybeRunExperiment();
			populateUI();
			populateNavbar(userName, [{link:"profile.html", name:"Profile"}]);
		};
		domainSettings = domainSettings(domain, onDomain);
	};
	// If user is not logged go to intro page
	onDismissal = function(){document.location.href="intro.html";};
	logUserIn(onLoggedIn, onDismissal);
}

function populateUI() {
	$.getJSON("ui_elements", {locale:locale, ui:ui, type:"labels"})
	.done(function(labels){
		document.title = labels.title;
		initLabels(labels);
		initImage();
		// Only show path when cluster is available
		if(localStorage.getItem("currentCluster") !== null)
			addPath();
		addButtonEvents();
		events();
	});
	metadata();
	annotations();
}

function initLabels(data) {
	$("#btnPrevious").append(data.btnPrevious);
	$("#btnNext").prepend(data.btnNext);
	$("#btnAnnotateRecommend").append(data.btnAnnotateRecommend);
	$("#btnAnnotateSearch").append(data.btnAnnotateSearch);
	vntFirstTitle = data.vntFirstTitle;
	vntFirstText = data.vntFirstText;
	// Add next to optional experiment navigation
	$("#btnExperimentNext").prepend(data.btnNext);
}

function initImage() {
	$.getJSON("metadata", {uri:uri})
	.done(function(metadata){
		$(".annotationImage").attr("src", metadata.image);
	});
}

function events() {
	$.getJSON("annotations", {uri:user, type:"user"})
	.done(function(annotations){
		uris = annotations;
		if(annotations.length===0) {
			alertMessage(vntFirstTitle, vntFirstText, 'success');
		}
	});
}

function addPath() {
	query = localStorage.getItem("query");
	var cluster = JSON.parse(localStorage.getItem("currentCluster"));
	$("#path").append(pathHtmlElements(cluster.path));
	unfoldPathEvent("#path", cluster.path);
	addClusterNavigationButtonEvents();
}

function addButtonEvents() {
	$("#btnAnnotateRecommend").click(function() {
		document.location.href="results.html" + "?user=" + user;
	});
	// Search on pressing enter
	$("#frmSearch").keypress(function(event) {
		if (event.which == 13) {
			var query = encodeURIComponent($("#frmSearch").val());
			document.location.href="results.html?query=" + query;
		}
	});
	$("#btnAnnotateSearch").click(function() {
		var query = encodeURIComponent($("#frmSearch").val());
		document.location.href="results.html?query=" + query;
	});
}

function addClusterNavigationButtonEvents() {
	var index = parseInt(localStorage.getItem("itemIndex"));
	var cluster = JSON.parse(localStorage.getItem("currentCluster"));
	var items = cluster.items;

	if(index === 0) {
		$("#btnPrevious").attr("disabled", "disabled");
	} else {
		$("#btnPrevious").click(function() {
			localStorage.setItem("itemIndex", index - 1);
			document.location.href= "annotate.html?uri=" + items[index -1].uri;
		});
	}

	if(index === items.length-1) {
		$("#btnNext").attr("disabled", "disabled");
	} else {
		$("#btnNext").click(function() {
			localStorage.setItem("itemIndex", index + 1);
			document.location.href= "annotate.html?uri=" + items[index + 1].uri;
		});
	}
}

function metadata() {
	if(displayOptions.showMetadata){
		// Get metadata from server
		$.getJSON("metadata", {uri:uri})
		.done(function(metadata){
			appendMetadataWell(metadata);
		});
	}
}

function appendMetadataWell(metadata) {
	$("#metadata").append(
		$.el.div({'class':'row'},
			$.el.div({'class':'col-md-10 col-md-offset-1'},
				$.el.div({'class':'well well-sm'},
				  $.el.h4('Showing metadata for ' + metadata.title),
					$.el.dl({'class':'dl-horizontal',
							 'id':'metadataList'})))));

	for(var i=0; i<metadata.properties.length; i++) {
		var encodedQuery = encodeURIComponent(metadata.properties[i].object_label);
		$("#metadataList").append(
			$.el.dt(metadata.properties[i].predicate_label));
		$("#metadataList").append(
			$.el.dd(
				$.el.a({'class':'r_undef',
					    'href':'results.html?query=' + encodedQuery},
					metadata.properties[i].object_label)));
	}
}

function annotations() {
	// Get annotations from server
	if(displayOptions.showAnnotations){
		$.getJSON("annotations", {uri:uri, type:"object"})
		.done(function(annotations){
			if(annotations.annotations.length > 0){
				$("#metadata").append(annotationWell(annotations));
			}
		});
	}
}

function annotationWell(annotations) {
	$("#metadata").append(
		$.el.div({'class':'row'},
			$.el.div({'class':'col-md-10 col-md-offset-1'},
				$.el.div({'class':'well well-sm'},
				  $.el.h4('Annotations for ' + annotations.title),
					$.el.dl({'class':'dl-horizontal',
							 'id':'annotationList'})))));


	for(var i=0; i<annotations.annotations.length; i++) {
		var encodedQuery = encodeURIComponent(annotations.annotations[i].body);
		$("#annotationList").append(
			$.el.dt(annotations.annotations[i].field));
		$("#annotationList").append(
			$.el.dd(
				$.el.a({'class':'r_undef',
					    'href':'results.html?query=' + encodedQuery},
					annotations.annotations[i].body)));
	}
}

var substringMatcher = function(strs) {
	return function findMatches(q, cb) {
		var matches, substringRegex;

		// an array that will be populated with substring matches
		matches = [];

		// regex used to determine if a string contains the substring `q`
		substrRegex = new RegExp(q, 'i');

		// iterate through the pool of strings and for any string that
		// contains the substring `q`, add it to the `matches` array
		$.each(strs, function(i, str) {
			if (substrRegex.test(str)) {
				matches.push(str);
			}
		});

		cb(matches);
	};
};

var pageType = ['Full page illustration',
	'Page that contains part of an illustration that is printed on more than one page',
	'Page that contains both text and small illustrations',
	'Page that contains both text and illuminated capitals',
	'Page that contains exclusively text',
	'Page that contains neither illustrations nor text'
];

$('#annotations .typeahead').typeahead({
	hint: true,
	highlight: true,
	minLength: 1
},
{
	name: 'pageType',
	source: substringMatcher(pageType)
});

function maybeRunExperiment() {
	// Hide some elements during an experiment
	if(experiment !== "none") {
		// Hide path if on annotate page
		$("#clusterNavigation").hide();
		// Don't show metadata
		displayOptions.showMetadata = false;
		// Don't show annotations of others
		displayOptions.showAnnotations = false;
		// Add big next button
		addExperimentNavigation();
	}
}

function addExperimentNavigation() {
	$("#metadata").before(
		$.el.div({'class':'row',
				  'id':'experimentNavigation'},
			$.el.button({'class':'btn btn-primary',
						 'id':'btnExperimentNext'})
		)
	);

	// Get the number of objects annotated
	$.getJSON("annotations", {uri:user, type:"user"})
	.done(function(annotations){
		var numberAnnotated = annotations.length;

		// Switch AB setting after 5 annotations
		if(numberAnnotated == 5) {
			var AorB = getAOrB();

			if(AorB === "recommend")
				setAOrB("random");
			if(AorB === "random")
				setAOrB("recommend")
		}

		// Add click event to navigation button
		$("#btnExperimentNext").click(function() {
			// Go to thank you page after 20 annotations else results
			if(numberAnnotated == 10) {
				document.location.href="end.html";
			} else {
				document.location.href="results.html" + "?user=" + user;
			}
		});
	});
}
