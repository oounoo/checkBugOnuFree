# checkBugOnuFree
Programme de diagnostique de connexion FTTH Free avec boîtier ONU

Ce programme effectue des tests de débit en mono-session TCP afin d'évaluer la
possibilité que la connexion FTTH soit affectée par un dysfonctionnement du
boîtier ONU Free.
Il est aussi possible d'utiliser ce programme sur une infrastructure sans
Freebox pour comparer les résultats, à condition de désactiver le test de débit
local via le paramètre --skip-lan-check (voir --help pour plus d'information).
