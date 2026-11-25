import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  static const String clientId = '14fa6a2074a94f229d1d74bde68d5d19';
  // Flutter Web callback: use the same origin as the running Spendly app.
  static String get redirectUri => '${Uri.base.origin}/';

  String? accessToken;
  bool loading = false;
  bool searching = false;
  String? error;
  String query = '';

  final TextEditingController searchController = TextEditingController();
  List<dynamic> tracks = [];
  List<dynamic> artists = [];
  List<dynamic> albums = [];

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> _restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('spotify_access_token');
    final expiry = prefs.getInt('spotify_expiry') ?? 0;

    if (token != null && DateTime.now().millisecondsSinceEpoch < expiry) {
      if (mounted) setState(() => accessToken = token);
      return;
    }

    final refreshToken = prefs.getString('spotify_refresh_token');
    if (refreshToken != null) {
      await _refreshToken(refreshToken);
      return;
    }

    // Spotify redirects back to this page with an authorization code.
    final params = Uri.base.queryParameters;
    if (params.containsKey('code')) {
      await _exchangeCode(params['code']!);
    } else if (params.containsKey('error')) {
      if (mounted) {
        setState(() => error = 'Spotify authorization was not completed.');
      }
    }
  }

  String _randomString(int length) {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => chars[random.nextInt(chars.length)],
    ).join();
  }

  String _base64Url(List<int> bytes) {
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  Future<void> connectSpotify() async {
    setState(() {
      loading = true;
      error = null;
    });

    try {
      final verifier = _randomString(64);
      final state = _randomString(32);
      final challenge = _base64Url(
        sha256.convert(utf8.encode(verifier)).bytes,
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('spotify_code_verifier', verifier);
      await prefs.setString('spotify_state', state);

      final authUri = Uri.https(
        'accounts.spotify.com',
        '/authorize',
        {
          'client_id': clientId,
          'response_type': 'code',
          'redirect_uri': redirectUri,
          'code_challenge_method': 'S256',
          'code_challenge': challenge,
          'state': state,
        },
      );

      await launchUrl(
        authUri,
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      if (mounted) setState(() => error = 'Could not open Spotify: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _exchangeCode(String code) async {
    final prefs = await SharedPreferences.getInstance();

    // Avoid exchanging the same callback code again after a page refresh.
    final existingToken = prefs.getString('spotify_access_token');
    final existingExpiry = prefs.getInt('spotify_expiry') ?? 0;
    if (existingToken != null &&
        DateTime.now().millisecondsSinceEpoch < existingExpiry) {
      if (mounted) setState(() => accessToken = existingToken);
      return;
    }

    final verifier = prefs.getString('spotify_code_verifier');
    final expectedState = prefs.getString('spotify_state');
    final receivedState = Uri.base.queryParameters['state'];

    if (verifier == null ||
        expectedState == null ||
        receivedState != expectedState) {
      if (mounted) {
        setState(() => error = 'Spotify login verification failed. Try again.');
      }
      return;
    }

    setState(() {
      loading = true;
      error = null;
    });

    try {
      final response = await http.post(
        Uri.parse('https://accounts.spotify.com/api/token'),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'client_id': clientId,
          'grant_type': 'authorization_code',
          'code': code,
          'redirect_uri': redirectUri,
          'code_verifier': verifier,
        },
      );

      final data = jsonDecode(response.body);

      if (response.statusCode != 200) {
        throw Exception(
            data['error_description'] ?? data['error'] ?? response.body);
      }

      await _saveToken(data);

      if (mounted) {
        setState(() {
          accessToken = data['access_token'];
          loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          error = 'Spotify login failed: $e';
        });
      }
    }
  }

  Future<void> _saveToken(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    final expiry = DateTime.now().millisecondsSinceEpoch +
        ((data['expires_in'] as num).toInt() * 1000);

    await prefs.setString('spotify_access_token', data['access_token']);
    await prefs.setInt('spotify_expiry', expiry);

    if (data['refresh_token'] != null) {
      await prefs.setString('spotify_refresh_token', data['refresh_token']);
    }
  }

  Future<void> _refreshToken(String refreshToken) async {
    try {
      final response = await http.post(
        Uri.parse('https://accounts.spotify.com/api/token'),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'client_id': clientId,
          'grant_type': 'refresh_token',
          'refresh_token': refreshToken,
        },
      );

      final data = jsonDecode(response.body);
      if (response.statusCode != 200) {
        throw Exception(data['error_description'] ?? 'Token refresh failed');
      }

      await _saveToken(data);
      if (mounted) setState(() => accessToken = data['access_token']);
    } catch (e) {
      if (mounted) {
        setState(() => error = 'Please reconnect Spotify: $e');
      }
    }
  }

  Future<String> _validToken() async {
    final prefs = await SharedPreferences.getInstance();
    final expiry = prefs.getInt('spotify_expiry') ?? 0;

    if (accessToken != null &&
        DateTime.now().millisecondsSinceEpoch < expiry - 60000) {
      return accessToken!;
    }

    final refresh = prefs.getString('spotify_refresh_token');
    if (refresh == null) throw Exception('Please connect Spotify again.');

    await _refreshToken(refresh);
    if (accessToken == null) throw Exception('Spotify session expired.');
    return accessToken!;
  }

  Future<void> searchSpotify(String value) async {
    if (value.trim().isEmpty) return;

    setState(() {
      searching = true;
      error = null;
      query = value.trim();
    });

    try {
      final token = await _validToken();

      final uri = Uri.https(
        'api.spotify.com',
        '/v1/search',
        {
          'q': value.trim(),
          'type': 'track,artist,album',
          'limit': '10',
        },
      );

      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );

      final data = jsonDecode(response.body);

      if (response.statusCode != 200) {
        throw Exception(data['error']?['message'] ?? response.body);
      }

      if (!mounted) return;

      setState(() {
        tracks = data['tracks']?['items'] ?? [];
        artists = data['artists']?['items'] ?? [];
        albums = data['albums']?['items'] ?? [];
        searching = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          searching = false;
          error = 'Search failed: $e';
        });
      }
    }
  }

  Future<void> openSpotify(String? url) async {
    if (url == null || url.isEmpty) return;

    final uri = Uri.tryParse(url);
    if (uri == null) return;

    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> disconnectSpotify() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('spotify_access_token');
    await prefs.remove('spotify_refresh_token');
    await prefs.remove('spotify_expiry');

    if (mounted) {
      setState(() {
        accessToken = null;
        tracks = [];
        artists = [];
        albums = [];
      });
    }
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 12),
      child: Text(
        title,
        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _trackTile(dynamic track) {
    final album = track['album'] ?? {};
    final images = album['images'] as List? ?? [];
    final image = images.isNotEmpty ? images.first['url'] : null;
    final names = (track['artists'] as List? ?? [])
        .map((artist) => artist['name'])
        .join(', ');

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 4),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: image != null
            ? Image.network(
                image,
                width: 55,
                height: 55,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.music_note, size: 35),
              )
            : const Icon(Icons.music_note, size: 35),
      ),
      title: Text(
        track['name'] ?? 'Unknown track',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        names,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton(
        icon: const Icon(Icons.play_circle_fill_rounded, size: 34),
        onPressed: () => openSpotify(track['external_urls']?['spotify']),
      ),
      onTap: () => openSpotify(track['external_urls']?['spotify']),
    );
  }

  Widget _artistTile(dynamic artist) {
    final images = artist['images'] as List? ?? [];
    final image = images.isNotEmpty ? images.first['url'] : null;

    return SizedBox(
      width: 125,
      child: Column(
        children: [
          CircleAvatar(
            radius: 48,
            backgroundImage: image != null ? NetworkImage(image) : null,
            child: image == null ? const Icon(Icons.person, size: 40) : null,
          ),
          const SizedBox(height: 9),
          Text(
            artist['name'] ?? 'Artist',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Text(
            'Artist',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _albumTile(dynamic album) {
    final images = album['images'] as List? ?? [];
    final image = images.isNotEmpty ? images.first['url'] : null;

    return SizedBox(
      width: 145,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: image != null
                ? Image.network(
                    image,
                    width: 145,
                    height: 145,
                    fit: BoxFit.cover,
                  )
                : Container(
                    width: 145,
                    height: 145,
                    color: Colors.black12,
                    child: const Icon(Icons.album, size: 45),
                  ),
          ),
          const SizedBox(height: 8),
          Text(
            album['name'] ?? 'Album',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Text(
            (album['artists'] as List? ?? [])
                .map((artist) => artist['name'])
                .join(', '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: dark ? const Color(0xFF101116) : const Color(0xFFF5F6FA),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 30),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'SPENDLY',
                            style: TextStyle(
                              fontSize: 12,
                              letterSpacing: 3,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 5),
                          Text(
                            'Discover',
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      if (accessToken != null)
                        IconButton(
                          tooltip: 'Disconnect Spotify',
                          onPressed: disconnectSpotify,
                          icon: const Icon(Icons.logout_rounded),
                        ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF243B55), Color(0xFF141E30)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'YOUR NEXT\nFAVOURITE SONG',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 25,
                            height: 1.15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 10),
                        Text(
                          'Explore music, artists and sounds worth discovering.',
                          style: TextStyle(color: Colors.white70),
                        ),
                        SizedBox(height: 18),
                        Row(
                          children: [
                            Icon(Icons.graphic_eq, color: Colors.white),
                            SizedBox(width: 8),
                            Text(
                              'SPENDLY DISCOVER',
                              style: TextStyle(
                                color: Colors.white,
                                letterSpacing: 2,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (accessToken == null)
                    FilledButton.icon(
                      onPressed: loading ? null : connectSpotify,
                      icon: const Icon(Icons.link_rounded),
                      label: Text(
                        loading ? 'Connecting...' : 'Connect Spotify',
                      ),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                    )
                  else
                    TextField(
                      controller: searchController,
                      textInputAction: TextInputAction.search,
                      onSubmitted: searchSpotify,
                      decoration: InputDecoration(
                        hintText: 'Search songs, artists or albums',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.arrow_forward_rounded),
                          onPressed: () => searchSpotify(searchController.text),
                        ),
                        filled: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      error!,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ],
                  if (accessToken == null) ...[
                    const SizedBox(height: 18),
                    Text(
                      'Connect your Spotify account to search its music catalogue and open tracks in Spotify.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (searching)
                    const Padding(
                      padding: EdgeInsets.all(30),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  if (tracks.isNotEmpty) ...[
                    _sectionTitle('Songs'),
                    ...tracks.map(_trackTile),
                  ],
                  if (artists.isNotEmpty) ...[
                    _sectionTitle('Artists'),
                    SizedBox(
                      height: 145,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: artists.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 18),
                        itemBuilder: (_, index) => _artistTile(artists[index]),
                      ),
                    ),
                  ],
                  if (albums.isNotEmpty) ...[
                    _sectionTitle('Albums'),
                    SizedBox(
                      height: 205,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: albums.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 14),
                        itemBuilder: (_, index) => _albumTile(albums[index]),
                      ),
                    ),
                  ],
                  if (query.isNotEmpty &&
                      !searching &&
                      tracks.isEmpty &&
                      artists.isEmpty &&
                      albums.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(25),
                      child: Center(child: Text('No results found.')),
                    ),
                  if (accessToken != null && query.isEmpty && !searching) ...[
                    _sectionTitle('Start exploring'),
                    const Text(
                      'Search for an artist, song or album to find your next favourite.',
                    ),
                  ],
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
