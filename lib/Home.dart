import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'dart:io';
import 'package:open_file/open_file.dart';
import 'package:flutter/services.dart';

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _urlController = TextEditingController();
  Video? videoInfo;
  List<DropdownMenuItem<String>> qualityItems = [];
  String? selectedQuality;
  bool isLoading = false;
  List<Map<String, String>> downloadedVideos = [];
  bool isDownloading = false;
  double downloadProgress = 0;
  String? currentDownloadId;

  @override
  void initState() {
    super.initState();
    _initializeDownloader();
    _loadDownloadedVideos();
  }

  Future<void> _initializeDownloader() async {
    await FlutterDownloader.initialize(debug: true);
    FlutterDownloader.registerCallback(downloadCallback as DownloadCallback);
  }

  static void downloadCallback(String id, DownloadTaskStatus status, int progress) {
    // Callback for download updates
  }

  Future<void> _loadDownloadedVideos() async {
    final dir = await getApplicationDocumentsDirectory();
    final videoDir = Directory('${dir.path}/yt_downloads');
    if (await videoDir.exists()) {
      final files = videoDir.listSync();
      setState(() {
        downloadedVideos = files
            .where((file) => file.path.endsWith('.mp4'))
            .map((file) => {
          'path': file.path,
          'name': file.path.split('/').last,
        })
            .toList();
      });
    }
  }

  Future<void> _requestPermissions() async {
    if (!await Permission.storage.isGranted) {
      final status = await Permission.storage.request();
      if (!status.isGranted) {
        throw Exception('Storage permission required');
      }
    }
  }

  Future<void> fetchVideoInfo() async {
    setState(() {
      isLoading = true;
      videoInfo = null;
    });

    try {
      final yt = YoutubeExplode();
      final videoId = VideoId.parseVideoId(_urlController.text);
      if (videoId == null) throw Exception('Invalid URL');

      final video = await yt.videos.get(videoId);

      setState(() {
        videoInfo = video;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() => isLoading = false);
    }
  }


  Future<void> downloadVideo() async {
    if (videoInfo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fetch video info before downloading.')),
      );
      return;
    }

    try {
      await _requestPermissions();

      setState(() {
        isDownloading = true;
        downloadProgress = 0;
      });

      final yt = YoutubeExplode();
      final videoId = VideoId.parseVideoId(_urlController.text);
      if (videoId == null) throw Exception('Invalid YouTube URL');

      final manifests = await yt.videos.streamsClient.getManifest(videoId);

      final selectedStream = selectedQuality != null
          ? manifests.muxed.firstWhere(
            (stream) => stream.qualityLabel == selectedQuality,
        orElse: () => throw Exception('Selected quality not available'),
      )
          : manifests.muxed.firstWhere(
            (stream) => stream != null,
        orElse: () => throw Exception('No streams available for download'),
      );

      final dir = await getExternalStorageDirectory();
      if (dir == null) {
        throw Exception('External storage is not available on this device.');
      }

      final videoDir = Directory('${dir.path}/yt_downloads');
      if (!await videoDir.exists()) {
        await videoDir.create(recursive: true);
      }

      final fileName = '${videoInfo!.title.replaceAll(RegExp(r'[^\w\s]'), '')}.mp4';

      final taskId = await FlutterDownloader.enqueue(
        url: selectedStream.url.toString(),
        savedDir: videoDir.path,
        fileName: fileName,
        showNotification: true,
        openFileFromNotification: true,
      );

      if (taskId == null) {
        throw Exception('Failed to start download');
      }

      currentDownloadId = taskId;

    } catch (e) {
      setState(() {
        isDownloading = false;
        downloadProgress = 0;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AMM YouTube Manager'),
        backgroundColor: Colors.blue,
      ),
      resizeToAvoidBottomInset: true,
      body: Container(
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blue, Colors.white54],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.only(
              left: 16.0,
              right: 16.0,
              top: 16.0,
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Column(
              children: [
                TextField(
                  controller: _urlController,
                  decoration: InputDecoration(
                    labelText: 'Paste YouTube URL',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.paste),
                      onPressed: () async {
                        final data = await Clipboard.getData('text/plain');
                        if (data != null) {
                          _urlController.text = data.text ?? '';
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: fetchVideoInfo,
                  child: const Text('Fetch Video Info'),
                ),
                if (isLoading) const CircularProgressIndicator(),
                if (videoInfo != null) ...[
                  const SizedBox(height: 16),
                  Image.network(videoInfo!.thumbnails.mediumResUrl),
                  const SizedBox(height: 8),
                  Text(
                    videoInfo!.title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  if (qualityItems.isNotEmpty)
                    DropdownButton<String>(
                      value: selectedQuality,
                      items: qualityItems,
                      onChanged: (value) => setState(() => selectedQuality = value),
                      hint: const Text('Select Quality'),
                    )
                  else
                    const SizedBox(height: 10),
                  const Text(
                    'No quality options available. Downloading default quality.',
                    style: TextStyle(color: Colors.red),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: isDownloading ? null : downloadVideo,
                    child: const Text('Download Video'),
                  ),
                ],
                const SizedBox(height: 24),
                const Text(
                  'Downloaded Videos',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                downloadedVideos.isEmpty
                    ? const Center(child: Text('No downloads yet'))
                    : ListView.builder(
                  shrinkWrap: true, // Ensures ListView takes only necessary space
                  physics: const NeverScrollableScrollPhysics(), // Prevents nested scrolling issues
                  itemCount: downloadedVideos.length,
                  itemBuilder: (context, index) {
                    final video = downloadedVideos[index];
                    return ListTile(
                      title: Text(video['name']!),
                      trailing: IconButton(
                        icon: const Icon(Icons.play_arrow),
                        onPressed: () => OpenFile.open(video['path']),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}