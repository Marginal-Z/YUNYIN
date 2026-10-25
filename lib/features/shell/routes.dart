import 'package:flutter/material.dart';

import '../artist/artist_page.dart';
import '../discover/discover_page.dart';
import '../home/desktop_home_page.dart';
import '../home/home_page.dart';
import '../library/collections_page.dart';
import '../library/library_page.dart';
import '../login/login_page.dart';
import '../playlist/playlist_page.dart';
import '../search/search_page.dart';
import '../search/search_result_page.dart';
import '../settings/appearance_page.dart';
import '../settings/settings_more_page.dart';
import '../settings/settings_page.dart';
import 'nav.dart';

Widget buildMobileRoute(AppRoute r) => switch (r) {
  HomeRoute() => const HomePage(),
  DiscoverRoute(:final tab) => DiscoverPage(initialTab: tab),
  LibraryRoute() => const LibraryPage(),
  PlaylistRoute() || AlbumRoute() || RadioRoute() || CollectionRoute() => PlaylistPage(route: r),
  ArtistRoute() => ArtistPage(route: r),
  MyCollectionsRoute(:final tab) => CollectionsPage(initialTab: tab),
  SearchRoute() => const SearchPage(),
  SearchResultRoute() => SearchResultPage(key: ValueKey(r.uid), route: r),
  SettingsRoute() => const SettingsPage(),
  SettingsMoreRoute() => const SettingsMorePage(),
  AppearanceRoute() => const AppearancePage(),
  LoginRoute() => const LoginPage(),
};

Widget buildDesktopRoute(AppRoute r) => switch (r) {
  HomeRoute() => const DesktopHomePage(),
  LibraryRoute() => const CollectionsPage(),
  _ => buildMobileRoute(r),
};
