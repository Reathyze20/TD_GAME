# Roster — co ve hře je

> **Generováno z `data/*.tres`.** Needituj ručně — spusť
> `python tools/roster.py --md > docs/ROSTER.md`. Ručně psané soupisy
> v tomhle repu už třikrát zvětraly (viz varování v `docs/core/11`).

## Distrakce (nepřátelé)

| id | jméno | HP | rychlost | comp | rat | Dopamin | Focus dmg | archetyp | kde |
|---|---|---|---|---|---|---|---|---|---|
| `adult_content` | Adult Content | 60 | 50.0 | 5 | 2 | 12 | 5 | — | **nikde** |
| `autoplay` | Autoplay | 12 | 110.0 | 0 | 0 | 2 | 1 | — | **nikde** |
| `clickbait` | Clickbait | 70 | 55.0 | 4 | 2 | 9 | 3 | golem | **nikde** |
| `comparison` | Comparison | 48 | 64.0 | 0 | 0 | 7 | 3 | — | **nikde** |
| `doomscroll` | Doomscroll | 40 | 68.0 | 4 | 0 | 5 | 2 | — | L1(w1) L98(w3) |
| `energy_drink` | Energy Drink | 30 | 105.0 | 1 | 0 | 6 | 2 | energiser, overdrive | **nikde** |
| `fomo` | FOMO | 22 | 168.0 | 0 | 0 | 11 | 0 | — | **nikde** |
| `group_chat` | Group Chat | 45 | 55.0 | 2 | 1 | 8 | 3 | disruptor | **nikde** |
| `jackpot` | Jackpot | 55 | 62.0 | 3 | 3 | 14 | 4 | — | **nikde** |
| `just_one_more` | Just One More | 34 | 72.0 | 0 | 0 | 2 | 2 | — | **nikde** |
| `notification` | Notification | 5 | 140.0 | 0 | 0 | 1 | 1 | — | L98(w1) |
| `phantom_buzz` | Phantom Buzz | 8 | 125.0 | 2 | 0 | 3 | 1 | letec | **nikde** |
| `social_media_binge` | Social Media Binge | 900 | 50.0 | 6 | 4 | 40 | 15 | BOSS | **nikde** |

## Habity (věže)

| id | jméno | cena | Willpower | Awareness | cooldown | dosah | vlastnosti |
|---|---|---|---|---|---|---|---|
| `accountability` | Nutrition Guild | 55 | 0 | 0 | 0.0 | 0.0 | barracks, → accountability_2 |
| `accountability_2` | Fresh Pantry | 85 | 0 | 0 | 0.0 | 0.0 | barracks |
| `anchor` | Anchor | 20 | 0 | 0 | 999.0 | 260.0 | — |
| `exercise` | Exercise | 70 | 34 | 0 | 1.1 | 390.0 | → exercise_2 |
| `exercise_2` | Peak Movement | 80 | 60 | 0 | 0.9 | 460.0 | — |
| `focus_pillar` | Focus Pillar | 70 | 0 | 20 | 4.0 | 300.0 | AoE, stun 1.2s, dispel |
| `focus_timer` | Focus Timer | 30 | 3 | 0 | 0.10 | 160.0 | pomodoro, → focus_timer_2 |
| `focus_timer_2` | Deep Focus | 50 | 5 | 0 | 0.06 | 420.0 | pomodoro |
| `mindfulness` | Mindfulness | 45 | 0 | 5 | 0.7 | 260.0 | AoE, slow 50%, → mindfulness_2 |
| `mindfulness_2` | Deep Mindfulness | 55 | 0 | 10 | 0.55 | 320.0 | AoE, slow 62% |
| `real_hobby` | Deep Reading | 60 | 0 | 2 | 0.15 | 520.0 | DoT 3/s, → real_hobby_2 |
| `real_hobby_2` | Passion Project | 90 | 0 | 3 | 0.12 | 560.0 | DoT 5/s |
| `zen_pulsar` | Zen Pulsar | 70 | 0 | 20 | 4.0 | 300.0 | AoE, stun 1.2s, dispel, → zen_pulsar_2a, zen_pulsar_2b |
| `zen_pulsar_2a` | Resonance Wave | 90 | 0 | 30 | 4.0 | 420.0 | AoE, stun 1.2s, dispel, vuln +25%/3s |
| `zen_pulsar_2b` | Overclocked Stillness | 85 | 0 | 14 | 2.8 | 300.0 | AoE, stun 0.7s, dispel |

## Intervence (aktivní schopnosti)

| id | jméno | typ | cooldown | rádius | cena v Rush |
|---|---|---|---|---|---|
| `airplane_mode` | Airplane Mode | `freeze_field` | 45.0 | 0.0 | 3 |
| `call_a_friend` | Call a Friend | `summon_allies` | 30.0 | 44.0 | 0 |
| `deep_breath` | Deep Breath | `freeze_aoe` | 22.0 | 210.0 | 0 |
| `moment_of_clarity` | Moment of Clarity | `reveal_field` | 40.0 | 0.0 | 0 |
| `screen_break` | Screen Break | `damage_aoe` | 18.0 | 180.0 | 0 |
