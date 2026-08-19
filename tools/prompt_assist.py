# Gemini Prompt Asistent: prevod ceskeho zadani na presny SDXL pixel-art prompt.
#
#   from prompt_assist import enhance_prompt
#   prompt_en = enhance_prompt("fialovy boss s monitory na hrudi")
#
# PRAVIDLA PODLE DOKUMENTACE ART_PIPELINE.MD:
#
# 1. SDXL potrebuje STATICKY POPIS PREDMETU, ne proces ("fixing...", "rotating...").
# 2. Silny obrys a silueta: "chunky silhouette, crisp 1px clean pixel art, vibrant colors".
# 3. Pozadi: "flat solid magenta background" pro ciste vyriznuti pres cut_background.
# 4. Pohled: "low top-down 3/4 view, facing the viewer".
# 5. Styl rodiny junk-food: obří oči, naddimenzované prvky, junk-food doplňky.
import os
import sys
import urllib.request
import json

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
KEY_FILE = os.path.join(PROJ, ".gemini_api_key")

SYSTEM_INSTRUCTION = """You are an expert pixel art prompt engineer modeled on PixelLab v3/Pro character generation for a retro Tower Defense RPG.
Your job is to convert any user creature/enemy/character concept into a professional, highly-structured 64x64 pixel art sprite prompt.

A top-tier PixelLab prompt follows this EXACT 5-block structure:
1. [Header & Archetype]: "64x64 pixel art character sprite, sturdy/agile/colossal [Name] [Role] unit."
2. [Body, Materials & Clothing]: Exact physical material, anatomy, armor plates with rivets/straps/seams (e.g., "Heavy stocky body made of... wearing a dark iron-plated cuirass with riveted straps").
3. [Head & Signature Tell]: Distinctive head shape and high-readability feature (e.g., "The head is a massive glowing cyclops eye with sharp teeth" or "wearing a dense vegetable battle helmet").
4. [Props, Hands & Stance]: Held objects and stance (e.g., "Holding a solid reinforced shield in left hand and heavy war mallet in right hand. Wide grounded defensive combat stance").
5. [Perspective, Shading & Palette]: Always end with: "strictly front-facing low top-down RPG perspective (aligned straight to square grid, zero 45-degree isometric tilt). Gritty pixel dithering, high contrast deep shadows, [3-4 specific theme colors] palette. Flat solid magenta background."

IMPORTANT LENGTH LIMIT: the result is fed to CLIP, which reads at most 77 tokens and
SILENTLY DISCARDS the rest. Stay under 55 tokens (roughly 40 words). Drop block 2
(materials, rivets, straps) first — at 64 px it is invisible anyway. Keep the archetype,
the head tell and the palette.
NEVER use process verbs ("try to fix", "generate", "drawn by"). Return ONLY the final English prompt.
"""

# ------------------------------------------------------------ dvě délky promptu
#
# JEDEN ZDROJ, DVĚ PODOBY. PixelLab i lokalni SDXL chteji tentyz popis, ale kazdy jinak
# dlouhy — a drzet dva rucne psane texty vedle sebe znamena, ze se do mesice rozejdou.
# Proto se popis drzi po BLOCICH a obe podoby se z nich skladaji.
#
# PROC TO VUBEC MUSELO VZNIKNOUT. Puvodni sablony mely 120 az 166 tokenu vcetne gen.STYLE,
# tedy o 43 az 89 pres limit CLIPu. Lokalni model z nich videl zhruba polovinu a utrzek
# koncil uprostred vety — a nikde se to nehlasilo. Je to tatáz tichá past, ze ktere vzesel
# roj lebek misto jedne prisery i seda pozadi (viz komentar u gen.NEGATIVE).
#
# CO SE DO KRATKE PODOBY VEJDE. Vybira se to, co na 64 px doopravdy nese identitu:
# archetyp, hlavovy poznavaci znak a paleta. Materialy, nyty a remínky z bloku 2 se na
# 64 px stejne nevykresli — a zmereno je, ze prompt kolem 55 tokenu dostal 9,1-9,7,
# kdezto 120tokenovy dal kasi. Kratsi tu tedy neni kompromis, je to lepsi vysledek.
#
# Do PixelLabu jde naopak podoba PLNA: limit CLIPu je vlastnost naseho SDXL, ne jeho.
BLOKY = {
    "boss": {
        "archetyp": "colossal Boss distraction unit",
        "telo": "massive towering body of stacked CRT monitors and junk food slabs "
                "with exposed glowing copper wiring",
        "hlava": "one oversized magenta cyclops lens with static glitch",
        "rekvizity": "metallic fist, electrical cable whip, wide menacing stance",
        "paleta": "neon magenta, electric cyan, dark charcoal",
    },
    "broccoli": {
        "archetyp": "sturdy Broccoli Knight defender unit",
        "telo": "stocky humanoid body of thick green stalk in a dark iron cuirass "
                "with riveted leather straps",
        "hlava": "dense broccoli crown worn as a battle helmet",
        "rekvizity": "round wooden shield with dark metal rim, heavy war mallet, "
                     "wide grounded defensive stance",
        "paleta": "moss green, charcoal, warm wood",
    },
    "clickbait": {
        "archetyp": "squat heavy Clickbait brute distraction unit",
        "telo": "chunky muscular body of greasy burger patties and melted cheese, "
                "dark spiked wristbands",
        "hlava": "grotesque burger bun with jagged teeth and one giant magenta eyeball",
        "rekvizity": "clenched fists, aggressive brawler stance",
        "paleta": "toasted brown, glowing magenta, cheddar gold",
    },
    "energy": {
        "archetyp": "agile Energy Drink speedster unit",
        "telo": "jittery cylindrical can body with lightning decals and glowing blue "
                "fluid seams",
        "hlava": "crackling electrical spark antenna on top",
        "rekvizity": "thin robotic spider legs, twitching stance",
        "paleta": "electric cyan, neon yellow, matte black",
    },
    "phone": {
        "archetyp": "stealthy Doomscroll distraction unit",
        "telo": "sleek dark smartphone monolith body, OLED screen with scrolling red "
                "notifications",
        "hlava": "glowing camera sensor eyes",
        "rekvizity": "four twitching metallic insect legs, creeping stance",
        "paleta": "obsidian black, notification red, phosphor green",
    },
}

