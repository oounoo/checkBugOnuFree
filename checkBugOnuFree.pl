#!/usr/bin/env perl

use warnings;
use strict;

use utf8;

use HTTP::Tiny;
use Time::HiRes 'time';

my $VERSION=0.4;

my $lanUrl='http://212.27.38.253:8095/fixed/1G';
my $wanBbrUrl='http://ipv4.scaleway.testdebit.info/1G.iso';
my $wanCubicUrl='http://ping.online.net/1000Mo.dat';

my $osIsWindows=$^O eq 'MSWin32';

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

print <<EOT;

CheckBugOnuFree (v$VERSION)
---------------

Programme de diagnostique de connexion FTTH Free avec boîtier ONU

Ce programme permet d'évaluer la possibilité que la connexion FTTH soit affectée
par un dysfonctionnement du boîtier ONU Free. La Freebox est utilisée pour
tester le débit local, ce programme ne fonctionne donc que si la connexion
Internet est gérée par une Freebox.

Avant de continuer, veuillez vérifier que rien d'autre ne consomme de la bande
passante sur le réseau (ordinateurs, Freebox player, télévision...), ni du CPU
sur le système de test (mises à jour automatiques, antivirus...).

Appuyer sur Entrée pour continuer (ou Ctrl-C pour annuler)...
EOT
exit unless(defined <STDIN>);

print "Test de débit local (vérification de la fiabilité du système de test)...\n";
$httpClient->{timeout}=2;
my $localSpeed=1024 ** 3 / getDlTime($lanUrl);
print '  --> '.readableDlSpeed($localSpeed)."\n";
if($localSpeed < 70 * 1024 ** 2) {
  print "\nDébit local insuffisant pour déterminer si la connexion est affectée par un dysfonctionnement du boîtier ONU Free.\n";
  quit("  => VERIFIER QU'UNE LIAISON FILAIRE EST UTILISEE ET QUE RIEN D'AUTRE NE CONSOMME DE LA BANDE PASSANTE NI DU CPU SUR LE SYSTEME, PUIS RELANCER LE TEST");
}

print "Test de débit Internet (BBR)...\n";
$httpClient->{timeout}=10;
my $internetBbrSpeed=1024 ** 3 / getDlTime($wanBbrUrl);
print '  --> '.readableDlSpeed($internetBbrSpeed)."\n";
my $internetBbrSpeedMB=$internetBbrSpeed/(1024 ** 2);
if($internetBbrSpeedMB < 20) {
  print "\nDébit Internet insuffisant pour déterminer si la connexion est affectée par un dysfonctionnement du boîtier ONU Free.\n";
  quit("  => VERIFIER QUE RIEN D'AUTRE NE CONSOMME DE LA BANDE PASSANTE ET RELANCER LE TEST POUR CONFIRMER LE DEBIT INTERNET");
}elsif($internetBbrSpeedMB < 45) {
  print "\n/!\\ La connexion semble affectée par un dysfonctionnement du boîtier ONU Free.\n";
  quit("    (ONU v2 ou ONU v1 récent)");
}

print "Test de débit Internet (Cubic)...\n";
my $internetCubicSpeed=1024 ** 3 / getDlTime($wanCubicUrl);
print '  --> '.readableDlSpeed($internetCubicSpeed)."\n\n";
my $internetCubicSpeedMB=$internetCubicSpeed/(1024 ** 2);
if($internetCubicSpeedMB < 20) {
  print "/!\\ La connexion semble affectée par un dysfonctionnement du boîtier ONU Free.\n";
  quit("    (ONU v1 ancien)");
}elsif($internetBbrSpeedMB < 55 || $internetCubicSpeedMB/$internetBbrSpeedMB < 1/2) {
  print "La connexion POURRAIT être affectée par un dysfonctionnement du boîtier ONU Free.\n";
  quit("  => VERIFIER QUE RIEN D'AUTRE NE CONSOMME DE LA BANDE PASSANTE ET RELANCER LE TEST POUR CONFIRMER LE DEBIT INTERNET");
}elsif($internetBbrSpeedMB < 70 || $internetCubicSpeedMB < 70) {
  quit("La connexion ne semble pas affectée par un dysfonctionnement classique du boîtier ONU Free mais présente tout de même des performances dégradées.");
}else{
  quit("La connexion n'est pas affectée par un dysfonctionnement du boîtier ONU Free.");
}
