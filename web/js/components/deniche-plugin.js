/* Annotorious plugin to use the annotation editor from the
 * ClioPatria image_annotation cpack package as the editor for
 * shapes created in Annotorious.
 *
 * To this, we need to solve three issues:
 *
 * 1. We need to communicate the shape that the user created within
 *    annotorious to all annotation field objects of the cpack.
 *    This is why the plugin has a public member variable 'currentShape'
 *    that the cpack fields can access.
 *
 * 2. The cpack data model assumes multiple annotation can be made on
 *    the same target, while annotorious can have only one.
 *    As a result, we need to collect all tags for the same target and
 *    merge them into a single annotation for annotorious.
 *    This is done in the 'cleantags' array, which is indexed on targetId.
 *
 * 3. While the annotorious editor is open, the user can add and remove
 *    individual tags using the cpack user interface. But we can only
 *    add/rm the final merged tag using the annotorious API when the
 *    editor is closed. As a result, we need to do some bookkeeping
 *    ourselves in the _dirtytag variable, and update annotorious when
 *    the editor is closed by flushing out all changes made to the current
 *    dirty tag.
 *
 * Apart from these issues above, the approach is quite straight forward:
 *
 * 1. We simple move the cpack editor as a plugin field into the annotorious
 *    editor.
 * 2. We hijack the cancel/save buttons of annotorious for our own purposes.
 * 3. We bind handler functions on all relevant events generated by annotorious.
 *
 * @author: Jacco van Ossenbruggen
 *
 * */

annotorious.plugin.DenichePlugin = function() {
    /** @public **/
	this.currentShape = null; // Should be accessible by cpack objects

	/** @private **/
	this._cleantags = []; // tags annotorious already knows about
	this._dirtytag = null; // tag annotorious doesn't know yet
	this._saveButtons = {}; // we have multiple buttons if we have multiple images per page
	this._cancelButtons = {};
}

annotorious.plugin.DenichePlugin.states = {EMPTY:'empty', SOME:'some'};

annotorious.plugin.DenichePlugin.prototype.onInitAnnotator = function(annotator) {
    this.annotator = annotator;
	var el =  annotator.element;

	// remove standard textarea
	var textArea = el.getElementsByTagName('textarea')[0];
	textArea.parentNode.removeChild(textArea);

	// move the cpack editor into the annotorious editor:
    var fieldsId = el.getElementsByTagName('img')[0].getAttribute('fields');
    var imageId  = el.getElementsByTagName('img')[0].getAttribute('id');
    var fieldsEl = document.getElementById(fieldsId);
    annotator.editor.addField(fieldsEl);

    // install all handlers on events created by annotorious:
    this.installHandlers();

	// get existing annotations on init annotorious
    if (this._anno.fields) {
		var fields = this._anno.fields[imageId][fieldsId];
		for (var i in fields) {
			var field = fields[i];
			if (field.showAnnotations) field.getAnnotations();
		}
    }
}

annotorious.plugin.DenichePlugin.prototype.initPlugin = function(anno) {
	this._anno = anno;	// make sure we know annotorious ...
	this._anno._deniche = this; // and annotorious knows us
}

annotorious.plugin.DenichePlugin.prototype.toggleButtons = function(state, fieldsId) {
	if (!this._cancelButtons[fieldsId]) return;
	if (!state) state = annotorious.plugin.DenichePlugin.states.SOME;
	if (state == annotorious.plugin.DenichePlugin.states.SOME) {
		this._cancelButtons[fieldsId].style.display="none";
		this._saveButtons[fieldsId].style.display="inline-block";
	} else if (state == annotorious.plugin.DenichePlugin.states.EMPTY) {
		this._saveButtons[fieldsId].style.display="none";
		this._cancelButtons[fieldsId].style.display="inline-block";
	}
}