# Ocas plne podoby. Do kratke se nedava: gen.STYLE uz rika totez uspornejc a perspektivu
# si u --pose stejne vynucuje kostra, ne text.
# Hue shift v ocasu neni kosmeticke slovo: style_audit.py (18.8.2026) zmeril, ze bez
# vyslovne barvy stinu generator sklouzne k cernemu zeslabeni (terrain/path/*.png
# vyslo 2-4 stupne misto cile 20+). "deep shadows" samo o sobe tohle nehlida.
# Limit CLIPu tady neplati (viz PIXELLAB.md — plna podoba jde primo do PixelLabu),
# takze se to smi vypsat cele misto zkratky.
OCAS_PLNY = ("strictly front-facing low top-down RPG perspective (aligned straight to "
             "square grid, zero 45-degree isometric tilt). Gritty pixel dithering, "
             "high contrast deep shadows that shift hue cool toward blue/violet, never "
             "a flat black falloff, {paleta} palette. Flat solid magenta background.")


# Sochařská forma věží (19. 8. 2026) — jiná osa než hue shift výš, obě platí zároveň.
# Hue shift říká JAKÝ ODSTÍN má stín mít; tenhle chvost říká PODLE JAKÉHO TVARU se po
# objektu rozkládá (odstupňované pásy podle formy, jeden směr světla, zaoblené hrany,
# kontaktní AO). Vzniklo z rozboru reference, kterou uživatel poslal (mobilní TD hra) —
# schváleno přebrat POUZE sochařskost, ne paletu ani rendering (viz ART_PIPELINE.md §3c
# pro plné odůvodnění a "co si z reference NEBRAT"). Zatím nemá vlastní BLOKY/builder —
# věže na rozdíl od príšer výš nemají v repu žádný commitnutý prompt-generátor — takže
# tahle konstanta čeká, až nějaký vznikne. `tower_01_FOCUS_final.png` (dnešní obelisk,
# mimo assets/) je důkaz, že fráze funguje, aniž by se cokoli dalšího muselo přegenerovat.
TOWER_FORM_TAIL = (
    "sculptural stepped massing divided into distinct tiers — wide base, mid shaft, "
    "capping crown — each tier a separate plane with its own tone. Single consistent "
    "light source from directly above: top-facing surfaces brightest, side faces "
    "darker, undersides near-black. Rounded, chamfered edges, no sharp right angles. "
    "Soft contact shadow / ambient occlusion where the base meets the ground, thin "
    "rim-light along the lit top edge. Pixel art on a hard grid — no smooth painted "
    "gradients, no anti-aliased curves."
)


def prompt_pixellab(b):
    """Plna podoba pro PixelLab. Bez limitu delky — 77 tokenu je vlastnost naseho CLIPu."""
    return (f"64x64 pixel art character sprite, {b['archetyp']}. {b['telo'].capitalize()}. "
            f"The head is {b['hlava']}. {b['rekvizity'].capitalize()}. "
            + OCAS_PLNY.format(paleta=b["paleta"]))


