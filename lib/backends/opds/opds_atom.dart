import 'package:xml/xml.dart';

const opdsRelSubsection = 'subsection';
const opdsRelAcquisitionPrefix = 'http://opds-spec.org/acquisition';
const opdsRelThumbnail = 'http://opds-spec.org/image/thumbnail';
const opdsRelImage = 'http://opds-spec.org/image';
const opdsRelPseStream = 'http://vaemendis.net/opds-pse/stream';
const opdsRelNext = 'next';

/// A single `<link>` inside an Atom entry or feed, with the OPDS-PSE
/// extension attributes (`pse:count`, `pse:lastRead`) parsed out when
/// present - OPDS-PSE servers advertise per-book page count and last-read
/// position this way rather than in the entry body.
class AtomLink {
  final String rel;
  final String href;
  final String? type;
  final int? pseCount;
  final int? pseLastRead;

  const AtomLink({
    required this.rel,
    required this.href,
    this.type,
    this.pseCount,
    this.pseLastRead,
  });

  bool get isAcquisition => rel.startsWith(opdsRelAcquisitionPrefix);
}

class AtomEntry {
  final String id;
  final String title;
  final String? content;
  final List<AtomLink> links;

  const AtomEntry({
    required this.id,
    required this.title,
    this.content,
    required this.links,
  });

  AtomLink? _link(String rel) {
    for (final l in links) {
      if (l.rel == rel) return l;
    }
    return null;
  }

  AtomLink? get subsectionLink => _link(opdsRelSubsection);
  AtomLink? get pseStreamLink => _link(opdsRelPseStream);
  AtomLink? get thumbnailLink => _link(opdsRelThumbnail) ?? _link(opdsRelImage);
  AtomLink? get acquisitionLink =>
      links.where((l) => l.isAcquisition).firstOrNull;

  bool get isNavigation => subsectionLink != null;
  bool get isBook => !isNavigation && (pseStreamLink != null || acquisitionLink != null);
}

class AtomFeed {
  final String id;
  final String title;
  final String? subtitle;
  final List<AtomEntry> entries;
  final String? nextHref;

  const AtomFeed({
    required this.id,
    required this.title,
    this.subtitle,
    required this.entries,
    this.nextHref,
  });

  factory AtomFeed.parse(String xmlBody) {
    final doc = XmlDocument.parse(xmlBody);
    final feed = doc.rootElement;

    String? nextHref;
    for (final link in feed.findElements('link')) {
      if (link.getAttribute('rel') == opdsRelNext) {
        nextHref = link.getAttribute('href');
      }
    }

    return AtomFeed(
      id: feed.getElement('id')?.innerText ?? '',
      title: feed.getElement('title')?.innerText ?? '',
      subtitle: feed.getElement('subtitle')?.innerText,
      nextHref: nextHref,
      entries: feed.findElements('entry').map(_parseEntry).toList(),
    );
  }

  static AtomEntry _parseEntry(XmlElement entry) {
    final links = entry.findElements('link').map((link) {
      final pseCountRaw = _attrIgnoringNamespace(link, 'count');
      final pseLastReadRaw = _attrIgnoringNamespace(link, 'lastRead');
      return AtomLink(
        rel: link.getAttribute('rel') ?? '',
        href: link.getAttribute('href') ?? '',
        type: link.getAttribute('type'),
        pseCount: pseCountRaw == null ? null : int.tryParse(pseCountRaw),
        pseLastRead: pseLastReadRaw == null ? null : int.tryParse(pseLastReadRaw),
      );
    }).toList();

    return AtomEntry(
      id: entry.getElement('id')?.innerText ?? '',
      title: entry.getElement('title')?.innerText ?? 'Untitled',
      content: entry.getElement('content')?.innerText,
      links: links,
    );
  }

  /// `pse:count` comes through as an attribute in the OPDS-PSE XML
  /// namespace; `getAttribute(name, namespace: '*')` only matches
  /// attributes that *are* namespaced, so this also checks the bare name
  /// for servers that (out of spec, but seen in the wild) omit the prefix.
  static String? _attrIgnoringNamespace(XmlElement element, String localName) {
    for (final attr in element.attributes) {
      if (attr.name.local == localName) return attr.value;
    }
    return null;
  }
}
