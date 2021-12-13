#!/usr/bin/env perl

use warnings;
use strict;

use utf8;

use HTTP::Tiny;
use Time::HiRes 'time';

my $VERSION=0.5;

my $lanUrl='http://212.27.38.253:8095/fixed/1G';
my %wanBbrUrls=(AS12876 => 'http://ipv4.scaleway.testdebit.info/1G.iso',
                AS5410 => 'http://ipv4.paris.testdebit.info/1G.iso');
my %wanCubicUrls=(AS12876 => 'http://ping.online.net/1000Mo.dat',
                  AS5410 => 'http://ipv4.bouygues.testdebit.info/1G.iso');

my $osIsWindows=$^O eq 'MSWin32';

my %options;
my %cmdOpts=('skip-msg' => ['Désactive le message de présentation et démarre immédiatement les tests','s'],
             'test' => ['Sélectionne le mode test de débit simple à la place du mode diagnostique automatique','t'],
             'no-fbx' => ['Mode sans Freebox (test de débit Internet uniquement)','n'],
             'alternate-srv' => ['Change de serveur pour les tests de débit (utilise AS5410 "Bouygues Telecom" à la place de AS12876 "Scaleway")','a'],
             help => ["Affiche l'aide",'h'],
             version => ['Affiche la version','v']);
my %cmdOptsAliases = map {$cmdOpts{$_}[1] => $_} (keys %cmdOpts);

sub quit {
  my $msg=shift;
  print "$msg\n" if(defined $msg);
  print "\n";
  if($osIsWindows) {
    print "Appuyer sur Entrée pour quitter...\n";
    <STDIN>;
  }
  exit;
}

if($osIsWindows) {
  require Win32;
  eval "use open ':std', ':encoding(cp'.Win32::GetConsoleOutputCP().')'";
  if($@) {
    quit("Impossible de configurer l'encodage de la console Windows:\n$@");
  }
}else{
  eval "use open ':std', ':encoding(utf8)'";
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
$options{test}=1 if($options{'no-fbx'});

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

if(! $options{'skip-msg'}) {
  print <<EOT;

CheckBugOnuFree
---------------

Programme de diagnostique de connexion FTTH Free avec boîtier ONU

Ce programme permet d'évaluer la possibilité que la connexion FTTH soit affectée
par un dysfonctionnement du boîtier ONU Free. Un test de débit local utilisant
la Freebox est effectué en premier lieu pour vérifier la fiabilité du système de
test, sauf si le mode sans Freebox est sélectionné (paramètre --no-fbx). Le mode
par défaut ne fonctionne donc que si la connexion Internet est gérée par une
Freebox.

Avant de continuer, veuillez vérifier que rien d'autre ne consomme de la bande
passante sur le réseau (ordinateurs, Freebox player, télévision...), ni du CPU
sur le système de test (mises à jour automatiques, antivirus...).

Appuyer sur Entrée pour continuer (ou Ctrl-C pour annuler)...
EOT
  exit unless(defined <STDIN>);
}

my $srvAs = $options{'alternate-srv'} ? 'AS5410' : 'AS12876';
my ($wanBbrUrl,$wanCubicUrl)=($wanBbrUrls{$srvAs},$wanCubicUrls{$srvAs});

print "[checkBugOnuFree v$VERSION] [$^O] [$srvAs]\n";
if(! $options{'no-fbx'}) {
  print "Test de débit local (vérification de la fiabilité du système de test)...\n";
  $httpClient->{timeout}=2;
  my $localSpeed=1024 ** 3 / getDlTime($lanUrl);
  print '  --> '.readableDlSpeed($localSpeed)."\n";
  if($localSpeed < 70 * 1024 ** 2) {
    print "\nDébit local insuffisant pour déterminer si la connexion est affectée par un dysfonctionnement du boîtier ONU Free.\n";
    quit("  => VERIFIER QU'UNE LIAISON FILAIRE EST UTILISEE ET QUE RIEN D'AUTRE NE CONSOMME DE LA BANDE PASSANTE NI DU CPU SUR LE SYSTEME, PUIS RELANCER LE TEST");
  }
}

print "Test de débit Internet (BBR)...\n";
$httpClient->{timeout}=10;
my $internetBbrSpeed=1024 ** 3 / getDlTime($wanBbrUrl);
print '  --> '.readableDlSpeed($internetBbrSpeed)."\n";
my $internetBbrSpeedMB=$internetBbrSpeed/(1024 ** 2);
if(! $options{'test'}) {
  if($internetBbrSpeedMB < 20) {
    print "\nDébit Internet insuffisant pour déterminer si la connexion est affectée par un dysfonctionnement du boîtier ONU Free.\n";
    quit("  => VERIFIER QUE RIEN D'AUTRE NE CONSOMME DE LA BANDE PASSANTE ET RELANCER LE TEST POUR CONFIRMER LE DEBIT INTERNET");
  }elsif($internetBbrSpeedMB < 45) {
    quit("\n/!\\ La connexion semble affectée par un dysfonctionnement du boîtier ONU Free.");
  }
}

print "Test de débit Internet (Cubic)...\n";
my $internetCubicSpeed=1024 ** 3 / getDlTime($wanCubicUrl);
print '  --> '.readableDlSpeed($internetCubicSpeed)."\n";
my $internetCubicSpeedMB=$internetCubicSpeed/(1024 ** 2);
if(! $options{'test'}) {
  print "\n";
  if($internetCubicSpeedMB < 30) {
    quit("/!\\ La connexion semble affectée par un dysfonctionnement du boîtier ONU Free.");
  }elsif($internetBbrSpeedMB < 55 || $internetCubicSpeedMB/$internetBbrSpeedMB < 2/3) {
    print "La connexion POURRAIT être affectée par un dysfonctionnement du boîtier ONU Free.\n";
    quit("  => VERIFIER QUE RIEN D'AUTRE NE CONSOMME DE LA BANDE PASSANTE ET RELANCER LE TEST POUR CONFIRMER LE DEBIT INTERNET");
  }elsif($internetBbrSpeedMB < 70 || $internetCubicSpeedMB < 70) {
    quit("La connexion ne semble pas affectée par un dysfonctionnement classique du boîtier ONU Free mais présente tout de même des performances dégradées.");
  }else{
    quit("La connexion ne semble pas affectée par un dysfonctionnement du boîtier ONU Free.");
  }
}
quit();
