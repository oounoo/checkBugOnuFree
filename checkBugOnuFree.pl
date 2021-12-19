#!/usr/bin/env perl

use warnings;
use strict;

use utf8;

use List::Util 'any';
use Time::HiRes qw'time sleep';

require HTTP::Tiny;
require Net::Ping;
require POSIX;
require Time::Piece;

my $VERSION='0.8';
my $PROGRAM_NAME='checkBugOnuFree';

my %TEST_DATA = ( 'local' => ['212.27.38.253',8095,'fixed/10G',2,10],
                  Internet => { AS12876 => { BBR => ['ipv4.scaleway.testdebit.info',80,'10G.iso',10,50],
                                             CUBIC => ['ping.online.net',80,'10000Mo.dat',10,50] },
                                AS5410 => { BBR => ['ipv4.paris.testdebit.info',80,'10G.iso',10,50],
                                            CUBIC => ['ipv4.bouygues.testdebit.info',80,'10G.iso',10,50]} } );

my $MTU=1500;
my $MSS=$MTU-52;
my $TCP_EFFICIENCY=$MSS/($MTU+38);
my $GOODPUT_1Gbps_Bytes=1_000_000_000* $TCP_EFFICIENCY / 8;
my $RECOMMENDED_MIN_RTT_MAX_FOR_FULL_BANDWIDTH=15;
my $RECOMMENDED_MIN_RCV_WINDOW_SIZE=$GOODPUT_1Gbps_Bytes*$RECOMMENDED_MIN_RTT_MAX_FOR_FULL_BANDWIDTH/1000;

my %cmdOpts=('skip-update-check' => ['Désactive la vérification de disponibilité de nouvelle version','U'],
             'skip-intro' => ["Désactive le message d'introduction et démarre immédiatement les tests",'I'],
             'no-diag' => ['Désactive le diagnostique automatique (tests de débit uniquement)','D'],
             'detailed-diag' => ['Affiche des messages de diagnostique supplémentaires','d'],
             'skip-lan-check' => ['Désactive la vérification du débit local à partir de la Freebox (tests de débit Internet uniquement)','L'],
             'alternate-srv' => ['Change de serveur pour les tests de débit (AS5410 "Bouygues Telecom" à la place de AS12876 "Scaleway")','a'],
             'binary-units' => ["Utilise les préfixes binaires pour le système d'unités de débit",'b'],
             'long-download' => ['Utilise des tests de téléchargement plus longs (multiplie par 2 la durée max des téléchargements)','l'],
             help => ["Affiche l'aide",'h'],
             version => ['Affiche la version','v']);
my %cmdOptsAliases = map {$cmdOpts{$_}[1] => $_} (keys %cmdOpts);

my $httpClient=HTTP::Tiny->new(proxy => undef, http_proxy => undef, https_proxy => undef);

my $osIsWindows=$^O eq 'MSWin32';
if($osIsWindows) {
  require Win32;
  eval "use open ':std', ':encoding(cp'.Win32::GetConsoleOutputCP().')'";
  if($@) {
    quit("Impossible de configurer l'encodage de la console Windows:\n$@");
  }
}else{
  eval "use open ':std', ':encoding(utf8)'";
}

