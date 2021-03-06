# checkBugOnuFree
Programme de diagnostique de connexion FTTH Free avec boîtier ONU

Ce programme vérifie la configuration TCP du système et effectue des tests de
débit en mono-session TCP afin d'évaluer la possibilité que la connexion FTTH
soit affectée par un dysfonctionnement du boîtier ONU Free.
Il est aussi possible d'utiliser ce programme sur une infrastructure sans
Freebox pour comparer les résultats, à condition de désactiver le test de débit
local via le paramètre --skip-lan-check.

Usage:

    perl checkBugOnuFree.pl [<options>]
        --alternate-srv (-a) : Change de serveur pour les tests de débit (AS5410 "Bouygues Telecom" à la place de AS12876 "Scaleway")
        --binary-units (-b) : Utilise les préfixes binaires pour le système d'unités de débit
        --detailed-diag (-d) : Affiche des messages de diagnostique supplémentaires
        --help (-h) : Affiche l'aide
        --long-download (-l) : Utilise des tests de téléchargement plus longs (multiplie par 2 la durée max des téléchargements)
        --no-diag (-D) : Désactive le diagnostique automatique (tests de débit uniquement)
        --skip-intro (-I) : Désactive le message d'introduction et démarre immédiatement les tests
        --skip-lan-check (-L) : Désactive la vérification du débit local à partir de la Freebox (tests de débit Internet uniquement)
        --skip-update-check (-U) : Désactive la vérification de disponibilité de nouvelle version
        --version (-v) : Affiche la version
