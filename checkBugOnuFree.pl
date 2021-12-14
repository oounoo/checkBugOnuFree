#!/usr/bin/env perl

use warnings;
use strict;

use utf8;

use HTTP::Tiny;
use Time::HiRes 'time';
use Time::Piece;

my $VERSION='0.7';

my $lanUrl='http://212.27.38.253:8095/fixed/1G';
my %wanBbrUrls=(AS12876 => 'http://ipv4.scaleway.testdebit.info/1G.iso',
                AS5410 => 'http://ipv4.paris.testdebit.info/1G.iso');
my %wanCubicUrls=(AS12876 => 'http://ping.online.net/1000Mo.dat',
                  AS5410 => 'http://ipv4.bouygues.testdebit.info/1G.iso');

my $osIsWindows=$^O eq 'MSWin32';

my %options;
my %cmdOpts=('skip-update-check' => ['Désactive la vérification de disponibilité de nouvelle version','U'],
             'skip-intro' => ["Désactive le message d'introduction et démarre immédiatement les tests",'I'],
             'no-diag' => ['Désactive le diagnostique automatique (tests de débit uniquement)','D'],
             'skip-lan-check' => ['Désactive la vérification du débit local à partir de la Freebox (tests de débit Internet uniquement)','L'],
             'alternate-srv' => ['Change de serveur pour les tests de débit (AS5410 "Bouygues Telecom" à la place de AS12876 "Scaleway")','a'],
             help => ["Affiche l'aide",'h'],
             version => ['Affiche la version','v']);
my %cmdOptsAliases = map {$cmdOpts{$_}[1] => $_} (keys %cmdOpts);

my $timestampPrinted;
sub printTimestampLine { 
  my $gmTime=gmtime()->strftime('%F %T').' GMT';
  my $timestampPadding='-' x (int(77-length($gmTime))/2);
  print "$timestampPadding $gmTime $timestampPadding\n";
  $timestampPrinted=1;
}

sub quit {
  my $msg=shift;
  print "$msg\n" if(defined $msg);
  if($timestampPrinted) {
    printTimestampLine();
  }else{
    print "\n";
  }
  if($osIsWindows) {
    print "Appuyer sur Entrée pour quitter...\n";
    <STDIN>;
  }
  exit;
}

my $osName=$^O;
if($osIsWindows) {
  require Win32;
  eval "use open ':std', ':encoding(cp'.Win32::GetConsoleOutputCP().')'";
  if($@) {
    quit("Impossible de configurer l'encodage de la console Windows:\n$@");
  }
  $osName=Win32::GetOSDisplayName();
}else{
  eval "use open ':std', ':encoding(utf8)'";
  require POSIX;
  my @uname=POSIX::uname();
  my ($sysName,$sysRelease,$sysArch)=@uname[0,2,4];
  if($sysName) {
    $osName=$sysName;
    $osName.=" $sysRelease" if($sysRelease);
    $osName.=" ($sysArch)" if($sysArch);
  }
}

sub usage {
  print "\nUsage:\n  $0 [<options>]\n";
  foreach my $cmdOpt (sort keys %cmdOpts) {
    print "      --$cmdOpt (-$cmdOpts{$cmdOpt}[1]) : $cmdOpts{$cmdOpt}[0]\n";
  }
  quit();
}

