%dnl This file will be recreated at the next build. To avoid this, delete this line.

%global requires %include %{_sourcedir}/requires.inc

%define appName tracker_1
%define orgName ru.volgait
%define appVersion 1.0.0
%define summary Трекер расходов - учёт личных и служебных расходов для ОС Аврора
%define license BSD-3-Clause

%define debug_package %{nil}

%define _flutter_build_type Release
%define _flutter_excludes ^lib(dconf|aurora_embedder|maliit-glib|xkbcommon|.+_platform_plugin)\\.so.*$
%define _flutter_psdk_version 5.2.1
%define _flutter_psdk_major 5