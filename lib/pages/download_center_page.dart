import 'package:flutter/material.dart';
import 'local_comics_page.dart';

class DownloadCenterPage extends StatefulWidget {
  final int initialTab;

  const DownloadCenterPage({super.key, this.initialTab = 0});

  @override
  State<DownloadCenterPage> createState() => _DownloadCenterPageState();
}

class _DownloadCenterPageState extends State<DownloadCenterPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('下载中心')),
      body: const LocalComicsPage(embedded: true),
    );
  }
}