foreach my $arg (@ARGV) {
  if(substr($arg,0,2) eq '--') {
    my $cmdOpt=substr($arg,2);
    if(exists $cmdOpts{$cmdOpt}) {
      $options{$cmdOpt}=1;
    }else{
      print "Option invalide \"$cmdOpt\"\n";
      usage();
    }
  }elsif(substr($arg,0,1) eq '-') {
    my $cmdOptsString=substr($arg,1);
    my @cmdOptsList=split(//,$cmdOptsString);
    foreach my $cmdOpt (@cmdOptsList) {
      if(exists $cmdOptsAliases{$cmdOpt}) {
        $options{$cmdOptsAliases{$cmdOpt}}=1;
      }else{
        print "Option invalide \"$cmdOpt\"\n";
        usage();
      }
    }
  }else{
    print "Paramètre invalide \"$arg\"\n";
    usage();
  }
  
}

usage() if($options{help});
quit("checkBugOnuFree v$VERSION") if($options{version});
$options{'no-diag'}=1 if($options{'skip-lan-check'});

my $httpClient=HTTP::Tiny->new(proxy => undef, http_proxy => undef, https_proxy => undef);
sub getDlTime {
  my $url=shift;
  my $startTime=time();
  my $result=$httpClient->get($url,{data_callback => sub {}});
  if($result->{success}) {
    return time()-$startTime;
  }else{
    quit("Echec de téléchargement de \"$url\" (HTTP status: $result->{status}, reason: $result->{reason})");
  }
}

sub readableDlSpeed {
  my $speed=shift;
  my @units=('',qw'K M G T');
  my $unitIdx=0;
  while($speed >= 1024) {
    $speed/=1024;
    $unitIdx++;
  }
  return sprintf('%.2f',$speed).' '.$units[$unitIdx].'o/s';
}

if(! $options{'skip-update-check'} && $VERSION =~ /^(\d+)\.(\d+)$/) {
  my ($currentVersionMajor,$currentVersionMinor)=($1,$2);
  $httpClient->{timeout}=10;
  my $result=$httpClient->get('http://checkbugonu.royalwebhosting.net/LATEST');
  if($result->{success}) {
    my $newVersion=$result->{content};
    if($newVersion =~ /^(\d+)\.(\d+)$/) {
      my ($latestVersionMajor,$latestVersionMinor)=($1,$2);
      $newVersion="$latestVersionMajor.$latestVersionMinor";
      if($latestVersionMajor > $currentVersionMajor
         || ($latestVersionMajor == $currentVersionMajor && $latestVersionMinor > $currentVersionMinor)) {
        print +('-' x 79)."\n";
        print "Une nouvelle version de checkBugOnuFree est disponible ($newVersion)\n";
        print "Vous utilisez actuellement la version $VERSION\n";
        print "Vous pouvez télécharger la dernière version à partir du lien ci-dessous:\n";
        print '  https://github.com/oounoo/checkBugOnuFree/releases/latest/download/checkBugOnuFree.'.($0 =~ /\.exe$/i ? 'exe' : 'pl')."\n";
        print "Vous pouvez désactiver la vérification de version avec le paramètre --skip-update-check (-U)\n";
        print +('-' x 79)."\n";
        print "Appuyer sur Ctrl-c pour quitter, ou Entrée pour continuer avec votre version actuelle.\n";
        exit unless(defined <STDIN>);
      }
    }else{
      print "Impossible de vérifier si une nouvelle version est disponible (valeur de nouvelle version invalide \"$newVersion\")\n";
    }
  }else{
    print "Impossible de vérifier si une nouvelle version est disponible (HTTP status: $result->{status}, reason: $result->{reason})\n";
  }
}

if(! $options{'skip-intro'}) {
  print <<EOT;
===============================================================================
CheckBugOnuFree
---------------
Programme de diagnostique de connexion FTTH Free avec boîtier ONU

Ce programme effectue des tests de débit en mono-session TCP afin d'évaluer la
possibilité que la connexion FTTH soit affectée par un dysfonctionnement du
boîtier ONU Free.
Il est aussi possible d'utiliser ce programme sur une infrastructure sans
Freebox pour comparer les résultats, à condition de désactiver le test de débit
local via le paramètre --skip-lan-check (voir --help pour plus d'information).

Avant de continuer, veuillez vérifier que rien d'autre ne consomme de la bande
passante sur le réseau (ordinateurs, Freebox player, télévision...), ni du CPU
sur le système de test (mises à jour automatiques, antivirus...).
===============================================================================
Appuyer sur Entrée pour continuer (ou Ctrl-C pour annuler)...
EOT
  exit unless(defined <STDIN>);
}

my $cbofTag="[checkBugOnuFree v$VERSION]";
my $osNamePaddingLength=79-length($cbofTag)-length($osName);
$osNamePaddingLength=1 if($osNamePaddingLength < 1);
print "\n".$cbofTag.(' ' x $osNamePaddingLength).$osName."\n";

printTimestampLine();

if(! $options{'skip-lan-check'}) {
  print "Test de débit local (vérification de la fiabilité du système de test)...\n";
  $httpClient->{timeout}=2;
  my $localSpeed=1024 ** 3 / getDlTime($lanUrl);
  print '  --> '.readableDlSpeed($localSpeed)."\n";
  if($localSpeed < 70 * 1024 ** 2) {
    print "\nDébit local insuffisant pour déterminer si la connexion est affectée par un dysfonctionnement de boîtier ONU Free.\n";
    quit("  => VERIFIER QU'UNE LIAISON FILAIRE EST UTILISEE ET QUE RIEN D'AUTRE NE CONSOMME DE LA BANDE PASSANTE NI DU CPU SUR LE SYSTEME, PUIS RELANCER LE TEST");
  }
}

my $srvAs = $options{'alternate-srv'} ? 'AS5410' : 'AS12876';
my ($wanBbrUrl,$wanCubicUrl)=($wanBbrUrls{$srvAs},$wanCubicUrls{$srvAs});

print "Test de débit Internet ($srvAs-BBR)...\n";
$httpClient->{timeout}=10;
my $internetBbrSpeed=1024 ** 3 / getDlTime($wanBbrUrl);
print '  --> '.readableDlSpeed($internetBbrSpeed)."\n";
my $internetBbrSpeedMB=$internetBbrSpeed/(1024 ** 2);
if(! $options{'no-diag'}) {
  if($internetBbrSpeedMB < 20) {
    print "\nDébit Internet insuffisant pour déterminer si la connexion est affectée par un dysfonctionnement de boîtier ONU Free.\n";
    quit("  => VERIFIER QUE RIEN D'AUTRE NE CONSOMME DE LA BANDE PASSANTE ET RELANCER LE TEST POUR CONFIRMER LE DEBIT INTERNET");
  }elsif($internetBbrSpeedMB < 45) {
    quit("\n/!\\ La connexion semble affectée par un dysfonctionnement de boîtier ONU Free.");
  }
}

print "Test de débit Internet ($srvAs-Cubic)...\n";
my $internetCubicSpeed=1024 ** 3 / getDlTime($wanCubicUrl);
print '  --> '.readableDlSpeed($internetCubicSpeed)."\n";
my $internetCubicSpeedMB=$internetCubicSpeed/(1024 ** 2);
if(! $options{'no-diag'}) {
  print "\n";
  if($internetCubicSpeedMB < 30) {
    quit("/!\\ La connexion semble affectée par un dysfonctionnement de boîtier ONU Free.");
  }elsif($internetBbrSpeedMB < 55 || $internetCubicSpeedMB/$internetBbrSpeedMB < 2/3) {
    print "La connexion POURRAIT être affectée par un dysfonctionnement de boîtier ONU Free.\n";
    quit("  => VERIFIER QUE RIEN D'AUTRE NE CONSOMME DE LA BANDE PASSANTE ET RELANCER LE TEST POUR CONFIRMER LE DEBIT INTERNET");
  }elsif($internetBbrSpeedMB < 70 || $internetCubicSpeedMB < 70) {
    quit("La connexion ne semble pas affectée par un dysfonctionnement classique de boîtier ONU Free mais présente tout de même des performances dégradées.");
  }else{
    quit("La connexion ne semble pas affectée par un dysfonctionnement de boîtier ONU Free.");
  }
}
quit();
