#!/usr/bin/env perl

use warnings;
use strict;

use utf8;

use HTTP::Tiny;
use Time::HiRes 'time';

my $VERSION=0.1;

my $osIsWindows=$^O eq 'MSWin32';

sub quit {
  my $msg=shift;
  print "$msg\n" if(defined $msg);
  if($osIsWindows) {
    print "\nAppuyer sur Entrée pour quitter...\n";
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
  my $receivedDataLength;
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

Programme de comparaison du débit local / internet en mono-session TCP

Ce programme permet d'évaluer la possibilité que la connexion FTTH soit
affectée par le bug d'ONU Free. La Freebox est utilisée pour tester le débit
local, ce programme ne fonctionne donc que si la connexion Internet est gérée
par une Freebox.

Vérifier que rien d'autre ne consomme de la bande passante sur le réseau
(ordinateurs, Freebox player, télévision...), ni du CPU sur le système de test
(mises à jour automatiques, antivirus...)

Appuyer sur Entrée pour continuer (ou Ctrl-C pour annuler)...
EOT
exit unless(defined <STDIN>);

print "Test de débit local...\n";
$httpClient->{timeout}=2;
my $localSpeed=1024 ** 3 / getDlTime("http://212.27.38.253:8095/fixed/1G");
print '  --> '.readableDlSpeed($localSpeed)."\n";

if($localSpeed < 70 * 1024 ** 2) {
  print "Débit local insuffisant pour déterminer si la connexion est affectée par le bug d'ONU Free.\n";
  quit("  => VERIFIER QU'UNE LIAISON FILAIRE EST UTILISEE ET QUE RIEN D'AUTRE NE CONSOMME DE LA BANDE PASSANTE NI DU CPU SUR LE SYSTEME, PUIS RELANCER LE TEST\n");
}

print "Test de débit Internet...\n";
$httpClient->{timeout}=10;
my $internetSpeed=1024 ** 3 / getDlTime("http://scaleway.testdebit.info/1G/1G.iso");
print '  --> '.readableDlSpeed($internetSpeed)."\n\n";

if($internetSpeed < 20 * 1024 ** 2) {
  print "Débit internet insuffisant pour déterminer si la connexion est affectée par le bug d'ONU Free.\n";
  print "  => VERIFIER QUE RIEN D'AUTRE NE CONSOMME DE LA BANDE PASSANTE ET RELANCER LE TEST\n";
}elsif($internetSpeed < 35 * 1024 ** 2) {
  print "/!\\ La connexion semble affectée par le bug d'ONU Free /!\\\n";
}elsif($internetSpeed < 40 * 1024 ** 2) {
  print "La connexion POURRAIT être affectée par le bug d'ONU Free (débit internet légèrement supérieur au débit habituel pour les connexions affectées).\n";
  print "  => RELANCER LE TEST POUR CONFIRMER LE DEBIT INTERNET\n";
}else{
  print "La connexion ne semble pas affectée par le bug d'ONU Free (débit internet supérieur au débit habituel pour les connexions affectées).\n";
}
quit();
