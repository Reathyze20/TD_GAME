class_name InsightCardData extends Resource
## The educational card shown between levels, tying a real concept to what the
## player just experienced.

@export var level_id: int = 1
@export var title: String = ""
@export var concept: String = ""
@export_multiline var description: String = ""
@export_multiline var takeaway: String = ""
## Odkud to je. Prazdne = tvrzeni bez zdroje, coz je presne to, co dela kazdy
## clanek o dopaminu na internetu — a hra, ktera uci o pozornosti, si to dovolit nemuze.
## Kratky format "Autor et al., rok — o cem to bylo", ne plna citace: cilem je, aby si
## to hrac mohl dohledat, ne aby to vypadalo akademicky.
@export var citation: String = ""

@export var color: String = "4aa3ff"