annotorious.plugin.DenichePlugin.prototype.filterTags = function(targetId, fieldsId) {
	// Filter tags to show only the ones with the same selector
	var oSelf = this;
	var editor = $(".annotorious-editor")[0];
	var selector = '#'+ fieldsId + ' .lblAnnotation';
	if (!fieldsId) selector = '.lblAnnotation';

	$(editor).find(selector).each(function(index, annotation) {
		// See if id matches the (current?) target
		if (targetId == $(annotation).attr("targetId")) {
			$(annotation).show();
		} else {
			$(annotation).hide();
		}
	});
}

annotorious.plugin.DenichePlugin.prototype.removeAnnotation = function (label, targetId) {
	var old = this._dirtytag;
	if (!old) old = this._cleantags[targetId];
	if (old) {
		var annotation = JSON.parse(JSON.stringify(old)); // deep copy
		var index = old.compound_text.indexOf(label);
		annotation.compound_text = old.compound_text.splice(index, 1);
		annotation.text = old.compound_text.join(', ');
		this._dirtytag = annotation;
	}
}

annotorious.plugin.DenichePlugin.prototype.onFragmentCancel = function(ev) {
	this.annotator.stopSelection();
	this.annotator.editor.close();
}

annotorious.plugin.DenichePlugin.prototype.addAnnotation = function (annotation, update) {
	var old = this._dirtytag;
	if (!old) old = this._cleantags[ annotation.targetId ];

	if (old) {
		// extend new annotation by merging in old one
		annotation.compound_text = old.compound_text;
		annotation.compound_text.push(annotation.text);
		annotation.text = annotation.compound_text.join(', ');
	} else {
		annotation.compound_text = [ annotation.text ];
	}
	
	if (update) {
		this._cleantags[annotation.targetId] = annotation;
		this._anno.addAnnotation(annotation, old);
	} else {
		this._dirtytag = annotation;
	}

	this.toggleButtons(annotorious.plugin.DenichePlugin.states.SOME, annotation.fieldsId);
	this.filterTags(annotation.targetId, annotation.fieldsId); // only show tags for this shape
}

annotorious.plugin.DenichePlugin.prototype.flushDirtyAnnotation = function(original) {
	var dirty = this._dirtytag;
	this._dirtytag = null;
	if (dirty) {
		if (dirty.text) {
			this._anno.addAnnotation(dirty,original);
			this._cleantags[dirty.targetId] = dirty;
		} else {
			this._anno.removeAnnotation(original);
			this._cleantags[dirty.targetId] = null;
		}
	}
}

annotorious.plugin.DenichePlugin.prototype.installHandlers = function() {
	var oSelf = this;

	this._anno.addHandler('onSelectionCompleted', function(event) {
		oSelf.currentShape = event.shape;
		var currentFieldsId = event.mouseEvent.target.parentNode.getElementsByTagName('img')[0].getAttribute('fields');
		oSelf.toggleButtons(annotorious.plugin.DenichePlugin.states.EMPTY, currentFieldsId);
	});

	this._anno.addHandler('onEditorShown', function(annotation) {
		// get the annotorious save and cancel button so we can manipulate them:
		var node = oSelf.annotator.element;

		oSelf._saveButtons[annotation.fieldsId] = $(".annotorious-editor-button-save").get(0);
		oSelf._cancelButtons[annotation.fieldsId] = $(".annotorious-editor-button-cancel").get(0);
		oSelf._saveButtons[annotation.fieldsId].innerHTML = "Done";

		// Set focus on first field (exlude hint input field introduced by twitter typeahead)
		$(".annotorious-editor input").not(".tt-hint")[0].focus();

		oSelf._dirtytag = null;
		if (annotation && annotation.shapes) {
			oSelf.currentShape = annotation.shapes[0];
			oSelf.toggleButtons(annotorious.plugin.DenichePlugin.states.SOME, annotation.fieldsId);
			oSelf.filterTags(annotation.targetId, annotation.fieldsId); // only show tags for this shape
		} else {
			oSelf.filterTags(null, null);	// hide all tags
		}
	});

	this._anno.addHandler('onAnnotationCreated', function(original) {
		oSelf.flushDirtyAnnotation(original);
	});

	this._anno.addHandler('onAnnotationUpdated', function(original) {
		oSelf.flushDirtyAnnotation(original);
	});
}