import 'dart:async';
import 'dart:convert' show json;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'package:sign_in_button/sign_in_button.dart';

import '../../home.dart';



const List<String> scopes = <String>[
  'email',
  'https://www.googleapis.com/auth/drive.appdata',
];



GoogleSignIn _googleSignIn = GoogleSignIn(
  // Optional clientId
  // clientId: 'your-client_id.apps.googleusercontent.com',
  scopes: scopes,
);






class SignIn extends StatefulWidget {
  ///
  const SignIn({super.key});

  @override
  State createState() => _SignInState();
}

class _SignInState extends State<SignIn> {
  GoogleSignInAccount? _currentUser;

  bool _isAuthorized = false; 

  @override
  void initState() {
    super.initState();

    _googleSignIn.onCurrentUserChanged
        .listen((GoogleSignInAccount? account) async {
// #docregion CanAccessScopes
      // In mobile, being authenticated means being authorized...
      bool isAuthorized = account != null;
      // However, on web...
      if (kIsWeb && account != null) {
        isAuthorized = await _googleSignIn.canAccessScopes(scopes);
      }
// #enddocregion CanAccessScopes

      setState(() {
        _currentUser = account;
        _isAuthorized = isAuthorized;
      });

      // Now that we know that the user can access the required scopes, the app
      // can call the REST API.
      if (isAuthorized) {
        //unawaited(/*to DO */);
      }
    });

    // In the web, _googleSignIn.signInSilently() triggers the One Tap UX.
    //
    // It is recommended by Google Identity Services to render both the One Tap UX
    // and the Google Sign In button together to "reduce friction and improve
    // sign-in rates" ([docs](https://developers.google.com/identity/gsi/web/guides/display-button#html)).
    _googleSignIn.signInSilently();
  }


  Future<void> _handleSignIn() async {
    try {
      await _googleSignIn.signIn();
    } catch (error) {
      print(error);
    }
  }
 

  Future<void> _handleAuthorizeScopes() async {
    final bool isAuthorized = await _googleSignIn.requestScopes(scopes);
    // #enddocregion RequestScopes
    setState(() {
      _isAuthorized = isAuthorized;
    });
    // #docregion RequestScopes
    if (isAuthorized) {
      //unawaited(/*TODO*/);
    }
    // #enddocregion RequestScopes
  }

  Future<void> listAppDataFiles() async {
    if (_currentUser == null) return;

    final auth = await _currentUser!.authentication;
    final accessToken = auth.accessToken;

    if (accessToken == null) {
      print('No se pudo obtener el token de acceso.');
      return;
    }

    final response = await http.get(
      Uri.parse(
        'https://www.googleapis.com/drive/v3/files?spaces=appDataFolder&pageSize=10&fields=files(id,name)',
      ),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      print('Archivos en appDataFolder:');
      for (var file in data['files']) {
        print(' - ${file['name']} (${file['id']})');
      }
    } else {
      print('Error al obtener archivos: ${response.statusCode}');
      print(response.body);
    }
  }

  Future<void> downloadFile({required fileId, required fileName}) async {
    if (_currentUser == null) return;

    final auth = await _currentUser!.authentication;
    final accessToken = auth.accessToken;

    if (accessToken == null) {
      print('No se pudo obtener el token de acceso.');
      return;
    }

    final response = await http.get(
      Uri.parse(
        'https://www.googleapis.com/drive/v3/files/$fileId?alt=media',
      ),
      headers: {
        'Authorization': 'Bearer $accessToken',
      },
    );

    if (response.statusCode == 200) {
      final bytes = response.bodyBytes;
      // Obtener ruta para guardar
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$fileName');

      // Guardar archivo
      await file.writeAsBytes(bytes);
      print('Archivo guardado en: ${file.path}');
    } else {
      print('Error en la descarga del archivo: ${response.statusCode}');
    }
  }


  Future<void> deleteFile({required fileId}) async {
    if (_currentUser == null) return;

    final auth = await _currentUser!.authentication;
    final accessToken = auth.accessToken;

    if (accessToken == null) {
      print('No se pudo obtener el token de acceso.');
      return;
    }

    final response = await http.delete(
      Uri.parse(
        'https://www.googleapis.com/drive/v3/files/$fileId',
      ),
      headers: {
        'Authorization': 'Bearer $accessToken',
      },
    );

    if (response.statusCode == 204) {
      print('Archivo eliminado con exito');
    } else {
      print('Error en la eliminacion del archivo: ${response.statusCode}');
    }
  }