def prompt_sdxl(b):
    """Kratka podoba pro lokalni nahled. MUSI se vejit do 77 tokenu i s gen.STYLE.

    Hlida to `zkontroluj_delky()` a test na konci souboru — nikoli oko, protoze prave
    tohle se pri rucni uprave pokazde znovu utrhne a nikdo si toho nevsimne."""
    return (f"{b['archetyp']}, {b['hlava']}, {b['paleta']} palette, "
            f"low top-down RPG perspective")


def zkontroluj_delky(verbose=True):
    """Vejdou se vsechny kratke podoby do limitu? -> seznam (jmeno, tokenu, ok).

    Bez tokenizeru (napr. bez nainstalovanych transformers) se odhaduje po slovech —
    radsi hruby odhad nez zadna kontrola, protoze bez ni se preteceni nepozna vubec."""
    try:
        import gen
        from transformers import CLIPTokenizer
        tk = CLIPTokenizer.from_pretrained(gen.BASE_MODEL, subfolder="tokenizer")
        styl = gen.STYLE
        pocet = lambda t: len(tk(t).input_ids)          # noqa: E731
        limit = gen.TOKEN_LIMIT
    except Exception:
        styl = "pixel art, solid magenta background, centered single creature, dark outline"
        pocet = lambda t: int(len(t.split()) * 1.4) + 2  # noqa: E731
        limit = 77
    out = []
    for jmeno, b in sorted(BLOKY.items()):
        n = pocet(f"{prompt_sdxl(b)}, {styl}")
        out.append((jmeno, n, n <= limit))
        if verbose:
            print(f"  {jmeno:10s} {n:3d}/{limit} tokenů  {'OK' if n <= limit else 'PŘETÉKÁ'}")
    return out


# Zpetna kompatibilita: gen_ui saha na RULE_TEMPLATES a ceka kratkou podobu pro SDXL.
RULE_TEMPLATES = {k: prompt_sdxl(v) for k, v in BLOKY.items()}

# Plne podoby pro PixelLab — sem sahej, kdyz zadavas do PixelLabu.
PIXELLAB_TEMPLATES = {k: prompt_pixellab(v) for k, v in BLOKY.items()}

# Puvodni doslovne sablony jsou pryc zamerne: byly to petibloke texty psane rucne,
# tedy presne to, co se rozejde. Dnes je zdrojem BLOKY vys a obe podoby se skladaji.


def get_api_key():
    env_key = os.environ.get("GEMINI_API_KEY")
    if env_key:
        return env_key.strip()
    if os.path.isfile(KEY_FILE):
        try:
            return open(KEY_FILE, encoding="utf-8").read().strip()
        except Exception:
            pass
    return ""


def enhance_prompt(text_cs: str, api_key: str = None) -> str:
    """Prevede cesky text na optimalizovany SDXL pixel-art prompt."""
    text = (text_cs or "").strip()
    if not text:
        return ""

    key = api_key or get_api_key()
    if key:
        try:
            url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key={key}"
            payload = {
                "contents": [
                    {"role": "user", "parts": [{"text": f"User concept: {text}\nGenerate the SDXL pixel art prompt."}]}
                ],
                "systemInstruction": {
                    "parts": [{"text": SYSTEM_INSTRUCTION}]
                },
                "generationConfig": {
                    "temperature": 0.3,
                    "maxOutputTokens": 100
                }
            }
            req = urllib.request.Request(
                url,
                data=json.dumps(payload).encode("utf-8"),
                headers={"Content-Type": "application/json"}
            )
            with urllib.request.urlopen(req, timeout=8) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                out = data["candidates"][0]["content"]["parts"][0]["text"].strip()
                return out.strip('"').strip("'")
        except Exception as e:
            # Fallback na sablonovy generator pri offline / chybe site
            pass

    # Offline / Template-based fallback
    lower = text.lower()
    for kw, tpl in RULE_TEMPLATES.items():
        if kw in lower:
            return tpl

    # Obecna sablona
    return (f"{text}, chunky silhouette, single creature, 1px crisp outline, "
            f"vibrant contrasting colors, low top-down 3/4 view, "
            f"flat solid magenta background, crisp pixel art sprite")


if __name__ == "__main__":
    import sys
    query = sys.argv[1] if len(sys.argv) > 1 else "fialový boss s monitory a velkým okem"
    print("Vstup: ", query)
    print("Výstup:", enhance_prompt(query))
