import 'dart:io';
import 'package:angel_framework/angel_framework.dart';
import 'package:http/http.dart' as http;
import 'package:json_god/json_god.dart' as god;
import 'package:test/test.dart';

@Middleware(const ['interceptor'])
testMiddlewareMetadata(RequestContext req, ResponseContext res) async {
  return "This should not be shown.";
}

@Middleware(const ['intercept_service'])
class QueryService extends Service {
  @override
  @Middleware(const ['interceptor'])
  read(id, [Map params]) {
    return params;
  }
}

main() {
  Angel angel;
  Angel nested;
  Angel todos;
  String url;
  http.Client client;

  setUp(() async {
    final debug = false;
    angel = new Angel(debug: debug);
    nested = new Angel(debug: debug);
    todos = new Angel(debug: debug);

    angel
      ..registerMiddleware('interceptor', (req, res) async {
        res.write('Middleware');
        return false;
      })
      ..registerMiddleware('intercept_service',
          (RequestContext req, res) async {
        print("Intercepting a service!");
        return true;
      });

    todos.get('/action/:action', (req, res) => res.json(req.params));

    Route ted;

    ted = nested.post('/ted/:route', (RequestContext req, res) {
      print('Params: ${req.params}');
      print('Path: ${ted.path}, matcher: ${ted.matcher.pattern}, uri: ${req.path}');
      return req.params;
    });

    angel.use('/nes', nested);
    angel.get('/meta', testMiddlewareMetadata);
    angel.get('/intercepted', 'This should not be shown',
        middleware: ['interceptor']);
    angel.get('/hello', 'world');
    angel.get('/name/:first/last/:last', (req, res) => req.params);
    angel.post('/lambda', (req, res) => req.body);
    angel.use('/todos/:id', todos);
    angel
        .get('/greet/:name',
            (RequestContext req, res) async => "Hello ${req.params['name']}")
        .as('Named routes');
    angel.get('/named', (req, ResponseContext res) async {
      res.redirectTo('Named routes', {'name': 'tests'});
    });
    angel.get('/log', (RequestContext req, res) async {
      print("Query: ${req.query}");
      return "Logged";
    });

    angel.use('/query', new QueryService());
    angel.get('*', 'MJ');

    angel.dumpTree(header: "DUMPING ROUTES:");

    client = new http.Client();
    await angel.startServer(InternetAddress.LOOPBACK_IP_V4, 0);
    url = "http://${angel.httpServer.address.host}:${angel.httpServer.port}";
  });

  tearDown(() async {
    await angel.httpServer.close(force: true);
    angel = null;
    nested = null;
    todos = null;
    client.close();
    client = null;
    url = null;
  });

  test('Can match basic url', () async {
    var response = await client.get("$url/hello");
    expect(response.body, equals('"world"'));
  });

  test('Can match url with multiple parameters', () async {
    var response = await client.get('$url/name/HELLO/last/WORLD');
    print(response.body);
    var json = god.deserialize(response.body);
    expect(json['first'], equals('HELLO'));
    expect(json['last'], equals('WORLD'));
  });

  test('Can nest another Angel instance', () async {
    var response = await client.post('$url/nes/ted/foo');
    var json = god.deserialize(response.body);
    expect(json['route'], equals('foo'));
  });

  test('Can parse parameters from a nested Angel instance', () async {
    var response = await client.get('$url/todos/1337/action/test');
    var json = god.deserialize(response.body);
    print('JSON: $json');
    expect(json['id'], equals(1337));
    expect(json['action'], equals('test'));
  });

  test('Can add and use named middleware', () async {
    var response = await client.get('$url/intercepted');
    expect(response.body, equals('Middleware'));
  });

  test('Middleware via metadata', () async {
    // Metadata
    var response = await client.get('$url/meta');
    expect(response.body, equals('Middleware'));
  });

  test('Can serialize function result as JSON', () async {
    Map headers = {'Content-Type': 'application/json'};
    String postData = god.serialize({'it': 'works'});
    var response =
        await client.post("$url/lambda", headers: headers, body: postData);
    expect(god.deserialize(response.body)['it'], equals('works'));
  });

  test('Fallback routes', () async {
    var response = await client.get('$url/my_favorite_artist');
    expect(response.body, equals('"MJ"'));
  });

  test('Can name routes', () {
    Route foo = new Route('/framework/:id', name: 'frm');
    print('Foo: $foo');
    String uri = foo.makeUri({'id': 'angel'});
    print(uri);
    expect(uri, equals('framework/angel'));
  });

  test('Redirect to named routes', () async {
    var response = await client.get('$url/named');
    print(response.body);
    expect(god.deserialize(response.body), equals('Hello tests'));
  });

  test('Match routes, even with query params', () async {
    var response =
        await client.get("$url/log?foo=bar&bar=baz&baz.foo=bar&baz.bar=foo");
    print(response.body);
    expect(god.deserialize(response.body), equals('Logged'));

    response = await client.get("$url/query/foo?bar=baz");
    print(response.body);
    expect(response.body, equals("Middleware"));
  });
}
