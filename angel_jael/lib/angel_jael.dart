import 'dart:convert';
import 'package:angel_framework/angel_framework.dart';
import 'package:code_buffer/code_buffer.dart';
import 'package:file/file.dart';
import 'package:jael/jael.dart';
import 'package:jael_preprocessor/jael_preprocessor.dart';
import 'package:symbol_table/symbol_table.dart';

/// Configures an Angel server to use Jael to render templates.
///
/// To enable "minified" output, you need to override the [createBuffer] function,
/// to instantiate a [CodeBuffer] that emits no spaces or line breaks.
AngelConfigurer jael(Directory viewsDirectory,
    {String fileExtension, bool cacheViews: false, CodeBuffer createBuffer()}) {
  var cache = <String, Document>{};
  fileExtension ??= '.jl';
  createBuffer ??= () => new CodeBuffer();

  return (Angel app) async {
    app.viewGenerator = (String name, [Map locals]) async {
      var errors = <JaelError>[];
      Document processed;

      if (cacheViews == true && cache.containsKey(name)) {
        processed = cache[name];
      } else {
        var file = viewsDirectory.childFile(name + fileExtension);
        var contents = await file.readAsString();
        var doc =
        parseDocument(contents, sourceUrl: file.uri, onError: errors.add);
        processed = doc;

        try {
          processed = await resolve(doc, viewsDirectory, onError: errors.add);
        } catch (_) {
          // Ignore these errors, so that we can show syntax errors.
        }

        if (cacheViews == true) {
          cache[name] = processed;
        }
      }

      var buf = createBuffer();
      var scope = new SymbolTable(values: locals ?? {});

      if (errors.isEmpty) {
        try {
          const Renderer().render(processed, buf, scope);
          return buf.toString();
        } on JaelError catch (e) {
          errors.add(e);
        }
      }

      buf
        ..writeln('<!DOCTYPE html>')
        ..writeln('<html lang="en">')
        ..indent()
        ..writeln('<head>')
        ..indent()
        ..writeln(
          '<meta name="viewport" content="width=device-width, initial-scale=1">',
        )
        ..writeln('<title>${errors.length} Error(s)</title>')
        ..outdent()
        ..writeln('</head>')
        ..writeln('<body>')
        ..writeln('<h1>${errors.length} Error(s)</h1>')
        ..writeln('<ul>')
        ..indent();

      for (var error in errors) {
        var type =
            error.severity == JaelErrorSeverity.warning ? 'warning' : 'error';
        buf
          ..writeln('<li>')
          ..indent()
          ..writeln(
              '<b>$type:</b> ${error.span.start.toolString}: ${error.message}')
          ..writeln('<br>')
          ..writeln(
            '<span style="color: red;">' +
                HTML_ESCAPE
                    .convert(error.span.highlight(color: false))
                    .replaceAll('\n', '<br>') +
                '</span>',
          )
          ..outdent()
          ..writeln('</li>');
      }

      buf
        ..outdent()
        ..writeln('</ul>')
        ..writeln('</body>')
        ..writeln('</html>');

      return buf.toString();
    };
  };
}