my %options;
foreach my $arg (@ARGV) {
  if(substr($arg,0,2) eq '--') {
    my $cmdOpt=substr($arg,2);
    if(exists $cmdOpts{$cmdOpt}) {
      $options{$cmdOpt}++;
    }else{
      print "Option invalide \"$cmdOpt\"\n";
      usage();
    }
  }elsif(substr($arg,0,1) eq '-') {
    my $cmdOptsString=substr($arg,1);
    my @cmdOptsList=split(//,$cmdOptsString);
    foreach my $cmdOpt (@cmdOptsList) {
      if(exists $cmdOptsAliases{$cmdOpt}) {
        $options{$cmdOptsAliases{$cmdOpt}}++;
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
my $maxDlDuration=15*2**($options{'long-download'}//0);

sub usage {
  print "\nUsage:\n  $0 [<options>]\n";
  foreach my $cmdOpt (sort keys %cmdOpts) {
    print "      --$cmdOpt (-$cmdOpts{$cmdOpt}[1]) : $cmdOpts{$cmdOpt}[0]\n";
  }
  quit();
}

my $timestampPrinted;
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

sub printTimestampLine { 
  my $gmTime=Time::Piece::gmtime()->strftime('%F %T').' GMT';
  my $timestampPadding='-' x (int(77-length($gmTime))/2);
  print "$timestampPadding $gmTime $timestampPadding\n";
  $timestampPrinted=1;
}

sub checkForNewVersion {
  return unless($VERSION =~ /^(\d+)\.(\d+)$/);
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
        print "Une nouvelle version de $PROGRAM_NAME est disponible ($newVersion)\n";
        print "Vous utilisez actuellement la version $VERSION\n";
        print "Vous pouvez télécharger la dernière version à partir du lien ci-dessous:\n";
        print '  https://github.com/oounoo/$PROGRAM_NAME/releases/latest/download/$PROGRAM_NAME.'.($0 =~ /\.exe$/i ? 'exe' : 'pl')."\n";
        print "Vous pouvez désactiver la vérification de version avec le paramètre --skip-update-check (-U)\n";
        print +('-' x 79)."\n";
        print "Appuyer sur Ctrl-c pour quitter, ou Entrée pour continuer avec votre version actuelle.\n";
        exit unless(defined <STDIN>);
      }
    }else{
      print "[!] Impossible de vérifier si une nouvelle version est disponible (valeur de nouvelle version invalide \"$newVersion\")\n";
    }
  }else{
    print "[!] Impossible de vérifier si une nouvelle version est disponible (HTTP status: $result->{status}, reason: $result->{reason})\n";
  }
}

sub printIntroMsg {
  print <<EOT;
===============================================================================
$PROGRAM_NAME
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

sub printHeaderLine {
  my $osName=getOsName()//$^O;
  my $cbofTag="[$PROGRAM_NAME v$VERSION]";
  my $osNamePaddingLength=79-length($cbofTag)-length($osName);
  $osNamePaddingLength=1 if($osNamePaddingLength < 1);
  print $cbofTag.(' ' x $osNamePaddingLength).$osName."\n";
}

sub getOsName {
  my $n;
  if($osIsWindows) {
    $n=Win32::GetOSDisplayName();
  }else{
    my @uname=POSIX::uname();
    my ($sysName,$sysRelease,$sysArch)=@uname[0,2,4];
    if($sysName) {
      $n=$sysName;
      $n.=" $sysRelease" if($sysRelease);
      $n.=" ($sysArch)" if($sysArch);
    }
  }
  return $n;
}

my %tcpConf;
sub getTcpConf {
  my ($tcpConfReadCmd,@tcpConfFields);
  if($osIsWindows) {
    $tcpConfReadCmd='powershell.exe Get-NetTCPSetting Internet 2>NUL';
    @tcpConfFields=qw'AutoTuningLevelLocal AutoTuningLevelGroupPolicy AutoTuningLevelEffective ScalingHeuristics';
  }elsif(my $sysctlBin=findSysctlBin()) {
    $tcpConfReadCmd="$sysctlBin -a 2>/dev/null";
    @tcpConfFields=qw'net.ipv4.tcp_rmem net.core.rmem_max net.ipv4.tcp_adv_win_scale';
  }else{
    return;
  }
  my @tcpConfData=`$tcpConfReadCmd`;
  foreach my $line (@tcpConfData) {
    if($line =~ /^\s*([^:=]*[^\s:=])\s*[:=]\s*(.*[^\s])\s*$/ && (any {$1 eq $_} @tcpConfFields)) {
      $tcpConf{$1}=$2;
    }
  }
  if(defined $tcpConf{AutoTuningLevelEffective}) {
    if($tcpConf{AutoTuningLevelEffective} eq 'Local') {
      delete $tcpConf{AutoTuningLevelGroupPolicy};
      delete $tcpConf{AutoTuningLevelEffective};
    }elsif($tcpConf{AutoTuningLevelEffective} eq 'GroupPolicy') {
      delete $tcpConf{AutoTuningLevelLocal};
      delete $tcpConf{AutoTuningLevelEffective};
    }
  }
}

sub findSysctlBin {
  my $sysctlBin;
  foreach my $knownPath (qw'/sbin/sysctl /usr/sbin/sysctl') {
    if(-x $knownPath) {
      $sysctlBin=$knownPath;
      last;
    }
  }
  if(! defined $sysctlBin) {
    require IPC::Cmd;
    $sysctlBin=IPC::Cmd::can_run('sysctl');
  }
  return $sysctlBin;
}

my ($rcvWindow,$rmemMaxParam,$rmemMaxValuePrefix,$tcpAdvWinScale,$degradedTcpConf);
sub tcpConfAnalysis {
  if(%tcpConf) {
    print "Paramétrage actuel de la mémoire tampon de réception TCP:\n";
    map {print "  $_: $tcpConf{$_}\n"} (sort keys %tcpConf);
    if(defined $tcpConf{AutoTuningLevelLocal} && $tcpConf{AutoTuningLevelLocal} ne 'Normal') {
      $degradedTcpConf=1;
      print "[!] La valeur actuelle de AutoTuningLevelLocal peut dégrader les performances\n";
      if($options{'detailed-diag'}) {
        print "    Recommandation: ajuster le paramètre avec l'une des deux commandes suivantes\n";
        print "      [PowerShell] Set-NetTCPSetting -SettingName Internet -AutoTuningLevelLocal Normal\n";
        print "      [cmd.exe] netsh interface tcp set global autotuninglevel=normal\n";
      }
    }elsif(defined $tcpConf{AutoTuningLevelGroupPolicy} && $tcpConf{AutoTuningLevelGroupPolicy} ne 'Normal') {
      $degradedTcpConf=1;
      print "[!] La stratégie de groupe appliquée aux paramètres AutoTuningLevelEffective et AutoTuningLevelGroupPolicy peut dégrader les performances\n";
      if($options{'detailed-diag'}) {
        print "    Recommandation: effectuer l'une des deux actions suivantes\n";
        print "      - configurer la valeur du paramètre AutoTuningLevelGroupPolicy à \"Normal\" dans la stratégie de groupe\n";
        print "      - utiliser la configuration locale pour ce paramètre (configurer le valeur du paramètre AutoTuningLevelEffective à \"Local\")\n";
      }
    }
    if(defined $tcpConf{ScalingHeuristics} && $tcpConf{ScalingHeuristics} ne 'Disabled') {
      $degradedTcpConf=1;
      print "[!] La valeur actuelle de ScalingHeuristics peut dégrader les performances\n";
      if($options{'detailed-diag'}) {
        print "    Recommandation: ajuster le paramètre avec une des deux commandes suivantes\n";
        print "      [PowerShell] Set-NetTCPSetting -SettingName Internet -ScalingHeuristics Disabled\n";
        print "      [cmd.exe] netsh interface tcp set heuristics disabled\n";
      }
    }
    my $rmemMax;
    if(defined $tcpConf{'net.core.rmem_max'}) {
      if($tcpConf{'net.core.rmem_max'} =~ /^\s*(\d+)\s*$/) {
        ($rmemMax,$rmemMaxParam)=($1,'net.core.rmem_max');
      }else{
        print "[!] Valeur de net.core.rmem_max non reconnue\n";
      }
    }
    if(defined $tcpConf{'net.ipv4.tcp_rmem'}) {
      if($tcpConf{'net.ipv4.tcp_rmem'} =~ /^\s*(\d+)\s+(\d+)\s+(\d+)\s*$/) {
        ($rmemMax,$rmemMaxParam,$rmemMaxValuePrefix)=($3,'net.ipv4.tcp_rmem',"$1 $2 ");
      }else{
        print "[!] Valeur de net.ipv4.tcp_rmem non reconnue\n";
      }
    }
    if(defined $tcpConf{'net.ipv4.tcp_adv_win_scale'}) {
      if($tcpConf{'net.ipv4.tcp_adv_win_scale'} =~ /^\s*(-?\d+)\s*$/ && $&) {
        $tcpAdvWinScale=$1;
      }else{
        print "[!] Valeur de net.ipv4.tcp_adv_win_scale non reconnue\n";
      }
    }
    if(defined $rmemMax) {
      if(defined $tcpAdvWinScale) {
        my $overHeadFactor=2 ** abs($tcpAdvWinScale);
        $rcvWindow=$rmemMax/$overHeadFactor;
        $rcvWindow=$rmemMax-$rcvWindow if($tcpAdvWinScale > 0);
        my $maxRttMsFor1Gbps = int($rcvWindow * 1000 / $GOODPUT_1Gbps_Bytes + 0.5);
        print "  => Latence TCP max pour une réception à 1 Gbps: ${maxRttMsFor1Gbps} ms\n";
        if($maxRttMsFor1Gbps < $RECOMMENDED_MIN_RTT_MAX_FOR_FULL_BANDWIDTH) {
          if($tcpAdvWinScale < -3) {
            print "[!] Les valeurs actuelles de net.ipv4.tcp_adv_win_scale et $rmemMaxParam peuvent dégrader les performances\n";
          }else{
            print "[!] La valeur actuelle de $rmemMaxParam peut dégrader les performances\n";
            if($options{'detailed-diag'}) {
              print "    Recommandation: ajuster le paramètre avec la commande suivante\n";
              print "      sysctl -w $rmemMaxParam=".rcvWindowToRmemValue($RECOMMENDED_MIN_RCV_WINDOW_SIZE)."\n";
            }
          }
        }
      }else{
        print "[!] Valeur de net.ipv4.tcp_adv_win_scale non trouvée\n";
      }
    }
  }else{
    print "[!] Echec de lecture des paramètres TCP\n";
  }
}

sub rcvWindowToRmemValue {
  my $newRcvWindow=shift;
  my $overHeadFactor=2 ** abs($tcpAdvWinScale);
  my $newRmemValue=$overHeadFactor*$newRcvWindow;
  $newRmemValue/=($overHeadFactor-1) if($tcpAdvWinScale > 0);
  $newRmemValue=fixMemSize($newRmemValue);
  $newRmemValue="\"$rmemMaxValuePrefix$newRmemValue\"" if(defined $rmemMaxValuePrefix);
  return $newRmemValue;
}

sub fixMemSize { return POSIX::ceil($_[0]/POSIX::BUFSIZ())*POSIX::BUFSIZ() }

sub testTcp {
  my ($type,$as,$cca)=@_;
  my ($testDescription,$testIp,$testPort,$testUrl,$testTimeout,$expectedMaxLatency)=getTestData($type,$as,$cca);
  print "Test TCP $testDescription...\n";
  my $rttMs=getTcpLatency($testIp,$testPort,$testTimeout);
  if(! defined $rttMs) {
    if($type eq 'local') {
      print "[!] Echec du test de latence\n";
      quit("    En cas d'absence de Freebox, le paramètre --skip-lan-check (-L) doit être utilisé pour désactiver le test local");
    }else{
      quit('[!] Echec du test de latence');
    }
  }
  print "  --> Latence: $rttMs ms\n";
  print '[!] Latence élevée pour une connexion '.($type eq 'local' ? 'locale' : 'FTTH')."\n" if($rttMs > $expectedMaxLatency);
  my $maxThroughput=checkMaxThroughputForLatency($rttMs);
  $httpClient->{timeout}=$testTimeout;
  my $dlSpeed=getDlSpeed($testUrl);
  print '  --> Débit: '.readableDlSpeed($dlSpeed)."\n";
  return ($dlSpeed,$maxThroughput);
}

sub getTestData {
  my $testDescription=$_[0].' ('.($_[0] eq 'local' ? 'Freebox' : join('-',@_[1,-1])).')';
  my $r_testData=\%TEST_DATA;
  while(my $testMode=shift) {
    $r_testData=$r_testData->{$testMode};
  }
  return ($testDescription,@{$r_testData}[0,1],"http://$r_testData->[0]:$r_testData->[1]/$r_testData->[2]",@{$r_testData}[3,4]);
}

sub getTcpLatency {
  my ($ip,$port,$timeout)=@_;
  $port//=80;
  $timeout//=5;
  
  my $pinger=Net::Ping->new({proto => 'tcp', timeout => $timeout, family => 'ipv4'});
  $pinger->hires();
  $pinger->port_number($port);
  my $minPingTime;
  my $nbPings=5;
  for my $i (1..$nbPings) {
    my $elapsedTime=time();
    my ($pingRes,$pingTime)=$pinger->ping($ip);
    return undef unless($pingRes);
    $minPingTime=$pingTime unless(defined $minPingTime && $minPingTime < $pingTime);
    $elapsedTime=time()-$elapsedTime;
    sleep(1-$elapsedTime) if($elapsedTime < 1);
  }
  $pinger->close();

  my $streamPinger=Net::Ping->new({proto => 'stream', timeout => $timeout, family => 'ipv4', pingstring => "PING\n"});
  $streamPinger->hires();
  $streamPinger->port_number($port);
  for my $i (1..$nbPings) {
    my $elapsedTime=time();
    return undef unless($streamPinger->open($ip));
    my $openTime=time()-$elapsedTime;
    $minPingTime=$openTime unless($minPingTime < $openTime);
    my ($pingRes,$pingTime)=$streamPinger->ping($ip);
    $streamPinger->close();
    return undef unless(defined $pingRes && defined $pingTime);
    $minPingTime=$pingTime unless($minPingTime < $pingTime);
    $elapsedTime=time()-$elapsedTime;
    sleep(1-$elapsedTime) if($elapsedTime < 1 && $i < $nbPings);
  }

  return sprintf('%.2f',$minPingTime*1000);
}

sub checkMaxThroughputForLatency {
  return undef unless($rcvWindow);
  my $latency=shift;
  my $maxThroughput=$rcvWindow*1000/$latency;
  if($maxThroughput < $GOODPUT_1Gbps_Bytes) {
    print "[!] Avec cette latence, le paramétrage actuel de mémoire tampon TCP pourrait limiter le débit à environ ".readableDlSpeed($maxThroughput)."\n";
    if($options{'detailed-diag'} && $tcpAdvWinScale > -4) {
      print "    Recommandation: si la latence estimée est correcte, augmenter la mémoire tampon max avec la commande suivante\n";
      print "      sysctl -w $rmemMaxParam=".rcvWindowToRmemValue($GOODPUT_1Gbps_Bytes*$latency/1000)."\n";
    }
    return $maxThroughput;
  }
  return undef;
}

sub getDlSpeed {
  my $url=shift;
  my ($startTime,$downloadedSize,$dlSpeed)=(time(),0);
  my ($chunkStartTime,$chunkEndTime,$chunkDownloadedSize,$r_dataCallback)=($startTime,$startTime+1,0);
  my @chunkDlSpeeds;
  if(wantarray()) {
    $r_dataCallback = sub {
      my $currentTime=time();
      my $dlSize=length($_[0]);
      $downloadedSize+=$dlSize;
      $chunkDownloadedSize+=$dlSize;
      if($currentTime > $chunkEndTime) {
        push(@chunkDlSpeeds,$chunkDownloadedSize/($currentTime-$chunkStartTime));
        $chunkStartTime=$currentTime;
        do { $chunkEndTime++ } while($chunkEndTime < $chunkStartTime+0.5);
        $chunkDownloadedSize=0;
      }
      if($currentTime-$startTime>$maxDlDuration) {
        $dlSpeed=$downloadedSize/($currentTime-$startTime);
        die 'MAX_DL_DURATION';
      }
    };
  }else{
    $r_dataCallback = sub {
      my $currentTime=time();
      $downloadedSize+=length($_[0]);
      if($currentTime-$startTime>$maxDlDuration) {
        $dlSpeed=$downloadedSize/($currentTime-$startTime);
        die 'MAX_DL_DURATION';
      }
    };
  }
  my $result=$httpClient->get($url,{data_callback => $r_dataCallback});
  $dlSpeed=$downloadedSize/(time()-$startTime) if($result->{success});
  if($result->{success} || ($result->{status} == 599 && substr($result->{content},0,15) eq 'MAX_DL_DURATION')) {
    return wantarray() ? ($dlSpeed,\@chunkDlSpeeds) : $dlSpeed;
  }else{
    my $errorDetail = $result->{status} == 599 ? $result->{content} : "HTTP status: $result->{status}, reason: $result->{reason}";
    quit("[!] Echec de téléchargement de \"$url\" ($errorDetail)");
  }
}

sub readableDlSpeed {
  my $speed=shift;
  my $bitSpeed=$speed*8;
  my @units=('',qw'K M G T');
  my $unitIdx=0;
  my $unitFactor = $options{'binary-units'} ? 1024 : 1000;
  while($speed >= $unitFactor) {
    $speed/=$unitFactor;
    $unitIdx++;
  }
  my $bitUnitIdx=0;
  while($bitSpeed >= $unitFactor) {
    $bitSpeed/=$unitFactor;
    $bitUnitIdx++;
  }
  return sprintf('%.2f',$speed).' '.$units[$unitIdx].($options{'binary-units'} ? 'i' : '').'o/s ('.sprintf('%.2f',$bitSpeed).' '.$units[$bitUnitIdx].($options{'binary-units'} ? 'i' : '').'bps)';
}

usage() if($options{help});
quit("$PROGRAM_NAME v$VERSION") if($options{version});
checkForNewVersion() unless($options{'skip-update-check'});
printIntroMsg() unless($options{'skip-intro'});
print "\n";
printHeaderLine();
printTimestampLine();

if(! $options{'no-diag'}) {
  getTcpConf();
  tcpConfAnalysis();
  print "\n";
}

if(! $options{'skip-lan-check'}) {
  my ($localDlSpeed,$localMaxThroughput)=testTcp('local');
  if(! $options{'no-diag'} && $localDlSpeed < 70 * 1_000_000) {
    print "\nDébit local insuffisant pour déterminer si la connexion est affectée par un dysfonctionnement de boîtier ONU Free.\n";
    if($degradedTcpConf || (defined $localMaxThroughput && $localDlSpeed > 3 * $localMaxThroughput / 5)) {
      print '  => VERIFIER LE PARAMETRAGE DE LA MEMOIRE TAMPON TCP'.($options{'detailed-diag'} ? '' : " (paramètre --detailed-diag pour plus de détails)")."\n";
    }else{
      print "  => VERIFIER QU'UNE LIAISON FILAIRE EST UTILISEE ET QUE RIEN D'AUTRE NE CONSOMME DE LA BANDE PASSANTE NI DU CPU SUR LE SYSTEME (RELANCER LE TEST LE CAS ECHEANT)\n";
    }
    quit();
  }
  print "\n";
}

my $srvAs = $options{'alternate-srv'} ? 'AS5410' : 'AS12876';

my ($internetBbrDlSpeed,$internetBbrMaxThroughput)=testTcp('Internet',$srvAs,'BBR');
my $internetBbrDlSpeedMB=$internetBbrDlSpeed/1_000_000;
if(! $options{'no-diag'} && ! $options{'skip-lan-check'}) {
  if($internetBbrDlSpeedMB < 55
     && ($degradedTcpConf || (defined $internetBbrMaxThroughput && $internetBbrDlSpeed > 3 * $internetBbrMaxThroughput / 5))) {
    print "\nLe paramétrage actuel de la mémoire tampon TCP empêche de déterminer si la connexion est affectée par un dysfonctionnement de boîtier ONU Free.\n";
    quit('  => AJUSTER LE PARAMETRAGE DE LA MEMOIRE TAMPON TCP'.($options{'detailed-diag'} ? '' : " (paramètre --detailed-diag pour plus de détails)"));
  }
  if($internetBbrDlSpeedMB < 20) {
    print "\nDébit Internet insuffisant pour déterminer si la connexion est affectée par un dysfonctionnement de boîtier ONU Free.\n";
    quit("  => VERIFIER QUE RIEN D'AUTRE NE CONSOMME DE LA BANDE PASSANTE (RELANCER LE TEST LE CAS ECHEANT)");
  }elsif($internetBbrDlSpeedMB < 45) {
    quit("\n[!] La connexion semble affectée par un dysfonctionnement de boîtier ONU Free.");
  }
}
print "\n";

my ($internetCubicDlSpeed,$internetCubicMaxThroughput)=testTcp('Internet',$srvAs,'CUBIC');
my $internetCubicDlSpeedMB=$internetCubicDlSpeed/1_000_000;
if(! $options{'no-diag'} && ! $options{'skip-lan-check'}) {
  print "\n";
  my $isDegraded;
  if($internetBbrDlSpeedMB < 55) {
    $isDegraded=1;
    print "La connexion POURRAIT être affectée par un dysfonctionnement de boîtier ONU Free.\n";
  }elsif($internetBbrDlSpeedMB < 70 || $internetCubicDlSpeedMB < 70) {
    $isDegraded=1;
    print "La connexion ne semble pas affectée par un dysfonctionnement de boîtier ONU Free mais présente tout de même des performances dégradées.\n";
  }else{
    print "La connexion ne semble pas affectée par un dysfonctionnement de boîtier ONU Free.\n";
  }
  if($internetCubicDlSpeedMB/$internetBbrDlSpeedMB < 1/3) {
    $isDegraded=1;
    print "La connexion semble affectée par une congestion réseau prononcée.\n";
  }elsif($internetCubicDlSpeedMB/$internetBbrDlSpeedMB < 2/3) {
    $isDegraded=1;
    print "La connexion semble affectée par une congestion réseau.\n";
  }
  if($isDegraded) {
    print "  => VERIFIER QUE RIEN D'AUTRE NE CONSOMME DE LA BANDE PASSANTE (RELANCER LE TEST LE CAS ECHEANT)\n";
  }
}
quit();
