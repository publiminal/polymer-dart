// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Includes any additional polyfills that may needed by the deployed app.
library polymer.src.build.polyfill_injector;

import 'dart:async';

import 'package:barback/barback.dart';
import 'package:html5lib/dom.dart'
    show Document, DocumentFragment, Element, Node;
import 'package:html5lib/parser.dart' show parseFragment;
import 'package:code_transformers/messages/build_logger.dart';
import 'common.dart';

/// Ensures that any scripts and polyfills needed to run a polymer application
/// are included.
///
/// This step also replaces "packages/browser/dart.js" and the Dart script tag
/// with a script tag that loads the dart2js compiled code directly.
class PolyfillInjector extends Transformer with PolymerTransformer {
  final TransformOptions options;

  PolyfillInjector(this.options);

  /// Only run on entry point .html files.
  bool isPrimary(AssetId id) => options.isHtmlEntryPoint(id);

  Future apply(Transform transform) {
    var logger = new BuildLogger(transform,
        convertErrorsToWarnings: !options.releaseMode,
        detailsUri: 'http://goo.gl/5HPeuP');
    return readPrimaryAsHtml(transform, logger).then((document) {
      bool dartSupportFound = false;
      Element webComponentsJs;
      Element dartJs;
      final dartScripts = <Element>[];

      for (var tag in document.querySelectorAll('script')) {
        var src = tag.attributes['src'];
        if (src != null) {
          var last = src.split('/').last;
          if (_webComponentsJS.hasMatch(last)) {
            webComponentsJs = tag;
          } else if (_platformJS.hasMatch(last)) {
            tag.attributes['src'] =
                src.replaceFirst(_platformJS, 'webcomponents.min.js');
            webComponentsJs = tag;
          } else if (_dartSupportJS.hasMatch(last)) {
            dartSupportFound = true;
          } else if (last == 'dart.js') {
            dartJs = tag;
          }
        }

        if (tag.attributes['type'] == 'application/dart') {
          dartScripts.add(tag);
        }
      }

      if (dartScripts.isEmpty) {
        // This HTML has no Dart code, there is nothing to do here.
        transform.addOutput(transform.primaryInput);
        return;
      }

      // Remove "packages/browser/dart.js". It is not needed in release mode,
      // and in debug mode we want to ensure it is the last script on the page.
      if (dartJs != null) dartJs.remove();

      // TODO(jmesserly): ideally we would generate an HTML that loads
      // dart2dart too. But for now dart2dart is not a supported deployment
      // target, so just inline the JS script. This has the nice side effect of
      // fixing our tests: even if content_shell supports Dart VM, we'll still
      // test the compiled JS code.
      if (options.directlyIncludeJS) {
        // Replace all other Dart script tags with JavaScript versions.
        for (var script in dartScripts) {
          final src = script.attributes['src'];
          if (src.endsWith('.dart')) {
            script.attributes.remove('type');
            script.attributes['src'] = '$src.js';
            // TODO(sigmund): we shouldn't need 'async' here. Remove this
            // workaround for dartbug.com/19653.
            script.attributes['async'] = '';
          }
        }
      } else {
        document.body.nodes.add(
            parseFragment('<script src="packages/browser/dart.js"></script>'));
      }

      _addScriptFirst(urlSegment) {
        document.head.nodes.insert(
            0, parseFragment('<script src="packages/$urlSegment"></script>\n'));
      }

      // Inserts dart_support.js either at the top of the document or directly
      // after webcomponents.js if it exists.
      if (!dartSupportFound) {
        if (webComponentsJs == null) {
          _addScriptFirst('web_components/dart_support.js');
        } else {
          var parentsNodes = webComponentsJs.parentNode.nodes;
          parentsNodes.insert(parentsNodes.indexOf(webComponentsJs) + 1,
              parseFragment(
                  '\n<script src="packages/web_components/dart_support.js">'
                  '</script>'));
        }
      }

      // By default webcomponents.js should come before all other scripts.
      if (webComponentsJs == null && options.injectWebComponentsJs) {
        var suffix = options.releaseMode ? '.min.js' : '.js';
        _addScriptFirst('web_components/webcomponents$suffix');
      }

      transform.addOutput(
          new Asset.fromString(transform.primaryInput.id, document.outerHtml));
    });
  }
}

final _platformJS = new RegExp(r'platform.*\.js', caseSensitive: false);
final _webComponentsJS =
    new RegExp(r'webcomponents.*\.js', caseSensitive: false);
final _dartSupportJS = new RegExp(r'dart_support.js', caseSensitive: false);
