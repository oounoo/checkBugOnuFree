# checkBugOnuFree
Programme de diagnostique de connexion FTTH Free avec boîtier ONU

Ce programme effectue des tests de débit en mono-session TCP afin d'évaluer la
possibilité que la connexion FTTH soit affectée par un dysfonctionnement du
boîtier ONU Free.
Il est aussi possible d'utiliser ce programme sur une infrastructure sans
Freebox pour comparer les résultats, à condition de désactiver le test de débit
local via le paramètre --skip-lan-check.

Usage:

    perl checkBugOnuFree.pl [<options>]
        --alternate-srv (-a) : Change de serveur pour les tests de débit (AS5410 "Bouygues Telecom" à la place de AS12876 "Scaleway")
        --help (-h) : Affiche l'aide
        --no-diag (-D) : Désactive le diagnostique automatique (tests de débit uniquement)
        --skip-intro (-I) : Désactive le message d'introduction et démarre immédiatement les tests
        --skip-lan-check (-L) : Désactive la vérification du débit local à partir de la Freebox (tests de débit Internet uniquement)
        --skip-update-check (-U) : Désactive la vérification de disponibilité de nouvelle version
        --version (-v) : Affiche la version
