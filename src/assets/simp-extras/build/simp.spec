Summary: SIMP 6 Extra Packages
Name: simp
Version: 6.0.0
Release: 0
License: Apache License, Version 2.0
Group: Applications/System

Buildroot: %{_tmppath}/%{name}-%{version}-%{release}-buildroot
Buildarch: noarch
Requires: simp-adapter

Requires: pupmod-bfraser-grafana >= 2.5.0-2016
Requires: pupmod-elasticsearch-elasticsearch >= 0.11.0-2016
Requires: pupmod-elasticsearch-logstash >= 0.6.4-2016
Requires: pupmod-electrical-file_concat >= 1.0.1-2016
Requires: pupmod-herculesteam-augeasproviders_mounttab >= 2.0.1-2016
Requires: pupmod-herculesteam-augeasproviders_nagios >= 2.0.1-2016
Requires: pupmod-herculesteam-augeasproviders_pam >= 2.0.3-2016
Requires: pupmod-puppetlabs-mysql >= 2.2.3-2016
Requires: pupmod-simp-foreman >= 1.0.0
Requires: pupmod-simp-jenkins >= 4.1.0-2016
Requires: pupmod-simp-libreswan >= 0.1.1-2016
Requires: pupmod-simp-libvirt >= 4.1.1-2016
Requires: pupmod-simp-mcafee >= 4.1.1-2016
Requires: pupmod-simp-mozilla >= 4.1.1-2016
Requires: pupmod-simp-openscap >= 4.2.1-2016
Requires: pupmod-simp-polkit >= 4.1.0-2016
Requires: pupmod-simp-simp_elasticsearch >= 4.0.0
Requires: pupmod-simp-simp_grafana >= 0.1.0-2016
Requires: pupmod-simp-simp_logstash >= 2.0.0-2016
Requires: pupmod-simp-vnc >= 4.1.0-2016
Requires: pupmod-simp-vsftpd >= 5.0.6-2016
Requires: pupmod-simp-windowmanager >= 4.1.2-2016
Requires: pupmod-simp-xwindows >= 4.1.1-2016

Prefix: %{_sysconfdir}/puppet

%description
Stub for installing all 'extra' packages that are enhancements to SIMP but not
part of the supported core.

Unlike the main 'simp' require packages. Packages required by this RPM do not
have an upper bound to restrict breaking changes on a given distribution.

%changelog
* Thu Dec 08 2016 Trevor Vaughan <tvaughan@onyxpoint.com> 6.0.0-0
- Initial creation of the simp-extras RPM
