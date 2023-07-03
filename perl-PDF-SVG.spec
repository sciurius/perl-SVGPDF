# -*- rpm-spec -*-

%define metacpan https://cpan.metacpan.org/authors/id/J/JV/JV
%define FullName PDF-SVG

Name: perl-%{FullName}
Summary: SVG interpreter
License: GPL+ or Artistic
Version: 0.01
Release: 1%{?dist}
Source: %{metacpan}/%{FullName}-%{version}.tar.gz
Url: https://metacpan.org/release/%{FullName}

# It's all plain perl, nothing architecture dependent.
BuildArch: noarch

Requires: perl(:VERSION) >= 5.26.0
Requires: perl(:MODULE_COMPAT_%(eval "`perl -V:version`"; echo $version))

BuildRequires: make
BuildRequires: perl(Carp)
BuildRequires: perl(Exporter)
BuildRequires: perl(ExtUtils::MakeMaker) >= 7.54
BuildRequires: perl(PDF::API2) >= 2.044
BuildRequires: perl(File::LoadLines) >= 1.021
BuildRequires: perl(Object::Pad) >= 0.78
BuildRequires: perl(Test::More)
BuildRequires: perl(parent)
BuildRequires: perl(strict)
BuildRequires: perl(utf8)
BuildRequires: perl(warnings)
BuildRequires: perl-generators
BuildRequires: perl-interpreter

%description
PDF::SVG

%prep
%setup -q -n %{FullName}-%{version}

%build
perl Makefile.PL INSTALLDIRS=vendor NO_PACKLIST=1 NO_PERLLOCAL=1
%{make_build}

%check
make test VERBOSE=1

%install
%{make_install}
%{_fixperms} $RPM_BUILD_ROOT/*

%files
%doc Changes README
%{perl_vendorlib}/*
%{_mandir}/man3/*

%changelog
* Mon Jul 03 2023 Johan Vromans <jv@cpan.org> - 0.01-1
- Initial Fedora package.