  Future<void> uploadAppDataFile({required GoogleSignInAccount currentUser, required String fileName, required Map<String, dynamic> jsonData, required bool patch, fileId}) async {
    final auth = await currentUser.authentication;
    final accessToken = auth.accessToken;
    if (accessToken == null) {
      print('No se pudo obtener el token de acceso.');
      return;
    }

    // Metadata del archivo (nombre y padre)
    final metadata = patch
        ? json.encode({
      "name": fileName, //solo el nombre si deseas cambiarlo
    })
        : json.encode({
      "name": fileName,
      "parents": ["appDataFolder"], //Solo al CREAR
    });


    // Contenido JSON convertido a String
    final content = json.encode(jsonData);

    // Boundary para multipart
    final boundary = "foo_bar_baz";

    // Construimos el cuerpo multipart
    final body = '''
--$boundary
Content-Type: application/json; charset=UTF-8

$metadata
--$boundary
Content-Type: application/json

$content
--$boundary--
''';

    Uri url;
    http.Response response;
    if (patch){
      url = Uri.parse('https://www.googleapis.com/upload/drive/v3/files/$fileId?uploadType=multipart');

      response = await http.patch(
        url,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'multipart/related; boundary=$boundary',
        },
        body: body,
      );
    }else{
      url = Uri.parse('https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart');

      response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'multipart/related; boundary=$boundary',
        },
        body: body,
      );
    }




    if (response.statusCode == 200) {
      final respJson = json.decode(response.body);
      if (patch){
        print('Archivo modificado con ID: ${respJson['id']}');
      }
      else{
        print('Archivo creado con ID: ${respJson['id']}');
      }

    } else {
      print('Error al crear archivo: ${response.statusCode}');
      print(response.body);
    }
  }

  Future<void> _handleSignOut() => _googleSignIn.disconnect();

  Widget _buildBody() {
    final GoogleSignInAccount? user = _currentUser;
    if (user != null) {
      // Usuario autenticado
      return Column(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: <Widget>[
          ListTile(
            leading: GoogleUserCircleAvatar(identity: user),
            title: Text(user.displayName ?? ''),
            subtitle: Text(user.email),
          ),
          const Text('Signed in successfully.'),
          if (_isAuthorized) ...<Widget>[
            Text("TODO"),
            ElevatedButton(
              child: const Text('REFRESH'),
              onPressed: () {
                // TODO: implementar refresh
              },
            ),
          ],
          if (!_isAuthorized) ...<Widget>[
            const Text('Additional permissions needed to read your contacts.'),
            ElevatedButton(
              onPressed: _handleAuthorizeScopes,
              child: const Text('REQUEST PERMISSIONS'),
            ),
          ],
          ElevatedButton(
            onPressed: _handleSignOut,
            child: const Text('SIGN OUT'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => Home()),
              );
            },
            child: const Text('Go to Home'),
          ),
          ElevatedButton(
            child: const Text('Listar archivos en appDataFolder'),
            onPressed: listAppDataFiles,
          ),
          ElevatedButton(
            onPressed: () {
              if (_currentUser != null) {
                uploadAppDataFile(
                  currentUser: _currentUser!,
                  fileName: 'config.json',
                  jsonData: {
                    "songs": [
                      {"id": "1", "title": "Canción 1"},
                      {"id": "2", "title": "Canción 2"},
                    ],
                  },
                  patch: false
                );
              }
            },
            child: Text('Subir archivo config.json'),
          ),
          ElevatedButton(
            child: const Text('Download test'),
            onPressed: () {downloadFile(fileId: '1g_I1Er-vzA97zb2KHAGzNEaHsC_vMh9DSlvghwKcYRJVIOxz5A', fileName: 'config.json');},
          ),
          ElevatedButton(
            child: const Text('Delete test'),
            onPressed: () {deleteFile(fileId: '1g_I1Er-vzA97zb2KHAGzNEaHsC_vMh9DSlvghwKcYRJVIOxz5A');},
          ),
          ElevatedButton(
            onPressed: () {
              if (_currentUser != null) {
                uploadAppDataFile(
                    currentUser: _currentUser!,
                    fileName: 'config.json',
                    jsonData: {
                      "songs": [
                        {"id": "1", "test": "testttttt"},
                        {"id": "2", "title": "Canción 2"},
                      ],
                    },
                    patch: true,
                    fileId: '1xlm0QKbgdtUFxA9UxzB-TPQwailQAWFdV0cBj43ysB3anWGcRw'
                );
              }
            },
            child: Text('modificar config.json'),
          ),


        ],
      );
    } else {
      // Usuario no autenticado
      return Column(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: <Widget>[
          const Text('You are not currently signed in.'),
          SignInButton(
            Buttons.google,
            onPressed: _handleSignIn,
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => Home()),
              );
            },
            child: const Text('Continue without login'),
          ),
        ],
      );
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: const Text('Google Sign In'),
        ),
        body: ConstrainedBox(
          constraints: const BoxConstraints.expand(),
          child: _buildBody(),
        ));
  }
}