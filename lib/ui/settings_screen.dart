import 'package:flutter/material.dart';
import '../l10n/l10n.dart';
import '../services/settings.dart';
import 'audio_bar.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final s = AppSettings.i;
  late final TextEditingController _folder = TextEditingController(text: s.exportFolder);

  @override
  void dispose() {
    s.exportFolder = _folder.text.trim();
    super.dispose();
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
        child: Text(t, style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Settings'))),
      body: ListView(children: [
        _section(tr('Language')),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'en', label: Text('English')),
              ButtonSegment(value: 'ar', label: Text('العربية')),
            ],
            selected: {s.lang},
            onSelectionChanged: (v) {
              s.lang = v.first;
              L10n.i.setLang(v.first);
              setState(() {});
            },
          ),
        ),
        _section(tr('Stamp button position')),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in const [
              ('topLeft', 'Top left'),
              ('topRight', 'Top right'),
              ('bottomLeft', 'Bottom left'),
              ('bottomRight', 'Bottom right'),
            ])
              ChoiceChip(
                label: Text(tr(c.$2)),
                selected: s.corner == c.$1,
                onSelected: (_) => setState(() => s.corner = c.$1),
              ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(tr('You can also drag the button anywhere on the slides; the spot is remembered.'),
              style: Theme.of(context).textTheme.bodySmall),
        ),
        _section(tr('Stamp style')),
        RadioListTile<bool>(
          value: false,
          groupValue: s.stampWhilePlaying,
          title: Text(tr('Pause, then stamp (recommended)')),
          subtitle: Text(tr('Stamp pauses the audio and keeps that second. Pick the page, tap Stamp again, and the audio resumes.')),
          onChanged: (v) => setState(() => s.stampWhilePlaying = v!),
        ),
        RadioListTile<bool>(
          value: true,
          groupValue: s.stampWhilePlaying,
          title: Text(tr('Stamp while playing')),
          subtitle: Text(tr('One tap stamps the current second without stopping the audio.')),
          onChanged: (v) => setState(() => s.stampWhilePlaying = v!),
        ),
        _section(tr('Viewing')),
        SwitchListTile(
          title: Text(tr('Split screen when a project has two PDFs')),
          value: s.splitDefault,
          onChanged: (v) => setState(() => s.splitDefault = v),
        ),
        ListTile(
          title: Text(tr('Default playback speed')),
          trailing: DropdownButton<double>(
            value: kSpeeds.contains(s.speed) ? s.speed : 1.0,
            items: [for (final v in kSpeeds) DropdownMenuItem(value: v, child: Text('$v×'))],
            onChanged: (v) => setState(() => s.speed = v ?? 1.0),
          ),
        ),
        _section(tr('Export')),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _folder,
            decoration: InputDecoration(
              labelText: tr('Folder inside Movies'),
              helperText: tr('Leave empty to save in Movies.'),
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<int>(
            segments: [
              ButtonSegment(value: 300, label: Text(tr('Smallest'))),
              ButtonSegment(value: 500, label: Text(tr('Balanced'))),
              ButtonSegment(value: 1000, label: Text(tr('Sharpest'))),
            ],
            selected: {s.videoKbps},
            onSelectionChanged: (v) => setState(() => s.videoKbps = v.first),
          ),
        ),
        const SizedBox(height: 32),
      ]),
    );
  }
}
