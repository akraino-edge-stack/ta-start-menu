# Copyright 2019 Nokia

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

Name:       start-menu
Version:    %{_version}
Release:    1%{?dist}
Summary:    Contains code for start menu.
License:    %{_platform_licence}
Source0:    %{name}-%{version}.tar.gz
Vendor:     %{_platform_vendor}
BuildArch:  noarch

Requires: dialog
BuildRequires: rsync

%description
This RPM contains code and support files for installing start menu

%prep
%autosetup

%build

%install
mkdir -p %{buildroot}/opt/start-menu/
mkdir -p %{buildroot}/etc/userconfig/
mkdir -p %{buildroot}/usr/lib/systemd/system/

rsync -av src/*  %{buildroot}/opt/start-menu
rsync -av services/start-menu.service %{buildroot}/usr/lib/systemd/system/start-menu.service

find

%files
%defattr(0755,root,root,0755)
/opt/start-menu*
/etc/userconfig
%attr(0644, root, root) /usr/lib/systemd/system/start-menu.service

%pre

%post
# Only enable the service, if it is a new installation or it will break the upgrade
if [ $1 -eq 1 ]
then
    systemctl enable start-menu.service
fi

%preun

%postun
systemctl disable start-menu.service

%clean
rm -rf %{buildroot}

