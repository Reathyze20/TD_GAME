# Generator spritu, lokalne na tve karte. Zadny PixelLab, zadna cena za obrazek.
#
#   python tools/gen.py "energy drink creature with legs" --name endrink --n 8
#   python tools/gen.py "..." --size 32 --steps 30 --seed 7
#   python tools/gen.py "path tile, cracked asphalt" --size 16x8
#   python tools/gen.py --list                    # co uz je vygenerovane
#
#   python tools/gen.py "energy drink creature" --from build/gen/endrink/cand_03.png
#   python tools/gen.py "energy drink creature" --from ...png --animate walk
#   python tools/gen.py "energy drink creature" --from ...png --rotate
#
#   python tools/gen.py "broccoli knight" --ref assets/distractions/donut_frame_1.png
#   python tools/gen.py "..." --ref ...png --ref-mode paleta --lora-weight 0.7
#
# JAK TO FUNGUJE A PROC PRAVE TAKHLE
#
# Difuzni modely jsou trenovane na 1024 px. Vygenerovat rovnou 32x32 sprite nejde — je to
# mimo jejich distribuci a vyleze sum. Vsichni proto generuji velke a chytre zmensuji, a
# kvalita toho ZMENSENI je pak dobra polovina vysledku. Postup je:
#
#   1. SDXL + pixel-art LoRA na 1024 px, na plochem pozadi
#   2. odstraneni pozadi zaplavou od rohu (model se prompt-uje na jednolite pozadi,
#      takze zaplava je spolehlivejsi i levnejsi nez dalsi neuronka)
#   3. orez na postavu a doplneni na ctverec — bez toho by prisera na spritu byla mala
#   4. zmenseni MEDIANEM po blocich, ne prumerem: prumer michá barvy sousedu a udela
#      z ostre hrany kasi, median vybere tu, ktera v bloku prevlada
#   5. sprite_cleanup.py — paleta a sum, tytez funkce, ktere cistí PixelLabu
#   6. art_check.py — znamka, tytez miry, kterymi se meri zbytek hry
#
# Kroky 5 a 6 se IMPORTUJI, nekopiruji. Kdyby generator mel vlastni kopii cisteni, rozejde
# se s tim, co dela zbytek pipeline, a "prosel u generatoru" prestane znamenat "projde u
# lintru".
#
# Vysledek jde do build/gen/<jmeno>/ a NIKDY primo do assets/. Mezi "vygenerovano" a "ve
# hre" musi byt tvoje rozhodnuti — jinak jsme zpatky u toho, ze se do hry dostane rozbity
# art a zjisti se to za mesic.
import argparse
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODELS = os.path.join(PROJ, "models")
OUT = os.path.join(PROJ, "build", "gen")

# Vahy patri do models/ (v .gitignore), ne do ~/.cache — projekt tak zustane prenositelny
# a je videt, co zabira misto. Musí se nastavit PRED importem diffusers.
os.environ.setdefault("HF_HOME", MODELS)

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sprite_cleanup import build_palette, despeckle, remap, to_oklab   # noqa: E402
from art_check import isolated_ratio, palette_budget                   # noqa: E402
import gen_ref                                                          # noqa: E402
import gen_pose                                                         # noqa: E402

BASE_MODEL = "stabilityai/stable-diffusion-xl-base-1.0"
VAE_MODEL = "madebyollin/sdxl-vae-fp16-fix"   # fp16 SDXL VAE jinak vyrabí cerne obrazky
LORA = "nerijs/pixel-art-xl"
LORA_ADAPTER = "pixel"      # jmeno adapteru; bez nej se na nej neda sahnout set_adapters

# SILA LoRA JE HLAVNI PAKA NA DETAIL. Zmereno, ne odhadnuto:
#
#   1.0   Model zjednodusi tak, ze zahodi prvky z promptu. "blesk na plechovce" pri 1.0
#         zmizel uplne — LoRA prekresli scenu do sve predstavy o pixel artu a detail,
#         ktery v te predstave nema misto, proste vypusti.
#   0.45  Ten samy blesk se objevi. Rozsah 0.45-0.7 je misto, kde model porad kresli
#   -0.7  ploche plochy a tvrde hrany, ale jeste posloucha, co je v promptu.
#   0.0   NEPOUZIVAT, i kdyz to zni jako "cisty SDXL". Bez LoRA prestane model kreslit
#         jednolitou magentu a zacne pozadi stinovat — a na jednolite plose stoji
#         cut_background. Sprite pak vyleze s vykousnutymi dirami nebo s pozadim.
#
# Vysledek: 0.55 je vychozi kompromis, ne posvatne cislo. Kdyz chybi detail, jde dolu;
# kdyz se rozpada pixelovy raster, jde nahoru.
LORA_WEIGHT = 0.55

# Kompaktni styl (musi se vejit do 77 tokenu i s uzivatelskym promptem):
STYLE = "pixel art, solid magenta background, centered single creature, dark outline"

# Striktni negativni prompt proti spritesheetum, turnaroundum a texturam.
#
# PORADI NENI LIBOVOLNE a delka uz vubec ne. CLIP bere 77 tokenu; co je za nimi, model
# NEUVIDI — a neohlasi to jako chybu, jen varovanim zahrabanym v logu transformers.
#
# Zmereno 17. 8. 2026: puvodni znění mělo 95 tokenu a tise zahazovalo poslednich osm
# polozek — "pink tint, purple tint, noise, messy, artifacts, duplicate, crowd, team".
# Tedy prave pojistky proti davu a proti prosakovani magenty do postavy. Roj lebek misto
# jedne prisery nebyl rozmar modelu; zaruka proti nemu se k nemu nikdy nedostala.
#
# Proto: napred to, bez ceho se sprite rozpadne (dav, sheet, prosakla barva), az potom
# kosmetika. A cele to musi zustat pod 77 — pri zmene to zmer, neodhaduj.
# Aktualne 76 tokenu.
NEGATIVE = ("duplicate, crowd, team, multiple characters, multiple poses, multiple views, "
            "turnaround, spritesheet, character sheet, collage, grid, tileset, "
            "magenta character, pink tint, purple tint, gradient background, drop shadow, "
            "photo, realistic, 3d render, blurry, soft edges, "
            "noise, messy, artifacts, text, watermark, ui, frame")

# Kolik tokenu vezme textovy enkoder. Neni to nastaveni, je to vlastnost CLIPu.
TOKEN_LIMIT = 77

# NEGATIV PRO POHLED ZEZADU.
#
# Kostra sama pohled zezadu NEUMI rict. Pri otoceni o 180 stupnu je to zrcadlove tataz
# kostra jako zepredu — ramena, boky i koncetiny sedi na tychz mistech. Jediny rozdil je,
# ze zmizi nos a oci, a to model prebije svym sklonem kreslit obliceje: zmereno, sever
# vysel jako celni pohled (zmena pohledu 0,143 proti 0,39 u profilu).
#
# Profil kostra rict UMI (ramena splynou), takze vychod a zapad zadnou pomoc nepotrebuji.
# Tohle je cileně jen na zada.
#
# ZMERENO A NEZABRALO. Zmena pohledu na severu sla z 0,143 na 0,171 a symetrie z 0,919 na
# 0,904 — pri jednom seedu je to sum, ne oprava, a na kontaktnim listu ma sever porad
# oblicej, jen tmavsi oci. Proto je `back_negative` VYCHOZE VYPNUTY: stoji dve polozky
# obecneho negativu a nic za to nedava.
#
# Nechava se tu, protoze az sever vyresi neco jineho (nejspis inpaint pres oblicej), muze
# se hodit jako doplnek — a hlavne aby nekdo za pul roku nezkousel totez znovu.
#
# Musi se to vejit do 77 tokenu i s tim, co uz v NEGATIVE je, takze se koncova kosmetika
# VYMENI za oblicejove zakazy — nepridá se k nim. Kdyby se pridala, useknuti by zahodilo
# prave ty nove polozky a nikdo by se to nedozvedel; presne tak vznikl roj lebek i seda
# pozadi (viz NEGATIVE vys).
#
# Vymenuje se nejmene dulezity konec negativu. Vysledek je 76 tokenu, tedy STEJNE jako
# obecny negativ — margin zustava a nezlomi to prvni budouci uprava.
NEGATIVE_TAIL = "messy, artifacts, text, watermark, ui, frame"
NEGATIVE_BACK = "face, eyes, mouth, facial features, looking at viewer"

BACK_DIRS = ("north", "north-east", "north-west")


def negative_for(direction=None):
    """Negativni prompt pro dany smer. Bez smeru vraci ten obecny."""
    if direction in BACK_DIRS:
        return NEGATIVE.replace(NEGATIVE_TAIL, NEGATIVE_BACK)
    return NEGATIVE

# Pozadi, na ktere je prompt nastaveny a ktere umi cut_background odstranit zaplavou.
MAGENTA = (255, 0, 255)


# ------------------------------------------------------------------ generovani


def _pair(size, default=None):
    """32 -> (32, 32);  (16, 8) -> (16, 8);  None -> default.

    Vsechny funkce, ktere pracuji s velikosti, berou obojí: hra ma ctvercove prisery
    (kde je int cteci) i obdelnikove dlazdice 16x8. Prevod na jednom miste znamena, ze
    se nikde jinde nemusi resit, co prislo."""
    if size is None:
        return default
    if isinstance(size, (tuple, list)):
        w, h = int(size[0]), int(size[1])
    else:
        w = h = int(size)
    return max(1, w), max(1, h)


def build_pipe(lora_weight=LORA_WEIGHT):
    """SDXL + pixel-art LoRA v dane sile. Viz LORA_WEIGHT — to cislo rozhoduje o detailu.

    Vaha se nastavuje pres set_adapters, NE pres fuse_lora. Obojí najednou je past:
    fuse_lora(lora_scale=w) svou vahou NASOBI to, co uz nastavil set_adapters, takze
    0.55 a 0.55 dá 0.30 a nikdo nepozna proc. Fuse se proto pouzije jen jako zaloha na
    starem diffusers bez PEFT, kde set_adapters neexistuje.

    lora_weight=0 znamena LORU VUBEC NENACITAT (ne nacist s nulovou vahou): nulovy
    adapter porad stoji VRAM a cas, a hlavne je poctivejsi, aby bylo z logu videt, ze
    tenhle pipe pixel art neumi."""
    import torch
    from diffusers import AutoencoderKL, StableDiffusionXLPipeline

    if not torch.cuda.is_available():
        sys.exit("CUDA nenalezena — generovani na CPU by trvalo desitky minut na obrazek.")

    lora_weight = float(lora_weight or 0.0)
    print(f"načítám model (poprvé se stáhne ~7 GB do {os.path.relpath(MODELS, PROJ)}/)…")
    vae = AutoencoderKL.from_pretrained(VAE_MODEL, torch_dtype=torch.float16)
    pipe = StableDiffusionXLPipeline.from_pretrained(
        BASE_MODEL, vae=vae, torch_dtype=torch.float16, variant="fp16", use_safetensors=True)

    if lora_weight > 0:
        pipe.load_lora_weights(LORA, adapter_name=LORA_ADAPTER)
        try:
            pipe.set_adapters([LORA_ADAPTER], adapter_weights=[lora_weight])
        except (AttributeError, ValueError):
            # Bez PEFT set_adapters neni. Fuse zapece vahu primo do vah UNetu, cimz ji
            # zdedi i img2img roura z build_img2img (sdili tytez moduly).
            pipe.fuse_lora(lora_scale=lora_weight)
        print(f"  LoRA {LORA} @ {lora_weight}")
    else:
        print("  BEZ LoRA — model přestane kreslit plochou magentu a odstranění pozadí "
              "se rozbije; tohle má smysl jen na srovnání.")

    pipe.to("cuda")
    # 12 GB VRAM staci, ale attention slicing stoji par procent rychlosti a odstrani
    # riziko, ze to spadne na OOM pri vetsim batchi.
    pipe.enable_attention_slicing()
    pipe.set_progress_bar_config(disable=True)
    # Cislo si nese pipe s sebou, aby ho mohl vypsat volajici (CLI i UI) a nemusel ho
    # drzet vedle v promenne, ktera se casem rozejde s tim, co je doopravdy nactene.
    pipe.lora_weight = lora_weight
    return pipe


def _as_img2img(pipe):
    """Roura, ktera umi `image=`. Hotovou img2img vrati beze zmeny, textovou obalí.

    Obalka se schova NA pipe, ne do globalu: generate() muze dostat kazdou chvili jinou
    rouru (UI drzi svou), a globalni cache by druhe z nich podstrcila cizi vahy."""
    if "Img2Img" in type(pipe).__name__:
        return pipe
    cached = getattr(pipe, "_i2i_view", None)
    if cached is None:
        cached = build_img2img(pipe)
        try:
            pipe._i2i_view = cached
        except AttributeError:
            pass
    return cached


def _steps_for(steps, strength):
    """Diffusers denoisuje jen int(steps * strength) kroku. Pri strength 0.2 a 4 krocich
    je to nula: model neudela nic a tise vrati predlohu. Radsi kroky pridat."""
    if int(steps * strength) < 1:
        return int(np.ceil(1.0 / max(strength, 0.01)))
    return steps


# IP-ADAPTER: identita z obrazku misto z textu.
#
# Proc vubec: SDXL dostane 40 slov a domysli si i to, jestli kresli hlavu nebo cele telo.
# Odtud pochazi, ze osm kandidatu je osm ruznych priser. IP-Adapter pusobi v cross-attention
# VEDLE textu — model zacina od sumu jako pri normalnim generovani, ale po celou dobu vidi
# referenci.
#
# Proc ne prosty img2img (--ref-mode zaklad): tam je reference vychozi obraz, ktery model
# prepisuje, takze cim vic ma zmenit, tim min z reference zbyde. Jedna paka na dve veci.
# Tady jsou identita (IP_SCALE) a volnost kompozice (strength/text) dve nezavisla cisla.
#
# Licence: kod i vahy Apache 2.0 (overeno 17. 8. 2026), tedy vcetne komercniho uziti — na
# rozdil od Pixelization a od automatizace Retro Diffusion. Viz docs/art/zmensovani.md.
IP_REPO = "h94/IP-Adapter"
IP_SUBFOLDER = "sdxl_models"
# Zamerne varianta, ktera ma svuj obrazkovy enkoder ve stejne podslozce (sdxl_models/
# image_encoder, ViT-bigG) — diffusers si ho pak najde sam. Varianta ...vit-h.bin je
# podle ohlasu o neco lepsi, ale enkoder ma jinde (models/image_encoder) a musel by se
# predavat rucne pres image_encoder_folder. Az bude duvod, je to jednoradkova zmena.
IP_WEIGHT = "ip-adapter_sdxl.bin"

# Zmereno 17. 8. 2026 (build/gen/_ip_test), tri seedy na silu, azurovy phantom_buzz jako
# reference a fialovo-zluty prompt:
#
#   bez reference  7.8 7.0 8.2   chapadlove skvrny, zadne telo
#   0.4            9.0 8.6 8.4   tela s hlavou a koncetinami, fialova jeste castecne drzi
#   0.6            9.1 8.8 7.8   tela, ale barva z promptu skoro pryc
#   0.8            8.6 8.5 7.9   prebarvena reference, namet zmizel
#
# Rozhoduje BARVA, ne znamka — rozdil 8.67 proti 8.57 je pri trech vzorcich sum.
IP_SCALE = 0.4

# Sila reference pri KOSTROVE ceste. Vyssi nez IP_SCALE, a je to zmerene, ne odhadnute:
# pri 0.4 se avokadovy mnich zmenil v obecneho zeleneho mnicha — avokado zmizelo.
#
# Nedá se to ale zvysovat donekonecna. Reference je CELNI pohled, takze cim silneji drzi
# identitu, tim vic taky drzi POHLED a brzdi otoceni: pri 0.0 se vsechno otoci nadherne,
# jenze uz to neni tataz prisera (viz docs/art/controlnet.md). Tohle je kompromis mezi
# "je to on" a "je otoceny", ne optimum — to se teprve hleda.
POSE_IP_SCALE = 0.6

# Odbarvit subjekt reference pred zakodovanim? Viz gen_ref.ref_identity — bez toho
# reference vnutí i svou paletu a prompt o barvu prijde.
IP_NEUTRAL = True


def _warn_if_truncated(pipe, text, label):
    """Rekne nahlas, ze se prompt nevesel do CLIPu a CO PRESNE odpadlo.

    Bez tohohle je useknuti neviditelne: transformers ho ohlasi varovanim mezi svym
    ostatnim logem, sprite se vygeneruje a vypada jen hur, nez by mel. Cely den hledani
    "proc model neposloucha" muze byt tohle — model poslouchal, jen tu vetu nedostal."""
    tok = getattr(pipe, "tokenizer", None)
    if tok is None:
        return
    ids = tok(text)["input_ids"]
    if len(ids) <= TOKEN_LIMIT:
        return
    lost = tok.decode(ids[TOKEN_LIMIT - 1:-1]).strip()
    print(f"  POZOR: {label} má {len(ids)} tokenů, model uvidí jen prvních {TOKEN_LIMIT}.")
    print(f"         MODEL NEUVIDÍ: {lost}")
    print(f"         Zkrať zadání zhruba na {int((TOKEN_LIMIT - 15) * 0.75)} slov.")


def load_ip_adapter(pipe, scale=IP_SCALE, encoder_on_cpu=False):
    """Nacte IP-Adapter do roury (jen jednou) a nastavi silu. Vraci tutez rouru.

    encoder_on_cpu=True nechá obrazkovy enkoder na PROCESORU. Neni to setrnost, je to
    jediny zpusob, jak se na 12GB kartu vejde ControlNet zaroven s adapterem — a stalo to
    pul odpoledne, nez bylo jasne proc:

        Soubor enkoderu (ViT-bigG) je FP32 a ma 3,69 GB. Nacteni na kartu tedy nejdriv
        vyrobi fp32 kopii a teprve pak z ni fp16 (1,85 GB), takze spicka je pres 5 GB —
        a to na kartu, kde uz sedi SDXL (6,9 GB) a volno je 3,9 GB.

    A ted to podstatne: JE JEDNO, ZE SE PAK ZASE UVOLNI. Jakmile ovladac jednou zacne
    prelevat do systemove pameti, uz z toho v temze procesu nevycouva — po odlozeni
    enkoderu i textovych enkoderu z karty hlasil `mem_get_info` porad `volno 0`. Spicku
    tedy nestaci uklidit, nesmi vzniknout.

    Enkoder se na CPU drzi ve float32, protoze fp16 nema na procesoru pro CLIP vsechny
    kernely. Bezi stejne jen jednou na referenci, takze na jeho rychlosti nezalezi.

    Priznak si drzi roura sama, protoze load_ip_adapter() by pri druhem volani navesil
    adapter podruhe — a dva adaptery na tychz vrstvach nejsou dvakrat silnejsi, jsou
    rozbite.

    Priznak ale nestaci sam o sobe. Sedi na UNETU, ktery je SDILENY mezi vsemi rourami
    (textovou, img2img, controlnet), kdezto obrazkovy enkoder pribyde jen te rouře, na
    ktere se load_ip_adapter zavolalo. Kdyz se pak postavi dalsi roura z pipe.components,
    priznak uz je nastaveny, enkoder v ni ale chybi — a spadne to az uvnitr attention na
    "'tuple' object has no attribute 'shape'". Proto se kontroluje oboji."""
    if not (getattr(pipe.unet, "_td_ip_loaded", False)
            and getattr(pipe, "image_encoder", None) is not None):
        print(f"IP-Adapter: načítám {IP_WEIGHT} (poprvé se stahuje, ~3 GB do models/)")
        # Attention slicing z build_pipe se s IP-Adapterem TLUCE: adapter si prepise
        # attention procesory a sliced varianta se pritom znovu postavi bez slice_size —
        # spadne to na "SlicedAttnProcessor.__init__() missing 1 required positional
        # argument". Slicing je tu stejne jen pojistka proti OOM pri vetsim batchi a
        # generate() jede po jednom obrazku, takze se timhle nic neztraci.
        try:
            pipe.disable_attention_slicing()
        except AttributeError:
            pass
        import torch
        if encoder_on_cpu:
            # Enkoder se musi nacist rovnou na CPU, ne nacist a pak presunout. Presun
            # prichazi POZDE: `pipe.load_ip_adapter` si ho stahne na zarizeni roury, tedy
            # na kartu, a tim spicka uz vznikla — zmereno, karta skocila ze 7 318 na
            # 11 718 MiB jeste driv, nez se dalo cokoli presouvat.
            #
            # `image_encoder_folder=None` rekne diffusers, ze si enkoder obstarava volajici.
            from transformers import CLIPImageProcessor, CLIPVisionModelWithProjection
            if getattr(pipe, "image_encoder", None) is None:
                enc = CLIPVisionModelWithProjection.from_pretrained(
                    IP_REPO, subfolder=f"{IP_SUBFOLDER}/image_encoder",
                    torch_dtype=torch.float32)
                pipe.register_modules(image_encoder=enc,
                                      feature_extractor=CLIPImageProcessor())
            pipe.load_ip_adapter(IP_REPO, subfolder=IP_SUBFOLDER, weight_name=IP_WEIGHT,
                                 image_encoder_folder=None)
        else:
            pipe.load_ip_adapter(IP_REPO, subfolder=IP_SUBFOLDER, weight_name=IP_WEIGHT)
            if getattr(pipe, "image_encoder", None) is not None:
                pipe.image_encoder.to("cuda")
        # Projekcni vrstvy pribyly do UNetu AZ TED, tedy uz po jeho .to("cuda") v
        # build_pipe — bez tohohle by zustaly na CPU a spadlo by to na neshode zarizeni.
        # Presouva se UNet, ne cely pipe: `pipe.to("cuda")` by s sebou vzal i enkoder.
        pipe.unet.to("cuda")
        pipe.unet._td_ip_loaded = True
    pipe.set_ip_adapter_scale(float(scale))
    return pipe


def unload_ip_adapter(pipe):
    """Sunda IP-Adapter z UNetu. Bez tohohle uz obycejne generovani v temze procesu spadne.

    Nacteni adapteru prepise UNetu config na encoder_hid_dim_type='ip_image_proj', cimz se
    `image_embeds` stane POVINNYM argumentem. Kdo pak zavola tutez rouru bez reference,
    dostane:

        ValueError: ... requires the keyword argument `image_embeds` in `added_cond_kwargs`

    A protoze UNet je sdileny mezi textovou i img2img rourou, otrávi to cely proces — ve
    studiu staci jedno generovani s referenci a nasledne doladeni bez ni uz spadne."""
    if getattr(pipe.unet, "_td_ip_loaded", False):
        try:
            pipe.unload_ip_adapter()
        except AttributeError:
            return pipe                      # stary diffusers to neumi; radsi nic nemenit
        pipe.unet._td_ip_loaded = False
    return pipe


# CONTROLNET: tvar zvenci misto tvaru z promptu.
#
# Proc vubec: IP-Adapter rekne modelu KDO to je, ale ne JAK STOJI. Faze 2 to zmerila —
# sestnact "smeru" byly cele celni pohledy (docs/art/rotace.md). Text pohled neurci,
# reference uz vubec ne: obe pusobi na obsah, ne na geometrii.
#
# ControlNet je treti, nezavisla paka. Vedle UNetu bezi kopie jeho enkoderu, ktera dostane
# ridici obrazek a po celou dobu difuze prihravá do hlavni site "tady je rameno, tady
# koleno". Model si smi vymyslet vsechno krome rozlozeni, ktere dostal.
#
# POZOR NA ZAMENU PRICIN. ControlNet NEUMI OTOCIT POSTAVU — umi ji nakreslit do tvaru,
# ktery dostane. Puvodni plan chtel ridici obrazek delat ze siluety zakladniho spritu, coz
# je celni pohled, takze by se celni tvar vnutil i severu a vychodu. Tvar pro kazdy smer
# proto kresli gen_pose z UHLU, ne z predlohy.
#
# Licence: xinsir modely jsou Apache 2.0 (overeno 18. 8. 2026 pres HF API), tedy vcetne
# komercniho uziti — stejne jako IP-Adapter a na rozdil od Pixelization a Retro Diffusion.
CONTROL_MODELS = {
    "openpose": "xinsir/controlnet-openpose-sdxl-1.0",   # kostra: urcuje pohled a pozu
    "scribble": "xinsir/controlnet-scribble-sdxl-1.0",   # cara/silueta: urcuje obrys
}

# Jak silne ridici obrazek tlaci. Zmereno na ctyrech smerech (docs/art/controlnet.md):
#
#     0.7   profil se otoci, ale mekce — symetrie 0,76-0,79
#     0.9   profil je cisty a citelny — symetrie 0,52-0,82, znamky o neco vyssi
#
# Cenou za 0.9 je, ze se vykrok kostry propise i do CELNIHO pohledu (symetrie jihu klesla
# z 0,93 na 0,85). Vadi to min, nez to zni: jizni pohled je PREDLOHA, tedy uz ho mas —
# generuje se jen kvuli spolecne palete a dá se vynechat pres `dirs`.
CONTROL_SCALE = 0.9

# Rozpocet na render pri kostrove ceste. NIZSI NEZ VSUDE JINDE (1024) a je to zmerene, ne
# odhadnute — s ControlNetem uz je na karte tesno a aktivace rostou s PLOCHOU latentu:
#
#     render   s/krok (identita 0,6)
#     1024     2,09
#      768     1,09      <- polovina casu
#      640     0,94      <- uz skoro nic navic
#
# Na sprite 32-64 px zbyde pri 768 porad 12 az 24 zdrojovych pixelu na pixel spritu, tedy
# hluboko nad prahem 8, pod kterym zmenseni zacne zahazovat detail rychleji, nez ho model
# stihne nakreslit. Rozliseni se tu tedy nesnizuje na ukor kvality, jen se prestava platit
# za neco, z ceho na 32pixelovem spritu stejne nic nezbyde.
POSE_RENDER = 768

# Site se drzi v modulu, ne na rouře: kazda vazi ~2,5 GB VRAM a rour se staví vic (test
# si jich udela klidne ctyri za sebou). Cache podle druhu, ne podle roury.
_CONTROL_NETS = {}


def load_controlnet(kind="openpose"):
    """ControlNet dane druhu na karte. Druhe volani uz jen vrati tutez sit."""
    import torch
    from diffusers import ControlNetModel

    net = _CONTROL_NETS.get(kind)
    if net is None:
        repo = CONTROL_MODELS[kind]
        print(f"ControlNet: načítám {repo} (poprvé se stahuje ~2,5 GB do models/)")
        net = ControlNetModel.from_pretrained(repo, torch_dtype=torch.float16,
                                              use_safetensors=True)
        net.to("cuda")
        _CONTROL_NETS[kind] = net
    return net


# Pod kolika MiB uz to opravdu vazne. Zmereno, ne odhadnuto — a je to schvalne NIZKO:
#
#     ~500 MiB   kostrova cesta bezi plnou rychlosti (~0,8 s/krok)
#     ~0 MiB     prelevani, 8 s/krok a vic
#
# Prvni verze mela prah 1200 a houkala i pri tech 500, tedy v konfiguraci, ktera je v
# poradku. Vystraha, ktera plane houka, je horsi nez zadna: clovek si na ni zvykne a
# prehlidne ji i tehdy, kdyz plati.
VRAM_WARN = 256


def vram(label=None, warn_below=VRAM_WARN):
    """(k dispozici, celkem) v MiB. S `label` to i vypise a upozorni, kdyz je na dne.

    Existuje kvuli tomu, ze prekroceni VRAM se NEPROJEVI CHYBOU. Ovladac zacne prelevat do
    systemove pameti a vsechno je desetkrat pomalejsi, ale nic to nenahlasi — bez tohohle
    vypisu se to pozna az na stopkach, nebo vubec ne.

    "K dispozici" NENI to, co hlasi ovladac. PyTorch si drzi vlastni pool a uvnitr nej ma
    volne bloky, ktere muze dat aktivacim, aniz by ovladace na cokoli zadal. Merit jen
    `mem_get_info` proto hlasi poplach i v konfiguraci, ktera bezi dobre (633 MiB "volno"
    a pritom 1,09 s/krok) — a vystraha, ktera plane houka, je horsi nez zadna, protoze si
    na ni clovek zvykne. Scita se tedy oboji:

        k dispozici = volno u ovladace + (rezervovano - obsazeno) v poolu"""
    import torch
    if not torch.cuda.is_available():
        return 0, 0
    MB = 1024 * 1024
    free, total = torch.cuda.mem_get_info()
    free, total = free // MB, total // MB
    pool = (torch.cuda.memory_reserved() - torch.cuda.memory_allocated()) // MB
    usable = free + pool
    if label:
        msg = (f"VRAM po {label}: k dispozici {usable} z {total} MiB "
               f"(ovladač {free} + pool {pool})")
        if usable < warn_below:
            msg += ("\n  POZOR: pod tímhle už ovladač přelévá do systémové paměti. "
                    "Nespadne to, jen bude všechno ~10× pomalejší. Sniž --render, "
                    "vypni --ip-scale, nebo zavři, co drží kartu.")
        print(msg)
    return usable, total


def build_control_pipe(pipe, kind="openpose"):
    """Text2img roura s ControlNetem ze STEJNYCH vah, ktere uz drzi textova roura.

    Text2img zamerne, ne img2img. Img2img by potreboval vychozi obrazek a jediny, ktery je
    po ruce, je zakladni sprite — tedy celni pohled, ktery by pretlacil kostru a vratil
    presne vadu z faze 2. Tady zacina model od sumu a jediny tvar, ktery vidi, je ten
    z kostry.

    Sklada se z pipe.components ze stejneho duvodu jako build_img2img — from_pipe si vynuti
    pretypovani UNetu a naalokuje ho znovu (7,3 -> 12,0 GB a 31x pomaleji, viz tam)."""
    from diffusers import StableDiffusionXLControlNetPipeline as CN

    net = load_controlnet(kind)
    try:
        p = CN(**pipe.components, controlnet=net)
    except TypeError:
        p = CN.from_pipe(pipe, controlnet=net)     # jiny diffusers; radsi pomalu nez vubec
    # Slicing jen kdyz na UNetu NENI IP-Adapter. Ten si prepise attention procesory a
    # sliced varianta se pak postavi znovu bez slice_size — spadne to na
    # "SlicedAttnProcessor.__init__() missing 1 required positional argument". Totez resi
    # load_ip_adapter opacnym smerem; tady jde o poradi, kdy je adapter uz nactený driv.
    if not getattr(pipe.unet, "_td_ip_loaded", False):
        p.enable_attention_slicing()
    p.set_progress_bar_config(disable=True)
    return p


def generate(pipe, prompt, n, steps, seed, cfg=7.5, size=(1024, 1024), init=None,
             strength=0.6, ip_image=None):
    """N kandidatu. `size` je rozliseni RENDERU, ne velikost spritu.

    Ty dve veci se pletou snadno a plati se to sumem: sprite 32x32 vznika zmensenim
    renderu 1024x1024. Prevod cilove velikosti na render umí gen_ref.render_size — tady
    uz se ceka hotove cislo, aby matematika kolem pomeru stran byla na jednom miste.

    init != None prepne rouru na img2img a `strength` rekne, kolik z reference smi model
    prepsat (0.6 = zustane kompozice a zhruba postoj, zbytek je novy). Bez init se
    strength ignoruje — v text2img nema co znamenat.

    ip_image != None pridá referenci do cross-attention (IP-Adapter). Roura uz musi mit
    adapter nactený — viz load_ip_adapter(). Jde to i zaroven s init, ale pak uz na
    vysledek tlaci tri veci naráz a nedá se rict ktera; pro mereni delej jedno po druhem."""
    import torch
    w, h = _pair(size, (1024, 1024))
    full = f"{prompt}, {STYLE}"
    _warn_if_truncated(pipe, full, "prompt")
    _warn_if_truncated(pipe, NEGATIVE, "negativní prompt")
    if ip_image is None:
        unload_ip_adapter(pipe)
    runner, extra = pipe, {"width": w, "height": h}
    if init is not None:
        runner = _as_img2img(pipe)
        strength = float(min(1.0, max(0.05, strength)))
        im = init.convert("RGB")
        if im.size != (w, h):
            # NEAREST: predloha ma modelu ukazat pixelovou mrizku, vyhlazenim by se
            # prave ta informace ztratila.
            im = im.resize((w, h), Image.NEAREST)
        extra = {"image": im, "strength": strength}
        steps = _steps_for(steps, strength)
    # AZ TED, protoze vetev vys `extra` cely prepisuje — pridat to driv znamena tise
    # prijit o referenci prave v kombinaci init+ip.
    if ip_image is not None:
        extra["ip_adapter_image"] = ip_image
    imgs = []
    for i in range(n):
        g = torch.Generator("cuda").manual_seed(seed + i)
        img = runner(prompt=full, negative_prompt=NEGATIVE, num_inference_steps=steps,
                     guidance_scale=cfg, generator=g, **extra).images[0]
        imgs.append(img)
        print(f"  kandidát {i + 1}/{n}")
    return imgs


# ------------------------------------------------------------------ na sprite


def cut_background(img, tol=65):
    """Alfa zaplavou od obvodovych pixelu + chroma-key pojistka proti izolovanym flekum."""
    rgb = img.convert("RGB")
    mark = (1, 254, 1)                      # barva, kterou model prakticky nikdy netrefi
    d = ImageDraw.floodfill
    w, h = img.width, img.height
    
    # Obvodove seminka z celeho okraje
    seeds = ([(0, y) for y in range(0, h, 32)] + [(w - 1, y) for y in range(0, h, 32)] +
             [(x, 0) for x in range(0, w, 32)] + [(x, h - 1) for x in range(0, w, 32)] +
             [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)])
    
    for xy in seeds:
        try:
            d(rgb, xy, mark, thresh=tol)
        except Exception:
            pass
            
    a = np.array(rgb)
    bg = (np.abs(a.astype(int) - np.array(mark)).max(axis=-1) < 8)
    
    # Chroma-key fallback: jakykoli silne magentovy pixel
    raw_rgb = np.array(img.convert("RGB"))
    r, g, b = raw_rgb[..., 0].astype(int), raw_rgb[..., 1].astype(int), raw_rgb[..., 2].astype(int)
    is_magenta = (r > 150) & (g < 95) & (b > 150) & (np.abs(r - b) < 75)
    bg = bg | is_magenta
    
    out = np.dstack([raw_rgb, np.where(bg, 0, 255).astype(np.uint8)])
    return out


def crop_to_subject(a, pad=0.04, aspect=1.0):
    """Orez na postavu a doplneni na obalku v pomeru `aspect` (sirka/vyska).

    Bez tohohle sedi prisera uprostred 1024px platna jako mala skvrna a po zmenseni na
    32 px z ni zbyde deset pixelu.

    Pomer stran obalky musi sedet na CIL, ne byt vzdycky ctverec: dlazdice 16x8 orezana
    do ctverce by se pri zmenseni svisle zmackla na polovinu. Obalka se proto vzdycky
    ROZSIRUJE (nikdy neorezava obsah) — jinak by z prisery ubyla noha."""
    m = a[..., 3] > 32
    ys, xs = np.nonzero(m)
    if len(xs) == 0:
        return a
    aspect = float(aspect) if aspect and aspect > 0 else 1.0
    x0, x1 = int(xs.min()), int(xs.max())
    y0, y1 = int(ys.min()), int(ys.max())
    bw = int((x1 - x0 + 1) * (1.0 + pad * 2))
    bh = int((y1 - y0 + 1) * (1.0 + pad * 2))
    ow = max(bw, int(round(bh * aspect)))
    oh = max(bh, int(round(ow / aspect)))
    ow = max(ow, int(round(oh * aspect)))
    cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
    sx, sy = cx - ow // 2, cy - oh // 2

    # Prekryv obalky se zdrojem se kopiruje jednim slice. Puvodni verze slezla obalku
    # pixel po pixelu v Pythonu, coz je na 1024px renderu milion iteraci na obrazek —
    # nekolik sekund tam, kde numpy potrebuje milisekundy.
    out = np.zeros((oh, ow, 4), dtype=a.dtype)
    sx0, sy0 = max(0, sx), max(0, sy)
    sx1, sy1 = min(a.shape[1], sx + ow), min(a.shape[0], sy + oh)
    if sx1 > sx0 and sy1 > sy0:
        dx, dy = sx0 - sx, sy0 - sy
        out[dy:dy + (sy1 - sy0), dx:dx + (sx1 - sx0)] = a[sy0:sy1, sx0:sx1]
    return out


def downscale_median(a, size):
    """Zmenseni medianem po blocich. `size` je 32 nebo (16, 8).

    Prumer (a tim i BOX/BILINEAR) michá barvy sousednich oblasti, takze z ostre hrany
    udela prechod pres tri odstiny — presne to, co pak v artu meríme jako sum. Median
    vybere barvu, ktera v bloku prevlada, cimz hrana zustane hrana. Pruhledne pixely se
    do medianu nepocitaji, jinak by okraje ztmavly smerem k pozadi."""
    tw, th = _pair(size)
    h, w = a.shape[:2]
    out = np.zeros((th, tw, 4), dtype=np.uint8)
    ys = np.linspace(0, h, th + 1).astype(int)
    xs = np.linspace(0, w, tw + 1).astype(int)
    for j in range(th):
        for i in range(tw):
            blk = a[ys[j]:ys[j + 1], xs[i]:xs[i + 1]]
            if blk.size == 0:
                continue
            op = blk[blk[..., 3] > 32]
            # Blok je neprusvitny, jen kdyz je neprusvitna jeho vetsina — jinak by
            # kolem prisery zustal vencik polovicnich pixelu.
            if len(op) * 2 < blk.shape[0] * blk.shape[1]:
                continue
            out[j, i, :3] = np.median(op[:, :3], axis=0).astype(np.uint8)
            out[j, i, 3] = 255
    return out


def _dominant_color(rgb, k=2, iters=8):
    """k-means nad barvami jednoho bloku; vraci stred nejpocetnejsiho shluku.

    Pocatecni stredy jsou kvantily jasu, ne nahoda: u pixel-artoveho bloku je delici osa
    skoro vzdycky svetlo/tma (plocha proti obrysu), takze to konverguje za par iteraci a
    hlavne VZDYCKY STEJNE. Nahodna inicializace by znamenala, ze tentyz render da pokazde
    trochu jiny sprite, a pak uz se neda porovnavat ani seed, ani nastaveni."""
    px = rgb.astype(np.float32)
    if len(px) <= k:
        return px.mean(0).round().astype(np.uint8)
    lum = px @ np.array([0.299, 0.587, 0.114], dtype=np.float32)
    qs = np.quantile(lum, np.linspace(0.0, 1.0, k * 2 + 1)[1::2])
    cen = np.stack([px[np.argmin(np.abs(lum - q))] for q in qs]).astype(np.float32)
    lab = None
    for _ in range(iters):
        new = ((px[:, None, :] - cen[None, :, :]) ** 2).sum(2).argmin(1)
        if lab is not None and np.array_equal(new, lab):
            break                                    # ustalilo se, dal uz se nic nezmeni
        lab = new
        for c in range(k):
            m = lab == c
            if m.any():
                cen[c] = px[m].mean(0)
    return cen[np.bincount(lab, minlength=k).argmax()].round().astype(np.uint8)


def downscale_kcentroid(a, size, centroids=2):
    """Zmenseni k-centroidem: blok se shlukne na `centroids` barev a vyhraje nejpocetnejsi.

    Median resi kazdy kanal ZVLAST. Na bloku, kde se potkava zluta a fialova, muze proto
    vratit barvu, ktera v nem vubec nebyla — median R vezme ze zlute, median B z fialove a
    vyleze neco tretiho. Presne tohle dela z kontrastnich hran kalne pixely.

    K-centroid shlukuje cele RGB najednou a vrati stred toho shluku, ktery ma nejvic
    pixelu. Vysledna barva tedy vzdycky odpovida necemu, co model opravdu nakreslil, a
    mensina v bloku (antialiasing na hrane) vysledek neposune — prohraje hlasovani.

    Alfa se resi stejne jako u medianu, at jsou obe metody zamenitelne: pruhledne pixely
    se do shluku nepocitaji a blok je neprusvitny, jen kdyz je neprusvitna jeho vetsina."""
    tw, th = _pair(size)
    h, w = a.shape[:2]
    out = np.zeros((th, tw, 4), dtype=np.uint8)
    ys = np.linspace(0, h, th + 1).astype(int)
    xs = np.linspace(0, w, tw + 1).astype(int)
    for j in range(th):
        for i in range(tw):
            blk = a[ys[j]:ys[j + 1], xs[i]:xs[i + 1]]
            if blk.size == 0:
                continue
            op = blk[blk[..., 3] > 32]
            if len(op) * 2 < blk.shape[0] * blk.shape[1]:
                continue
            out[j, i, :3] = _dominant_color(op[:, :3], centroids)
            out[j, i, 3] = 255
    return out


DOWNSCALERS = {"median": downscale_median, "kcentroid": downscale_kcentroid}

# CO TENHLE PREPINAC POKRYVA A CO NE — nesjednocovat, je to schvalne.
#
# downscale() resi JEDINOU ulohu: render (1024 px) -> sprite, tedy desitky zdrojovych
# pixelu na jeden vysledny. Tam se o barve rozhoduje HLASOVANIM a zalezi, jakym.
#
# Jinde v projektu se zmensuje taky, ale je to jina uloha a NEAREST/BOX je tam spravne:
#   sprite_16.halve()          64 -> 32, presne 2x z UZ CISTEHO pixel artu + snap palety
#   install_local.na_platno()  orez a vycentrovani na platno; pixely neprepocitava vubec
#   raster_to_24.zmensi()      jednorazova migrace 64 -> 48 (NEAREST x0.75)
#
# Poslat je pres downscale() by je zhorsilo: median z bloku 2x2 ciste kresby zahodi prave
# tu ostrost, kvuli ktere je ta kresba ciste. Mereni v data.gd to rika cislem — retez
# NEAREST -> clean(24) -> outline dal na 111 spritech znamku 9,00.
#
# --downscale tedy NENI projektove nastaveni. Plati pro generovani, ne pro instalaci.

# Zmensovani je nastaveni BEHU, ne parametr jednotlivych volani. Duvod je v docstringu
# refine(): kdyby generovani a nasledne doladeni zmensovalo jinak, "doladil jsem to" by
# znamenalo "vypada to jinak, protoze se to jinak zmensilo". Parametr protazeny sesti
# funkcemi se da predat nekonzistentne; jedno nastaveni se nekonzistentne predat neda.
DOWNSCALE = "median"


def downscale(a, size, how=None):
    """Jedine misto, kde se rozhoduje, cim se zmensuje. `how=None` znamena DOWNSCALE."""
    fn = DOWNSCALERS.get(how or DOWNSCALE)
    if fn is None:
        raise ValueError(f"nezname zmensovani {how or DOWNSCALE!r}; "
                         f"znam {', '.join(DOWNSCALERS)}")
    return fn(a, size)


def strip_shadow(a, band=0.18):
    """Odstrani sedou/fialovou zapecenou zem pod nohama."""
    m = a[..., 3] > 32
    if not m.any():
        return a
    ys = np.nonzero(m)[0]
    y0 = int(ys.max() - (ys.max() - ys.min()) * band)
    rgb = a[..., :3].astype(float)
    lum = rgb @ [0.299, 0.587, 0.114]
    mx, mn = rgb.max(2), rgb.min(2)
    sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1), 0)
    kill = np.zeros_like(m)
    kill[y0:] = m[y0:] & ((sat[y0:] < 0.35) | (lum[y0:] < lum[m].mean() * 0.70))
    a = a.copy()
    a[..., 3][kill] = 0
    return a


def outline_sprite(a, strength=0.35):
    """Prida 1px tmavy prstenec kolem siluety — zvyrazni tvar a plastičnost.

    Ztmavuje se v Oklab, ne nasobenim RGB. Puvodni verze delala mean(RGB)*strength a pak
    clip(8, 70) po kanalech, coz u sytych barev MENI ODSTIN: (255,180,60)*0.35 dá
    (89,63,21), ale strop 70 srazi jen cerveny kanal a z teple oranzove se stane
    hnedosediva. style_bible.md:33 pritom chce "tmavsi odstin TEZE barvy, ne cerna".

    Oklch to resi primo: snizi se L, odstin h zustane. Chroma se ale MUSI snizit taky —
    tmava barva s plnou sytosti lezi mimo sRGB a prevod ji na okraji gamutu stoci. Zmereno
    na peti barvach (posun odstinu ve stupnich, cim min tim lip):

        barva        puvodni   jen L   C*0.6   C*0.45   C*0.3
        oranzova        23.9    39.0    16.0      6.0     0.2
        zluta            3.2    17.5     5.3      1.4     0.1
        azurova          8.0    12.1     2.5      1.5     0.9

    C*0.45 porazi puvodni verzi u vsech a jeste nechá obrysu barvu; C*0.3 je presnejsi,
    ale uz sedne do seda, coz je prave to, cemu se stylova bible brani."""
    from scipy.ndimage import binary_dilation
    from palette_morph import from_oklch, to_oklch
    m = a[..., 3] > 32
    if not m.any():
        return a
    ring = binary_dilation(m) & ~m
    base = a[..., :3][m].astype(np.float64).mean(0)
    lch = to_oklch(base.reshape(1, 3))
    lch[..., 0] = np.clip(lch[..., 0] * strength, 0.06, 0.32)   # tytez meze, ale ve svetlosti
    lch[..., 1] *= 0.45                                          # drzi odstin v gamutu
    dark = from_oklch(lch).reshape(3)
    out = a.copy()
    out[..., :3][ring] = dark
    out[..., 3][ring] = 255
    return out


def to_sprite(img, size=32, colors=20, palette=None):
    """Render -> hotovy sprite w×h s orezem, odstranenim stinu a 1px obrysem."""
    tw, th = _pair(size)
    a = cut_background(img) if isinstance(img, Image.Image) else np.asarray(img)
    a = strip_shadow(a)
    a = crop_to_subject(a, aspect=tw / float(th))
    a = downscale(a, (tw, th))
    a = outline_sprite(a)
    if palette is not None and len(palette):
        a = gen_ref.apply_palette(a, palette)
    return clean(a, colors)


def clean(a, colors=16):
    """Paleta a sum — tytez funkce, ktere cistí PixelLabu (sprite_cleanup.py)."""
    from collections import Counter
    m = a[..., 3] > 32
    if not m.any():
        return a
    pool = Counter(map(tuple, a[..., :3][m]))
    pal = build_palette(pool, colors, 0.5)
    pal_lab = to_oklab(pal)
    rgb = remap(a[..., :3].astype(np.int64), m, pal, pal_lab)
    lab_of = {tuple(c): l for c, l in zip(map(tuple, pal), pal_lab)}
    rgb, _, _ = despeckle(rgb, m, lab_of, 5, 0.12)
    return np.dstack([rgb.astype(np.uint8), a[..., 3]])


# ------------------------------------------------------------------ iterace a animace
#
# ITERACE JE RODOKMEN. Jedno spusteni generatoru da sest RUZNYCH priser a ty si z nich
# jednu vybereš. Tim to ale konci — dalsi spusteni s upravenym promptem vyrobi zase sest
# uplne jinych. Iterace je opak: vezme HOTOVY sprite jako vychozi obrazek a prekresli na
# nem jen tolik, kolik dovoli strength. Vznikne DITE, ne cizi prisera.
#
# Vsechno tady proto pracuje s dvojici rodic -> dite a kazdy krok si pamatuje, z ceho
# vznikl (meta.json ve slozce). Bez toho by po peti iteracich byla ve slozce hromada
# spritu, o kterych nikdo nevi, ze spolu souvisi, a nedalo by se vratit o krok zpatky.
#
# PROC SAMOTNA ITERACE NESTACI. Difuze je nahodny proces, takze kazdy pruchod barvy trochu
# posune — model si pokazde vybere vlastni odstin. Po trech krocich uz to neni tataz
# prisera, jen podobna, i kdyz kazdy jednotlivy krok vypadal jako drobna uprava. Proti tomu
# jsou ZAMKY: lock_palette prebarvi dite na paletu rodice, lock_silhouette mu vnuti i
# rodicuv obrys. Zamky delaji z iterace ladeni misto driftu.
#
# ANIMACE stoji na tomtez: vsechny framy vznikaji z JEDNOHO zakladu, lisi se jen pose
# promptem a maji nizkou strength. Konzistence tedy neni vysledek stesti, ale konstrukce.

# Poza na FRAME, ne popis animace. Model neumi nakreslit "cyklus chuze", umi nakreslit
# jednu pozu; cyklus vznikne az tim, ze pozy jdou za sebou. Ctyri fáze proto, ze na nich
# stoji klasicky walk cycle (kontakt, prochod, kontakt, prochod) a kazdy frame navic je
# dalsi minuta generovani i dalsi sance na odchylku. Kdyz ctyri nestaci, --poses vezme
# vlastni seznam libovolne delky.
WALK_POSES = [
    "walking, left leg forward and right leg back, arms swinging",
    "walking, legs together passing under the body, body lifted slightly higher",
    "walking, right leg forward and left leg back, arms swinging the other way",
    "walking, legs together passing under the body, body dipped slightly lower",
]

# Idle se nesmi hybat skoro vubec — na 32px spritu je "nadechnuti" jeden pixel. Proto
# vsechny ctyri pozy popisuji TOTEZ stani, jen s jinym dechem.
IDLE_POSES = [
    "standing still, relaxed, arms hanging down",
    "standing still, breathing in, body stretched a little taller",
    "standing still, relaxed, arms hanging down",
    "standing still, breathing out, body squashed a little shorter",
]

POSES = {"walk": WALK_POSES, "idle": IDLE_POSES}


def build_img2img(pipe):
    """Img2img roura ze STEJNYCH vah, ktere uz drzi textova roura.

    Sdili moduly (UNet, VAE, oba text encodery i nactenou LoRu) misto toho, aby se model
    nacetl podruhe — jinak by prvni doladeni stalo dalsich 7 GB VRAM a pul minuty cekani,
    a to na karte, kde uz jedna kopie modelu sedi."""
    from diffusers import StableDiffusionXLImg2ImgPipeline as I2I

    # POZOR NA from_pipe. Vypada jako spravna moderni cesta a je to past: pri nem VRAM
    # skoci ze 7,3 na 12,0 GB, tedy na 97 % karty — a od te chvile ovladac preleva misto
    # aby se pocitalo. Zmereno 18. 8. 2026 na 4070 SUPER, 512 px, 12 kroku:
    #
    #     I2I(**pipe.components)    7318 MiB    1,7 s
    #     I2I.from_pipe(pipe)      11986 MiB   52,0 s     <- 31x pomaleji
    #
    # Moduly jsou v obou pripadech TYTEZ objekty (unet, vae i oba enkodery), takze to
    # neni druha kopie vah — from_pipe si vynuti pretypovani a tim naalokuje UNet znovu.
    # empty_cache() to nevrati, je to ziva alokace.
    #
    # Tim padem bylo pomale VSECHNO, co jde pres img2img: rotate, refine, animate, --from.
    # Text2img byl cely cas rychly, proto to tak dlouho nikoho netrklo.
    try:
        p = I2I(**pipe.components)
    except TypeError:
        # Jina sada komponent (jiny diffusers) — radsi pomalu nez vubec.
        p = I2I.from_pipe(pipe)
    p.enable_attention_slicing()
    p.set_progress_bar_config(disable=True)
    return p


def build_inpaint(pipe):
    """Inpaint roura ze STEJNYCH vah jako textova/img2img roura.

    Pouziva AutoPipelineForInpainting.from_pipe — sdili moduly, takze zadna dalsi
    VRAM. Na rozdil od dedikovaneho inpaint checkpointu (stable-diffusion-xl-1.0-
    inpainting-0.1) tady neni trenovana vrstva na masku, takze okraje masky budou
    o neco mene presne. Pro pixel-art sprity, kde maska pokryva cele casti tela
    (hlava, ruka, zbran), je to ale vic nez dostatecne — a nestahuje se 6.5 GB navic."""
    from diffusers import AutoPipelineForInpainting
    p = AutoPipelineForInpainting.from_pipe(pipe)
    p.enable_attention_slicing()
    p.set_progress_bar_config(disable=True)
    return p


def inpaint(pipe_inpaint, base_rgba, mask_bool, prompt, strength=0.75, steps=28,
            seed=1, size=32, colors=16):
    """Pregeneruj JEN maskovanou oblast spritu, zbytek zustane na pixel presne stejny.

    mask_bool je 2D boolean pole (H, W) ve velikosti spritu — True = pregenerovat.

    Princip:
    1. Sprite se zvětší na render rozlišení (1024 px) přes sprite_to_init.
    2. Maska se zvětší na totéž rozlišení (NEAREST — maska nesmí být vyhlazená).
    3. Inpaint pipeline přegeneruje maskovanou oblast podle nového promptu.
    4. Výsledek projde stejnou cestou jako generate (cut_bg → crop → downscale → clean).
    5. Na závěr se na pixel přesně vrátí nemaskované pixely z originálu.

    Krok 5 je nejdůležitější: difuze může trochu pohnout i "chráněnými" pixely
    (artefakt netrénované inpaint hlavy), takže explicitní kopie originálu je
    pojistka — zbytek spritu se NEMŮŽE změnit, protože ho bereme ze souboru, ne
    z modelu."""
    import torch

    tw, th = _pair(size)
    rw, rh = gen_ref.render_size(tw, th)
    strength = float(min(1.0, max(0.05, strength)))
    steps = _steps_for(steps, strength)

    # Zvětšení spritu na render rozlišení
    init_img = sprite_to_init(base_rgba, (rw, rh))

    # Zvětšení masky na render rozlišení — NEAREST, at zustane binární
    mask_u8 = (mask_bool.astype(np.uint8) * 255)
    mask_pil = Image.fromarray(mask_u8, "L").resize((rw, rh), Image.NEAREST)

    # Inpaint: bílá = přegenerovat, černá = zachovat
    g = torch.Generator("cuda").manual_seed(seed)
    full = f"{prompt}, {STYLE}"
    _warn_if_truncated(pipe_inpaint, full, "inpaint prompt")
    result = pipe_inpaint(
        prompt=full,
        negative_prompt=NEGATIVE,
        image=init_img,
        mask_image=mask_pil,
        strength=strength,
        num_inference_steps=steps,
        guidance_scale=7.5,
        generator=g,
    ).images[0]

    # Standardní sprite pipeline
    a = cut_background(result)
    a = strip_shadow(a)
    a = crop_to_subject(a, aspect=tw / float(th))
    a = downscale(a, (tw, th))

    # POJISTKA: nemaskované pixely se berou z originálu, ne z modelu.
    # Maska se zmenší na velikost spritu (NEAREST) pro přesný pixelový composit.
    mask_small = np.array(
        Image.fromarray(mask_u8, "L").resize((tw, th), Image.NEAREST)
    ) > 128
    orig = base_rgba
    if orig.shape[:2] != (th, tw):
        orig = np.array(Image.fromarray(orig, "RGBA").resize((tw, th), Image.NEAREST))
    # Tam kde maska je False (neoznačené), vrať pixely originálu na pixel přesně
    for c in range(4):
        a[..., c] = np.where(mask_small, a[..., c], orig[..., c])

    return clean(a, colors)

def sprite_to_init(a, size=1024, margin=0.08):
    """Hotovy sprite -> vstupni obrazek pro img2img: NEAREST zvetseni na magentovem ctverci.

    NEAREST a ne bilinearni je tady to podstatne rozhodnuti. Difuze prekresluje to, co
    VIDI; kdyz dostane vyhlazenou predlohu, vrati vyhlazenou kresbu a pixel-art charakter
    je pryc uz po prvni iteraci. Tvrde ctverce naopak model precte jako styl a drzi se ho.

    Zvetsuje se CELOCISELNYM nasobkem a zbytek do ctverce se doplni pozadim. Nasobek 21.33
    by ctyri pixely delal siroke 21 a paty 22, takze i pri NEAREST by mrizka prestala byt
    pravidelna — presne v tom, co ma model precist jako styl.

    Magenta proto, ze presne tu si STYLE vynucuje jako pozadi, takze ji na vystupu zase
    odstrani cut_background touz cestou jako u generovani. Okraj kolem spritu tam je kvuli
    zaplave od rohu: sprite dotykajici se rohu by si nechal vykousnout nohu.

    `size` je 1024 nebo (1024, 512) — plati totez co u generate: je to rozliseni RENDERU."""
    src = np.asarray(a)
    h, w = src.shape[:2]
    if h == 0 or w == 0:
        raise ValueError("prázdná předloha")
    W, H = _pair(size, (1024, 1024))

    # Alfa se sklada na magentu rucne, ne pastou pres masku: poloprusvitne okraje by jinak
    # zustaly poloprusvitne a model by dostal predlohu s mekkym lemem, kteremu se vyhybame.
    al = src[..., 3:4].astype(np.float64) / 255.0
    rgb = src[..., :3].astype(np.float64) * al + np.array(MAGENTA, float) * (1.0 - al)
    im = Image.fromarray(rgb.round().astype(np.uint8), "RGB")

    zoom = min(int(W * (1.0 - margin * 2)) // w, int(H * (1.0 - margin * 2)) // h)
    if zoom < 1:                          # predloha vetsi nez cil — neni co zvetsovat
        return im.resize((W, H), Image.NEAREST)
    im = im.resize((w * zoom, h * zoom), Image.NEAREST)
    out = Image.new("RGB", (W, H), MAGENTA)
    out.paste(im, ((W - im.width) // 2, (H - im.height) // 2))
    return out


def lock_to_palette(a, parent_rgba, colors=16):
    """Prebarvi dite paletou RODICE.

    Bez tohohle kazda iterace barvy trochu posune — model si pokazde zvoli vlastni odstin
    modre — a po tretim kroku mas jinou priseru, i kdyz kazdy jednotlivy krok vypadal jako
    drobna uprava. Paleta se pocita jen z rodice, ne ze smesi obou, aby drift nemel kudy
    vlezt; a pocita se tymiz funkcemi, kterymi ji pocita sprite_cleanup."""
    from collections import Counter
    pm = parent_rgba[..., 3] > 32
    m = a[..., 3] > 32
    if not pm.any() or not m.any():
        return a
    pal = build_palette(Counter(map(tuple, parent_rgba[..., :3][pm])), colors, 0.5)
    rgb = remap(a[..., :3].astype(np.int64), m, pal, to_oklab(pal))
    return np.dstack([rgb.astype(np.uint8), a[..., 3]])


def lock_to_silhouette(a, parent_rgba):
    """Tvrdsi zamek: silueta se prevezme od rodice, meni se jen povrch.

    Pixely, ktere rodic ma a dite ne, nemaji zadnou barvu — downscale_median necha
    pruhledny blok nulovy, takze prosté prilepeni rodicovy alfy by kolem prisery udelalo
    cerny lem. Dotahnou se proto dilataci od sousedu, a to barvou DITETE: obrys je
    rodicuv, ale povrch je to jedine, co se v tomhle rezimu smi menit."""
    from collections import Counter
    pa = parent_rgba[..., 3]
    if pa.shape != a.shape[:2]:
        pa = np.array(Image.fromarray(pa.astype(np.uint8), "L").resize(
            (a.shape[1], a.shape[0]), Image.NEAREST))
    rgb = a[..., :3].copy()
    have = a[..., 3] > 32
    need = (pa > 32) & ~have
    h, w = rgb.shape[:2]
    for _ in range(8):                       # osm dilataci staci i na tlustsiho rodice
        todo = list(zip(*np.nonzero(need)))
        if not todo:
            break
        moved = False
        for y, x in todo:
            neigh = Counter()
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    yy, xx = y + dy, x + dx
                    if 0 <= yy < h and 0 <= xx < w and have[yy, xx]:
                        neigh[tuple(rgb[yy, xx])] += 1
            if neigh:
                rgb[y, x] = neigh.most_common(1)[0][0]
                have[y, x] = True
                need[y, x] = False
                moved = True
        if not moved:
            break
    return np.dstack([rgb.astype(np.uint8), pa.astype(np.uint8)])


def _i2i_sprite(pipe_i2i, init, prompt, strength, steps, seed, size, cfg=7.5):
    """Jeden pruchod img2img a tataz cesta na sprite jako u generate, jeste BEZ palety.

    Paleta zamerne az venku: refine ji zamyká na rodice, animate na celou sadu framu. Kdyby
    ji delala uz tahle funkce, animate by kvantoval dvakrat — nejdriv po framech a pak
    spolecne — a to je horsi, nez to zni: kazdy frame si vlastni kvantizaci vybere trochu
    jiny odstin tela, spolecna paleta pak vidi dva odstiny misto jednoho a nechá oba. Tedy
    presne to blikani, kvuli kteremu spolecna paleta existuje."""
    import torch
    tw, th = _pair(size)
    strength = float(min(1.0, max(0.05, strength)))
    steps = _steps_for(steps, strength)
    g = torch.Generator("cuda").manual_seed(seed)
    img = pipe_i2i(prompt=f"{prompt}, {STYLE}", negative_prompt=NEGATIVE, image=init,
                   strength=strength, num_inference_steps=steps, guidance_scale=cfg,
                   generator=g).images[0]
    a = cut_background(img)
    a = crop_to_subject(a, aspect=tw / float(th))
    return downscale(a, (tw, th))


def refine(pipe_i2i, base_rgba, prompt, strength=0.35, steps=28, seed=1,
           size=32, colors=16, lock_palette=True, lock_silhouette=False):
    """Z hotoveho spritu udelej jeho DITE: tataz prisera, jinak nakreslena.

    strength rika, kolik z rodice smi model prepsat: 0.2 posune detail, 0.5 uz je jina
    prisera. Skutecny pocet kroku je steps*strength, takze slaba iterace je i rychla.

    Vystup jde TOUTEZ cestou jako generate (cut_background -> crop_to_subject ->
    downscale_median -> clean). Kdyby mela iterace vlastni zmensovani, rozesla by se prvni
    generace s druhou a "doladil jsem to" by znamenalo "vypada to jinak, protoze se to
    jinak zmensilo".

    Poradi zamku a cistky neni libovolne: lock_to_palette bezi PRED clean. Po nem ma sprite
    nejvyse `colors` barev, takze build_palette uvnitr clean je vrati beze zmeny a jeho
    remap je identita — ale despeckle porad probehne, a to uz na finalnich barvach. Opacne
    poradi by sum vycistilo a hned nato barvy premlelo znovu, cimz by cast sumu vznikla
    zpatky."""
    a = _i2i_sprite(pipe_i2i, sprite_to_init(base_rgba, gen_ref.render_size(*_pair(size))),
                    prompt, strength, steps, seed, size)
    if lock_silhouette:
        a = lock_to_silhouette(a, base_rgba)
    if lock_palette:
        a = lock_to_palette(a, base_rgba, colors)
    return clean(a, colors)


def unify_palette(frames, colors=16):
    """Jedna paleta pres vsechny framy animace.

    Tataz oprava, kterou dela sprite_cleanup na hotovem artu, jen o krok driv: barva,
    ktera v jednom framu je a v druhem ne, se ve hre projevi jako varici se povrch. Kdyz
    vsechny framy sdileji paletu, blikani nema z ceho vzniknout.

    Despeckle az tady, a ne po jednotlivych framech: potrebuje lab_of te SPOLECNE palety,
    aby "kontrastni detail" znamenalo totez ve vsech framech. Jinak by oko v jednom framu
    prezilo a ve druhem se vsáklo do tvare — a to je zase blikani."""
    from collections import Counter
    pool = Counter()
    for a in frames:
        for c in map(tuple, a[..., :3][a[..., 3] > 32]):
            pool[c] += 1
    if not pool:
        return [a.copy() for a in frames]
    pal = build_palette(pool, colors, 0.5)
    pal_lab = to_oklab(pal)
    lab_of = {tuple(c): l for c, l in zip(map(tuple, pal), pal_lab)}
    out = []
    for a in frames:
        m = a[..., 3] > 32
        rgb = remap(a[..., :3].astype(np.int64), m, pal, pal_lab)
        rgb, _, _ = despeckle(rgb, m, lab_of, 5, 0.12)
        out.append(np.dstack([rgb.astype(np.uint8), a[..., 3]]))
    return out


def frame_anchor(a):
    """(teziste X, spodni hrana) siluety — dva body, proti kterym se frame zarovnava.

    Presne tyhle dve miry pocita i addons/td_anim_lab: teziste odhali ujizdeni do strany,
    spodni hrana poskakovani."""
    m = a[..., 3] > 32
    ys, xs = np.nonzero(m)
    if len(xs) == 0:
        return None
    return float(xs.mean()), int(ys.max())


def shift_frame(a, dx, dy):
    """Posun o cele pixely s doplnenim PRUHLEDNOSTI.

    np.roll sam o sobe wrapuje: noha, ktera vyjede vlevo, vleze zpatky zprava a v animaci
    problikne u opacneho okraje. Zarolovany pruh se proto vynuluje — nula je v RGBA
    (0,0,0,0), tedy pruhledno."""
    h, w = a.shape[:2]
    if abs(dx) >= w or abs(dy) >= h:
        return np.zeros_like(a)          # cely obsah by stejne vyjel z platna
    out = np.roll(np.roll(a, dy, axis=0), dx, axis=1)
    if dy > 0:
        out[:dy] = 0
    elif dy < 0:
        out[dy:] = 0
    if dx > 0:
        out[:, :dx] = 0
    elif dx < 0:
        out[:, dx:] = 0
    return out


def align_frames(frames):
    """Zarovnani framu na median — tataz matematika jako "Srovnat nohy" a "Srovnat střed"
    v Animation Labu, jen davkove a rovnou pri vzniku.

    Kazdy frame vznikl vlastnim orezem na vlastni obalku, takze prisera, ktera pri chuzi
    rozpazi, je v tom framu sirsi a cely sprite se orezem posune. Ve hre to vypada, ze
    prisera ujizdi do strany a poskakuje, i kdyz je kazdy frame sam o sobe v poradku.

    Median a ne prvni frame proto, ze prave prvni frame muze byt ten ukroceny — pak by se
    podle nej srovnalo spatne vsechno ostatni.

    Obe reference berou DOLNI median, tedy hodnotu NEKTEREHO z framu, ne prumer dvou
    prostrednich (to dela np.median u sude sady). Duvod je zaokrouhlovani: posouva se o
    cele pixely, takze pri referenci na x.5 vyjde pulka posunu na +0.5 a pulka na -0.5 — a
    Python zaokrouhluje .5 k sudemu cislu, takze cast framu skonci o pixel vedle druhe.
    Reference, kterou nektery frame trefuje presne, tuhle past nema: sada, ktera se lisi
    jen posunutim, se pak srovna na nulovy rozptyl. Tataz uvaha je v td_anim_lab (base_ref).

    Prazdne framy se do medianu nepocitaji a nehybe se s nimi — jejich nulova spodni hrana
    neni misto, kde prisera stoji."""
    anchors = [frame_anchor(a) for a in frames]
    good = [t for t in anchors if t is not None]
    if not good:
        return [a.copy() for a in frames]
    mid = len(good) // 2
    mcx = sorted(c for c, _ in good)[mid]
    mbase = sorted(b for _, b in good)[mid]
    out = []
    for a, t in zip(frames, anchors):
        if t is None:
            out.append(a.copy())
            continue
        out.append(shift_frame(a, int(round(mcx - t[0])), int(mbase - t[1])))
    return out


def animate(pipe_i2i, base_rgba, pose_prompts, strength=0.3, steps=28, seed=1,
            size=32, colors=16, on_frame=None):
    """Framy animace z JEDNOHO zakladu, kazdy s vlastni pozou.

    Konzistence tim neni odhad ani stesti, ale konstrukce: vsechny framy maji stejneho
    rodice a stejne nizkou silu, takze se od sebe nemuzou lisit vic, nez kolik ta sila
    dovoli. Generovat framy nezavisle (osmkrat text2img) vyrobi osm ruznych priser —
    presne ten "zprzeny" vzhled, ktery uz pak nikdo nedozarovna.

    Stejny seed pro vsechny framy, a to schvalne. Pri img2img urcuje seed sum primichany
    do predlohy, takze stejny seed znamena, ze se framy lisi JEN pozou. Seed po framech by
    pridal jeste nahodnou variaci povrchu — presne to kmitani, ktere pak sprite_cleanup
    meri jako blikajici pixely.

    pose_prompts jsou HOTOVE prompty, ne pripony. Slozit "<prisera>, <poza>" umi jen
    volajici — jen on vi, jestli ma popis prisery stat pred pozou nebo za ni.

    Palety se tady nezamykaji na rodice, protoze framy dostanou spolecnou paletu az
    nakonec: zamek na rodice by kazdy frame tahl jinam nez ostatni."""
    init = sprite_to_init(base_rgba, gen_ref.render_size(*_pair(size)))
    frames = []
    for i, pose in enumerate(pose_prompts):
        frames.append(_i2i_sprite(pipe_i2i, init, pose, strength, steps, seed, size))
        if on_frame:
            on_frame(i + 1, len(pose_prompts))
    return align_frames(unify_palette(frames, colors))


# ------------------------------------------------------------------ otoceni
#
# OSM SMERU Z JEDNOHO ZAKLADU. Konstrukce je tataz jako u animace a ze stejneho duvodu:
# kazdy smer je img2img z TEHOZ rodice, takze se od sebe nemuzou lisit vic, nez dovoli
# strength. Osm nezavislych text2img by dalo osm ruznych priser — ve hre by se pri
# otoceni prisera premenila v jinou.
#
# Strength je tu vyssi nez u animace (0.45 proti 0.3), a to je jedine spravne cislo, ktere
# se lisi: poza se meni o par pixelu, pohled se meni cely. Pod ~0.35 model predlohu jen
# prekresli a "pohled zezadu" ignoruje — vyleze osmkrat totez zepredu.
#
# FORMULACE POHLEDU. Na nich stoji, jestli to bude tentyz tvor otoceny, nebo osm ruznych
# tvoru. Zvolene formulace a proc prave ony:
#
#   * "seen from behind", ne "rear view" ani "back of the character". Popisky obrazku,
#     na kterych se model ucil, tuhle vazbu pouzivaji na OSOBU (a picture of X seen from
#     behind), takze otoci subjekt. "Rear view" je slovnik z fotek aut a nabytku a model
#     podle nej kresli zada jako novy predmet.
#   * "three-quarter view", ne "45 degrees" ani "isometric". Uhel ve stupnich model
#     nedodrzuje (neni to nic, co by v popiscich bylo), kdezto tri ctvrte je bezny termin
#     ze sprite sheetu a herniho artu. "Isometric" navic tahne k celym scenam s dlazdicemi.
#   * Smer se vaze na OBRAZOVKU ("facing screen right"), ne na telo prisery. "Facing left"
#     bez upresneni si model vylozi jednou jako jeji levou ruku a podruhe jako levou stranu
#     obrazku, takze pulka sady vyjde zrcadlove.
#   * Zavrzeno: "turnaround sheet", "character rotation sheet". Zni to presne na tuhle
#     ulohu, ale model podle toho nakresli VIC POSTAV do jednoho obrazku — presne to, co
#     NEGATIVE cely cas potlacuje, a cut_background by z toho udelal jednu slepenou skvrnu.
#   * Zavrzeno: zrcadlit east -> west misto generovani. Je to zadarmo a konzistentni, ale
#     prevraci i to, co prevratit nema (napis na plechovce, obvaz na jedne ruce), takze
#     zapadni pulka sady cte jako jina prisera. Kdyz to nekomu vadi mene nez cas, staci
#     dat rotate() jen ctyri smery pres `dirs` a zbytek zrcadlit venku.

# Poradi neni nahodne: krok mezi sousedy je 45 stupnu, takze index v seznamu je uhel
# (index * 45) a smery jdou pocitat modulo 8.
DIRECTIONS = ["south", "south-east", "east", "north-east",
              "north", "north-west", "west", "south-west"]

# Popis pohledu, ktery se prilepi k promptu prisery. Slozeni "<prisera>, <pohled>" dela
# rotate sam — na rozdil od animate, kde jsou pozy hotove prompty: pohled je vlastnost
# smeru, ne volajiciho, a osm ruznych formulaci by kazdy volajici napsal jinak.
DIR_VIEWS = {
    "south": "front view, facing the viewer",
    "south-east": "three-quarter front view, turned toward the lower right of the screen",
    "east": "side view, facing screen right, profile of the whole body",
    "north-east": "three-quarter view seen from behind, turned toward the upper right "
                  "of the screen",
    "north": "seen from behind, back turned to the viewer, face not visible",
    "north-west": "three-quarter view seen from behind, turned toward the upper left "
                  "of the screen",
    "west": "side view, facing screen left, profile of the whole body",
    "south-west": "three-quarter front view, turned toward the lower left of the screen",
}


def _progress(cb, i, n, label):
    """Ohlaseni postupu callbacku, ktery smi brat (i, n) i (i, n, label).

    Arity on_dir kontrakt neurcuje a volajici klidne posle tutez lambdu, jakou dava do
    animate. Rozhodnout se podle podpisu je jistejsi nez zavolat a chytit TypeError: ten
    by mohl prijit i zevnitr callbacku a tise by se snedl — presne tak umira tlacitko,
    o kterem si pak vsichni mysli, ze funguje."""
    if cb is None:
        return
    import inspect
    try:
        ps = list(inspect.signature(cb).parameters.values())
        wants = 3 if any(p.kind == p.VAR_POSITIONAL for p in ps) else sum(
            1 for p in ps if p.kind in (p.POSITIONAL_ONLY, p.POSITIONAL_OR_KEYWORD))
    except (TypeError, ValueError):
        wants = 3
    cb(i, n, label) if wants >= 3 else cb(i, n)


def rotate(pipe_i2i, base_rgba, prompt, dirs=None, strength=0.45, steps=28, seed=1,
           size=32, colors=16, on_dir=None):
    """Osm smeru z JEDNOHO zakladu -> {"south": pole RGBA, ...}.

    Vraci slovnik, ne seznam: u animace poradi JE ta vec (cyklus), u smeru je poradi jen
    dohoda a volajici potrebuje vedet, ktery obrazek je sever — jmeno smeru konci v nazvu
    souboru (<id>_north_frame_1.png).

    Stejny seed pro vsechny smery, stejne jako u animate: pri img2img urcuje seed sum
    primichany do predlohy, takze shodny seed znamena, ze se smery lisi JEN pohledem.

    Na konci projdou vsechny smery unify_palette a align_frames. Spolecna paleta proto,
    aby prisera pri otoceni nezmenila odstin tela; zarovnani proto, ze kazdy smer ma
    vlastni obrys a tim i vlastni orez — bez nej se prisera pri otoceni propadne nebo
    poskoci do strany. Presne tohle art_check hlasi jako 'pohled_jinde'."""
    dirs = [d for d in (dirs or DIRECTIONS)]
    unload_ip_adapter(pipe_i2i)          # rotate() je varianta BEZ adapteru, viz rotate_ip
    init = sprite_to_init(base_rgba, gen_ref.render_size(*_pair(size)))
    frames = []
    for i, d in enumerate(dirs):
        # Neznamy smer neni chyba: volajici smi poslat vlastni popis pohledu jako klic.
        view = DIR_VIEWS.get(d, d)
        frames.append(_i2i_sprite(pipe_i2i, init, f"{prompt}, {view}",
                                  strength, steps, seed, size))
        _progress(on_dir, i + 1, len(dirs), d)
    frames = align_frames(unify_palette(frames, colors))
    return dict(zip(dirs, frames))


def rotate_ip(pipe, base_rgba, prompt, dirs=None, strength=0.50, steps=28, seed=1,
              size=32, colors=16, ip_scale=0.7, on_dir=None):
    """Osm smeru s IP-Adapterem pro drzeni identity.

    Rozdil proti rotate(): IP-Adapter prida jizni pohled do cross-attention, takze
    model po celou dobu VIDI barvy, texturu a doplnky originálu. Text urcuje JEN
    smer pohledu, identitu drzi obraz. Vysledek je jedna prisera otocena, ne osm
    ruznych priser se stejnym promptem.

    strength je vyssi nez u bezneho rotate (0.50 vs 0.45), protoze IP-Adapter drzi
    identitu nezavisle na strength — model smi vic menit kompozici (otocit postavu),
    aniz by ztratil, kdo to je. Bez IP-Adapteru vyssi strength znamena vic zmeny
    A vic ztraty identity; s nim je to rozdelene na dve nezavisle osy.

    ip_scale 0.7 je vyssi nez pri generovani z nuly (0.6), protoze pri rotaci je
    zachovani identity dulezitejsi nez kreativni volnost — jde o tutez priseru z
    jineho uhlu, ne o novou priseru se stejnym stylem."""
    import torch

    dirs = [d for d in (dirs or DIRECTIONS)]
    # PORADI JE PODSTATNE. Rouru postavit driv, adapter nasadit az na ni.
    #
    # build_img2img sklada rouru z pipe.components (viz tam, proc ne pres from_pipe) a ta
    # cesta stav IP-Adapteru NEPRENESE — image_encoder a feature_extractor by chybely a
    # spadlo by to az uvnitr attention na "'tuple' object has no attribute 'shape'", tedy
    # v miste, kde uz nikoho nenapadne hledat pricinu o dve funkce vys.
    #
    # UNet je u obou rour tentyz objekt, takze navesenim adapteru na img2img rouru se
    # procesory stejne propisou i do te textove. Nic se tim neztraci.
    pipe_i2i = build_img2img(pipe)
    pipe_i2i = load_ip_adapter(pipe_i2i, scale=ip_scale)

    tw, th = _pair(size)
    rw, rh = gen_ref.render_size(tw, th)
    init = sprite_to_init(base_rgba, (rw, rh))

    # Referencni obrazek pro IP-Adapter: jizni pohled.
    #
    # Pres ref_identity, ne pres .convert("RGB"). Ten totiz alfu jen ZAHODI, takze
    # pruhledne pozadi zcerna — a model se z reference uci kreslit cernou plochu, presne
    # pred cim varuje docstring ref_init(). Navic by CLIP dostal sprite v jeho vlastnich
    # 32 az 64 px a zvetsil si ho hladce, cimz zmizi pixelova mrizka; ref_identity zvetsuje
    # NEAREST na 512 a sklada na magentu, na kterou je model promptovany.
    #
    # neutral=False zamerne: pri rotaci JE barva soucast identity. Odbarvuje se jen pri
    # generovani z nuly, kde by reference prebila paletu z promptu (viz ip_adapter.md).
    base_pil = gen_ref.ref_identity(base_rgba, bg=MAGENTA, neutral=False)

    frames = []
    for i, d in enumerate(dirs):
        view = DIR_VIEWS.get(d, d)
        full = f"{prompt}, {view}, {STYLE}"
        _warn_if_truncated(pipe_i2i, full, f"rotate-ip {d}")

        strength_clamped = float(min(1.0, max(0.05, strength)))
        actual_steps = _steps_for(steps, strength_clamped)

        g = torch.Generator("cuda").manual_seed(seed)
        img = pipe_i2i(
            prompt=full, negative_prompt=NEGATIVE,
            image=init, ip_adapter_image=base_pil,
            strength=strength_clamped, num_inference_steps=actual_steps,
            guidance_scale=7.5, generator=g,
        ).images[0]

        a = cut_background(img)
        a = crop_to_subject(a, aspect=tw / float(th))
        a = downscale(a, (tw, th))
        frames.append(a)
        _progress(on_dir, i + 1, len(dirs), d)

    frames = align_frames(unify_palette(frames, colors))
    return dict(zip(dirs, frames))


def _to_device(pipe, names, device):
    """Presune vyjmenovane moduly roury. Vraci jmena tech, ktere tam skutecne byly.

    Navratova hodnota je urcena k tomu, aby se presun dal vratit — moduly jsou SDILENE
    mezi vsemi rourami postavenymi z pipe.components, takze modul odlozeny na CPU zmizi
    z karty i tomu, kdo o zadnem odkladani nevi. Bez vraceni by pak obycejne generovani
    ve stejnem procesu spadlo na neshode zarizeni."""
    import torch
    moved = []
    for n in names:
        m = getattr(pipe, n, None)
        if m is not None and hasattr(m, "to"):
            m.to(device)
            moved.append(n)
    torch.cuda.empty_cache()
    return moved


# KOLIK SE VEJDE NA KARTU
#
# Zmereno 18. 8. 2026 na 4070 SUPER (12 282 MiB). Vahy samotne:
#
#     SDXL + LoRA                    7 318 MiB
#     + ControlNet openpose          ~2 500 MiB
#     + obrazkovy enkoder ViT-bigG   ~1 850 MiB
#     ------------------------------------------
#     dohromady                     11 984 MiB   = 97,6 % karty
#
# Od te chvile nema kde vzniknout mezivysledek a ovladac zacne prelevat do systemove
# pameti. NESPADNE TO A NIC NENAHLASI, jen jeden smer trva 6,5 minuty misto ~40 sekund.
# Poznat se to da jen na prikonu: 65 W z 220 W pri 100 % vytizeni znamena, ze karta ceka
# na pamet, ne ze pocita.
#
# Reseni neni obetovat kvalitu, ale prestat drzet na karte to, co uz dobehlo. Obrazkovy
# enkoder bezi JEDNOU na referenci, textove enkodery JEDNOU na kazdy prompt — a pak
# dvacet osm kroku jen zabiraji misto. Predpocitat je a odlozit je z karty tedy neni
# uskrtnuti, je to poradek: usetri ~3,5 GB a soucasne to i zrychli, protoze se reference
# nekoduje osmkrat po sobe znovu.


def rotate_pose(pipe, base_rgba, prompt, dirs=None, steps=28, seed=1, size=32, colors=16,
                ip_scale=POSE_IP_SCALE, control_scale=CONTROL_SCALE, cfg=7.5, stride=0.35,
                canon=None, render=POSE_RENDER, back_negative=False, same_pose=False,
                keep_controls=None, on_dir=None):
    """Smery z KOSTRY: ControlNet urcuje pohled, IP-Adapter identitu, text zbytek.

    Tohle je jedina ze tri "rotaci", ktera pohled skutecne meni. rotate() a rotate_ip()
    prekresluji celni sprite a faze 2 zmerila, ze pohled zustane celni — vysledkem jsou
    varianty tehoz pohledu, ne otoceni. Nemazou se proto, ze varianty jsou k necemu dobre,
    ale jmena maji zavadejici.

    Rozdeleni praci je tu poprve ciste na tri nezavisle paky:

        kostra (control_scale)  JAK STOJI a odkud se na ni divame
        reference (ip_scale)    KDO to je — barvy, textura, doplnky
        text                    co to je a jak to ma vypadat

    Zadny vychozi obrazek. Kdyby model dostal zakladni sprite jako init, pretlacil by
    kostru celnim pohledem — to je presne ta past, kvuli ktere faze 2 dopadla spatne.

    same_pose=True je KONTROLNI VZOREK: vsem smerum da jiznii kostru. Kdyz i tak vyjde osm
    ruznych pohledu, pohled nedela kostra a cele merení je o necem jinem, nez si mysli.
    Kdyz vyjde osmkrat celni pohled, je dokazano, ze pohledem hybe prave ridici obrazek.

    keep_controls: kdyz je to seznam, doplni se do nej pouzite kostry. Na kontaktni list
    se hodi mit vedle spritu i to, z ceho vznikly."""
    import torch

    dirs = [d for d in (dirs or DIRECTIONS)]
    # Adapter se sunda z UNETU JESTE PRED stavbou roury. Priznak sedi na sdilenem UNetu,
    # ale obrazkovy enkoder na rouře — kdyby adapter zbyl z drivejsiho rotate_ip, nova
    # roura by ho zdedila jen napul. Viz load_ip_adapter.
    unload_ip_adapter(pipe)

    tw, th = _pair(size)
    # `render` je rozpocet na render, ne velikost spritu. Snizit ho je nejlevnejsi paka na
    # VRAM, protoze aktivace rostou s PLOCHOU: 768 misto 1024 je o 44 % mensi mezivysledek
    # a na sprite 32-64 px porad zbyde 12 az 24 zdrojovych pixelu na pixel spritu, tedy
    # hluboko nad prahem 8, pod kterym zmenseni zacne zahazovat detail.
    rw, rh = gen_ref.render_size(tw, th, render)
    dev = torch.device("cuda")
    odlozeno = []
    frames = []
    try:
        # --- VSECHNO PODMINOVANI SE SPOCITA DRIV, NEZ SE NACTE CONTROLNET ---
        #
        # PORADI TU NENI KOSMETIKA, JE TO CELE RESENI. Vahy vsech tri casti dohromady jsou
        # ~11,7 GB, jenze karta ma po Windows volnych jen ~11,07 GB — nevejdou se, tecka.
        # A pri prekroceni to nespadne: ovladac zacne prelevat do systemove pameti a z toho
        # uz se v temze procesu NEVYCOUVA ani uvolnenim (zmereno: po odlozeni enkoderu
        # hlasil `mem_get_info` porad volno 0).
        #
        # Jedina cesta je nikdy tu spicku nevyrobit. Obrazkovy enkoder (1,85 GB) se proto
        # nacita ve chvili, kdy na karte sedi jen SDXL, hned se na nem spocitaji embeddingy
        # a odejde z karty. Totez textove enkodery. ControlNet prijde az na uklizenou.
        #
        #     spicka  SDXL 6,9 + enkoder 1,85       =  8,75 GB    vejde se
        #     potom   SDXL bez enkoderu 5,2 + CN 2,5 =  7,7 GB    zbyva ~3,3 GB na mezivysledky
        #
        # Enkodery davaji presne tytez cislo jako pri volani uvnitr roury, jen se spocitaji
        # jednou misto pri kazdem smeru — takze to i zrychli.
        embeds = None
        if ip_scale and ip_scale > 0:
            # Enkoder zustane na CPU a embeddingy se spocitaji tam — viz load_ip_adapter,
            # proc se ta spicka nesmi ani na okamzik vyrobit. Na kartu jde az vysledek,
            # coz je par kilobajtu misto 1,85 GB.
            load_ip_adapter(pipe, scale=ip_scale, encoder_on_cpu=True)
            # neutral=False: pri otaceni JE barva soucast identity. Odbarvuje se jen pri
            # generovani z nuly, kde by reference prebila paletu z promptu (ip_adapter.md).
            ref = gen_ref.ref_identity(base_rgba, bg=MAGENTA, neutral=False)
            embeds = pipe.prepare_ip_adapter_image_embeds(
                ref, None, torch.device("cpu"), 1, cfg > 1.0)
            embeds = [e.to(dev, dtype=pipe.unet.dtype) for e in embeds]

        conds = []
        for d in dirs:
            full = f"{prompt}, {DIR_VIEWS.get(d, d)}, {STYLE}"
            neg = negative_for(d) if back_negative else NEGATIVE
            _warn_if_truncated(pipe, full, f"rotate-pose {d}")
            _warn_if_truncated(pipe, neg, f"negativ {d}")
            conds.append(pipe.encode_prompt(
                prompt=full, device=dev, num_images_per_prompt=1,
                do_classifier_free_guidance=cfg > 1.0, negative_prompt=neg))
        odlozeno += _to_device(pipe, ["text_encoder", "text_encoder_2"], "cpu")
        vram("odložení enkodérů")

        pipe_cn = build_control_pipe(pipe, "openpose")
        vram("načtení ControlNetu")

        for i, d in enumerate(dirs):
            ctrl = gen_pose.for_direction("south" if same_pose else d, DIRECTIONS,
                                          size=(rw, rh), stride=stride, canon=canon)
            if keep_controls is not None:
                keep_controls.append(ctrl)
            pe, npe, ppe, nppe = conds[i]
            # Stejny seed pro vsechny smery, jako u rotate a animate: at se smery lisi JEN
            # kostrou a ne tim, ze kazdy zacal z jineho sumu.
            g = torch.Generator("cuda").manual_seed(seed)
            extra = {"ip_adapter_image_embeds": embeds} if embeds is not None else {}
            img = pipe_cn(
                prompt_embeds=pe, negative_prompt_embeds=npe,
                pooled_prompt_embeds=ppe, negative_pooled_prompt_embeds=nppe,
                image=ctrl, controlnet_conditioning_scale=float(control_scale),
                num_inference_steps=steps, guidance_scale=cfg,
                width=rw, height=rh, generator=g, **extra,
            ).images[0]

            a = cut_background(img)
            a = crop_to_subject(a, aspect=tw / float(th))
            a = downscale(a, (tw, th))
            frames.append(a)
            _progress(on_dir, i + 1, len(dirs), d)
    finally:
        # Moduly jsou sdilene se vsemi ostatnimi rourami, takze se MUSI vratit i kdyz to
        # spadne — jinak by dalsi generovani v temze procesu skoncilo na neshode zarizeni
        # a vypadalo by to jako vada nekde uplne jinde. Vraci se pres `pipe`, ne pres
        # `pipe_cn`: ten pri vyjimce v prvni polovine jeste nemusi existovat, kdezto moduly
        # jsou tytez objekty, takze na tom, ktera roura je vrati, nezalezi.
        _to_device(pipe, odlozeno, "cuda")

    frames = align_frames(unify_palette(frames, colors))
    return dict(zip(dirs, frames))


# ------------------------------------------------------------------ znamkovani
#
# CO BYLO NA PUVODNI ZNAMCE SPATNE
#
# Merila paletu proti rozpoctu a nic vic: cim vic barev, tim hur. Tentyz sprite spadl z
# 8.1 na 3.4 jen tim, ze se povolilo vic barev — a UI podle znamky RADI, takze nahoru
# davalo ten nejplossi. Generator tim doporucoval presny opak toho, co se od nej chce.
#
# Chyba nebyla v citlivosti prahu, ale v tom, ze pocet barev je slepy k tomu, CO ty barvy
# delaji. Rozliseni sumu od detailu je jedina otazka, na ktere zalezi:
#
#   SUM     Osamocene pixely bez souseda te same barvy; barvy rozsete po spritu, ktere
#           nikde netvori plochu. Jsou to mezistupne mezi dvema skutecnymi barvami, zbytek
#           po zmenseni renderu. Roztrepeny okraj je totez na siluete.
#   DETAIL  Barva, ktera nekde tvori souvisly tvar (aspon dva pixely te same barvy vedle
#           sebe), nebo mala plocha VYRAZNE odlisna od zbytku palety — oko, odlesk, zub.
#           Prah kontrastu je tentyz, kterym despeckle chrani oci pred vycistenim
#           (0.12 v Oklabu), takze "detail" znamena v obou nastrojich totez.
#
# Znamka je pak vazeny prumer ctyr slozek: CISTOTA (nejvic — sum je jediná vada, kterou
# uz nejde spravit jinak nez znovu), KAZEN PALETY (kolik barev jen sumí, az potom
# prekroceni rozpoctu), BOHATOST (nova slozka: plochy sprite uz neni nejlepsi mozny) a
# PLOCHA. Bohaty cisty sprite dostane vic nez plochy, protoze plochy nema z ceho vzit
# body za bohatost — a soucasne uz se netrestaji barvy, ktere doopravdy neco kresli.

ACCENT_CONTRAST = 0.12   # Oklab; tentyz prah, jakym despeckle pozna oko od zbytku po zmenseni
ACCENT_MAX_PX = 2        # barva na jednom dvou pixelech je akcent, na peti rozsypanych sum
ACCENT_LIMIT = 4         # ...ale ctyri akcenty na sprite je strop, vic uz je posypka


def _neighbors(a):
    """(neprusvitne, ma souseda TEZE barvy, pocet neprusvitnych sousedu) ve 4-okoli.

    Ctyrokoli a ne osm, aby "osamoceny pixel" znamenal v generatoru presne totez co v
    art_check.isolated_ratio a v sprite_cleanup.isolated_mask. Trojí definice sumu by
    znamenala, ze kazdy nastroj hlasí jine cislo o tomtez spritu."""
    m = a[..., 3] > 32
    rgb = a[..., :3]
    h, w = m.shape
    same = np.zeros((h, w), bool)
    cnt = np.zeros((h, w), np.int16)
    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        ys, xs = slice(max(0, dy), h + min(0, dy)), slice(max(0, dx), w + min(0, dx))
        yd, xd = slice(max(0, -dy), h + min(0, -dy)), slice(max(0, -dx), w + min(0, -dx))
        nb = np.zeros((h, w), bool)
        nb[yd, xd] = m[ys, xs]
        eq = np.zeros((h, w), bool)
        eq[yd, xd] = (rgb[ys, xs] == rgb[yd, xd]).all(-1) & m[ys, xs]
        same |= eq
        cnt += nb
    return m, same & m, cnt


def edge_ragged(a):
    """Podil obrysovych pixelu, ktere z tvaru TRCI (visi na jednom sousedovi nebo na
    zadnem). Meri se proti obvodu, ne proti plose: obvod roste s velikosti spritu jinak
    nez plocha, takze podil na plochu by u 64px bosse vysel vzdycky lip nez u 16px
    dlazdice, i kdyz je okraj stejne roztrepeny."""
    m, _, cnt = _neighbors(a)
    if not m.any():
        return 0.0
    border = int((m & (cnt < 4)).sum())
    spike = int((m & (cnt <= 1)).sum())
    return float(spike) / float(max(1, border))


def color_roles(a):
    """Barvy spritu roztridene podle toho, CO delaji -> (tvarove, akcenty, sumici).

    tvar    barva ma nekde aspon dva pixely vedle sebe — kresli plochu, linku nebo obrys
    akcent  1-2 pixely, ale v Oklabu daleko od VSECH tvarovych barev: oko, odlesk, zub
    sum     zbytek. Barva, ktera nikde netvori tvar a pritom lezi barevne mezi skutecnymi
            barvami — tak vypada mezistupen po zmenseni renderu.

    Vzdalenost se pocita k tvarovym barvam, protoze prave to sumici barvu prozradi:
    vznikla smisenim dvou sousednich ploch, takze k aspon jedne z nich ma blizko. Oko je
    naopak barva, ktera v okoli nema obdobu."""
    m, same, _ = _neighbors(a)
    if not m.any():
        return 0, 0, 0
    rgb = a[..., :3].astype(np.int64)
    key = (rgb[..., 0] << 16) | (rgb[..., 1] << 8) | rgb[..., 2]
    codes, coh = key[m], same[m]

    shape, rest = [], []
    for c in np.unique(codes).tolist():
        sel = codes == c
        # >= 2 a ne >= 1: souvisly tvar znamena DVOJICI sousedu, a ta se v masce projevi
        # u obou pixelu naraz. Prah 1 by neprosel nikdy — jeden pixel souseda nema z ceho mit.
        if int(coh[sel].sum()) >= 2:
            shape.append(c)
        else:
            rest.append((int(sel.sum()), c))
    if not shape:
        # Sprite bez jedine souvisle plochy je sum cely — akcent nema proti cemu kontrastovat.
        return 0, 0, len(rest)

    unpack = [[(c >> 16) & 255, (c >> 8) & 255, c & 255] for c in shape]
    shape_lab = to_oklab(np.array(unpack, dtype=np.int64))
    accent = noise = 0
    for n_px, c in sorted(rest, reverse=True):      # vetsi (2px) akcenty maji prednost
        col = np.array([[(c >> 16) & 255, (c >> 8) & 255, c & 255]], dtype=np.int64)
        d = float(np.sqrt(((to_oklab(col) - shape_lab) ** 2).sum(-1)).min())
        if n_px <= ACCENT_MAX_PX and d >= ACCENT_CONTRAST and accent < ACCENT_LIMIT:
            accent += 1
        else:
            noise += 1
    return len(shape), accent, noise


def target_budget(a, opaque, size=None):
    """Rozpocet palety podle CILOVE velikosti spritu (art_check.palette_budget).

    Rozpocet se v art_check odviji od poctu neprusvitnych pixelu. Kdyz se znamkuje sprite
    v jine velikosti, nez v jake pujde do hry, prepocita se pocet pixelu pomerem ploch —
    jinak by 64px pracovni kopie dostala rozpocet, ktery po zmenseni na 32 px neplati, a
    tentyz art by se "zhorsil" pouhym zmensenim."""
    tw, th = _pair(size, (a.shape[1], a.shape[0]))
    area = float(a.shape[0] * a.shape[1]) or 1.0
    return int(palette_budget(opaque * (tw * th) / area))


def score(a, size=None):
    """Znamka podle tychz mer, kterymi art_check meri zbytek hry. `size` je CILOVA
    velikost spritu (32 nebo (16, 8)); bez ní se bere velikost obrazku.

    Nehodnoti, jestli je to hezke — to skript neumi a umet nebude. Hodnoti, jestli je to
    POUZITELNY pixel art. Rozvahu za jednotlivymi slozkami viz komentar nad ACCENT_*."""
    m = a[..., 3] > 32
    opaque = int(m.sum())
    if opaque < 20:
        return {"grade": 0.0, "cols": 0, "iso": 1.0, "fill": 0.0, "budget": 0,
                "shape": 0, "accent": 0, "noise": 0, "edge": 1.0, "note": "prázdné"}
    cols = len({tuple(c) for c in a[..., :3][m]})
    iso = float(isolated_ratio(a))
    edge = float(edge_ragged(a))
    fill = opaque / float(a.shape[0] * a.shape[1])
    budget = target_budget(a, opaque, size)
    shape, accent, noise = color_roles(a)
    useful = shape + accent

    # CISTOTA. Tolerance 0.15 u sumu je tataz hranice, od ktere si vsima art_check.
    # Okraj ma vlastni prah, protoze se meri proti obvodu: par pixelu na koncetinach ma
    # i cisty sprite.
    g_iso = 1.0 - min(1.0, max(0.0, iso - 0.15) / 0.35)
    g_edge = 1.0 - min(1.0, max(0.0, edge - 0.08) / 0.30)
    g_clean = 0.6 * g_iso + 0.4 * g_edge

    # KAZEN PALETY. Hlavni je podil barev, ktere nic nekresli. Prekroceni rozpoctu se
    # trestá jen mirne a se stropem — je to vytka k artu, ktery uz neco umi, kdezto
    # sumici barvy jsou vada. Presne obracene to delala puvodni verze.
    junk = noise / float(cols)
    over = max(0.0, useful - budget) / float(budget)
    g_pal = max(0.0, 1.0 - 1.2 * junk - 0.5 * min(1.0, over))

    # BOHATOST. Bez teto slozky je uplne plochy sprite bez vady, a tim padem nejlepsi.
    # Plny pocet bodu je uz pri ~polovine rozpoctu (u 32px prisery kolem deviti barev),
    # coz je bezne pixel-artove telo: zaklad, stin a svetlo pro dva materialy plus obrys.
    rich_target = max(6.0, 0.45 * budget)
    g_rich = min(1.0, useful / rich_target)

    # PLOCHA, nesymetricky. Malo pokryti je vada vzdycky (bod uprostred prazdna), ale plne
    # pokryti je u dlazdice spravne — proto z teto slozky ubere nejvys 0.4, kdezto puvodni
    # symetricke okno kolem 0.55 dalo plne dlazdici nulu.
    g_fill = (fill / 0.5 if fill < 0.5
              else 1.0 - 0.4 * min(1.0, max(0.0, fill - 0.85) / 0.15))

    grade = round(10.0 * (0.40 * g_clean + 0.25 * g_pal + 0.20 * g_rich + 0.15 * g_fill), 1)

    note = []
    if noise:
        note.append(f"{noise} barev jen šumí")
    if useful > budget:
        note.append(f"{useful} nesoucích barev proti rozpočtu {budget}")
    if iso > 0.30:
        note.append(f"{iso * 100:.0f} % šumu")
    if edge > 0.25:
        note.append("roztřepený okraj")
    if useful < rich_target:
        note.append(f"plochý — jen {useful} barev nese tvar")
    if fill < 0.25:
        note.append("moc malá")
    return {"grade": grade, "cols": cols, "iso": iso, "fill": fill, "budget": budget,
            "shape": shape, "accent": accent, "noise": noise, "edge": edge,
            "note": ", ".join(note) or "ok"}


def contact_sheet(items, path, zoom=6, pad=8, bg=(24, 24, 30)):
    """Vsichni kandidati vedle sebe se znamkou pod sebou.

    Bunka je obdelnik podle spritu, ne ctverec: dlazdice 16x8 natazena do ctverce by na
    prehledu vypadala jako svisle rozmazana — a prehled je prave to misto, kde se ma
    poznat, ze je neco spatne."""
    if not items:
        return
    from PIL import ImageDraw as D
    tw = items[0][0].shape[1] * zoom
    th = items[0][0].shape[0] * zoom
    cols = min(4, len(items))
    rows = (len(items) + cols - 1) // cols
    W = cols * (tw + pad) + pad
    H = rows * (th + pad + 18) + pad
    sheet = Image.new("RGB", (W, H), bg)
    dr = D.Draw(sheet)
    for k, (a, sc, name) in enumerate(items):
        r, c = divmod(k, cols)
        x = pad + c * (tw + pad)
        y = pad + r * (th + pad + 18)
        im = Image.fromarray(a, "RGBA").resize(
            (a.shape[1] * zoom, a.shape[0] * zoom), Image.NEAREST)
        sheet.paste(im, (x, y), im)
        dr.text((x, y + th + 3), f"{name}  {sc['grade']}/10  {sc['note']}",
                fill=(200, 200, 212))
    sheet.save(path)


# ------------------------------------------------------------------ main


def main():
    global DOWNSCALE            # nastavuje ho --downscale, viz komentar u DOWNSCALE
    ap = argparse.ArgumentParser(description="Lokální generátor pixel-art spritů.")
    ap.add_argument("prompt", nargs="?", help="co nakreslit (anglicky)")
    ap.add_argument("--name", help="jméno sady (složka v build/gen/)")
    ap.add_argument("--n", type=int, default=6, help="kolik kandidátů (default 6)")
    ap.add_argument("--size", default="32", metavar="N|WxH",
                    help="cílová velikost spritu: 32 nebo 16x8 (default 32). Známé "
                         "velikosti: " + ", ".join(f"{s} = {co}" for s, co in gen_ref.TARGET_SIZES))
    ap.add_argument("--render", type=int, default=None, metavar="PX",
                    help="rozpočet renderu: 1024 = nejvíc detailu, 512 je 4× rychlejší "
                         "a levnější na VRAM (default 1024)")
    ap.add_argument("--colors", type=int, default=16, help="barev v paletě (default 16)")
    ap.add_argument("--downscale", choices=sorted(DOWNSCALERS), default=DOWNSCALE,
                    help=f"čím zmenšit render na cílový rastr (default {DOWNSCALE}): "
                         "median řeší každý kanál zvlášť, kcentroid shlukuje celé RGB "
                         "a drží hrany")
    ap.add_argument("--steps", type=int, default=28)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--lora-weight", type=float, default=LORA_WEIGHT, metavar="F",
                    help=f"síla pixel-art LoRA (default {LORA_WEIGHT}). 1.0 zjednoduší tak, "
                         "že zahodí detaily z promptu; 0 rozbije odstranění pozadí")
    ap.add_argument("--keep-raw", action="store_true", help="ulož i render 1024 px")
    ap.add_argument("--list", action="store_true", help="vypiš, co už je vygenerované")
    # dest="src", protože `from` je v Pythonu klíčové slovo a args.from by byla chyba
    # syntaxe — na attribut by se pak dalo dostat jen přes getattr.
    ap.add_argument("--from", dest="src", metavar="PNG",
                    help="dolaď hotový sprite místo generování od nuly (img2img)")
    ap.add_argument("--ref", metavar="PNG",
                    help="referenční obrázek z assets/ nebo build/ — nový sprite se podle "
                         "něj narodí místo aby se do stylu pak opravoval")
    ap.add_argument("--ref-mode", choices=gen_ref.REF_MODES, default="oboji",
                    help="co se z reference vezme: zaklad = kompozice, paleta = barvy, "
                         "oboji (default), identita = IP-Adapter (model referenci vidí "
                         "po celou dobu, kompozice zůstává volná)")
    ap.add_argument("--ip-scale", type=float, default=None, metavar="F",
                    help=f"síla identity u --ref-mode identita (default {IP_SCALE}); "
                         "nahoru drží referenci víc a poslouchá prompt míň")
    ap.add_argument("--ip-color", action="store_true",
                    help="ber z reference i BARVU (jinak se subjekt odbarví a barva "
                         "zůstane na promptu)")
    # default=None, ne cislo: rozumna sila je jina pro dolaďovani (drobna zmena), pro
    # otoceni (jiny pohled) a pro generovani z reference (jina prisera v teze poze).
    # Jedno spolecne cislo by dve ze tri pouziti tise pokazilo.
    ap.add_argument("--strength", type=float, default=None, metavar="F",
                    help="kolik smí model přepsat: 0.2 = retuš, 0.5 = už jiná příšera "
                         "(default 0.35 pro --from, 0.45 pro --rotate, 0.6 pro --ref)")
    ap.add_argument("--animate", choices=sorted(POSES), metavar="DRUH",
                    help="místo kandidátů vyrob animaci ze --from spritu (walk, idle)")
    ap.add_argument("--poses", metavar="A;B;C",
                    help="vlastní pózy pro animaci, oddělené středníkem (přebijí --animate)")
    ap.add_argument("--rotate", action="store_true",
                    help="ze --from spritu vyrob osm směrů (jedna příšera otočená, "
                         "ne osm příšer)")
    ap.add_argument("--dirs", metavar="A,B",
                    help="jen vybrané směry pro --rotate (default všech osm: "
                         + ", ".join(DIRECTIONS) + ")")
    ap.add_argument("--pose", action="store_true",
                    help="směry přes kostru a ControlNet — jediná varianta, která pohled "
                         "opravdu mění (--rotate překresluje čelní pohled)")
    ap.add_argument("--canon", choices=sorted(gen_pose.CANONS), default=gen_pose.CANON,
                    help=f"proporce kostry pro --pose (default {gen_pose.CANON}; "
                         "human je to, na čem se ControlNet učil)")
    ap.add_argument("--control-scale", type=float, default=CONTROL_SCALE, metavar="F",
                    help=f"jak silně tlačí kostra (default {CONTROL_SCALE}; nad ~0,9 "
                         "model kreslí kostru místo postavy)")
    args = ap.parse_args()

    # Nastavi se jednou, pred vsim ostatnim — generovani i doladeni v jednom behu pak
    # zmensuji stejne.
    DOWNSCALE = args.downscale

    # `--render` ma vychozi hodnotu az TED, ne v add_argument. Kdyby ji mel tam, prebilo by
    # napevno zadanych 1024 zmerenou hodnotu POSE_RENDER pro kostrovou cestu — a to potise,
    # takze by --pose z prikazove radky bezel dvakrat pomaleji nez ze studia a nikdo by
    # nevedel proc. None znamena "uzivatel nerekl", takze se doplni podle toho, co se dela.
    if args.render is None:
        args.render = POSE_RENDER if args.pose else 1024
    # Totez pro silu reference: kostrova cesta ma svou zmerenou hodnotu (POSE_IP_SCALE),
    # protoze pri IP_SCALE=0.4 se avokadovy mnich zmenil v obecneho zeleneho mnicha.
    if args.ip_scale is None:
        args.ip_scale = POSE_IP_SCALE if args.pose else IP_SCALE

    if args.list:
        if not os.path.isdir(OUT):
            print("zatím nic")
            return
        for d in sorted(os.listdir(OUT)):
            fs = os.listdir(os.path.join(OUT, d))
            # Animace se pocitaji zvlast: sada osmi framu chuze neni "osm kandidatu",
            # ze kterych se vybira jeden, ale jedna vec, ktera drzi pohromade.
            nc = len([f for f in fs if f.startswith("cand_")])
            nf = len([f for f in fs if f.startswith("frame_")])
            what = f"{nc} kandidátů" if nc else ""
            what += (", " if what and nf else "") + (f"{nf} framů animace" if nf else "")
            print(f"  {d:<30}{what or '—'}")
        return

    # Pozy urcuji, jestli se dela animace. --poses prebiji --animate, protoze rucne psany
    # seznam je vzdycky konkretnejsi zamer nez volba z nabidky.
    poses = None
    if args.poses:
        poses = [p.strip() for p in args.poses.split(";") if p.strip()]
    elif args.animate:
        poses = POSES[args.animate]

    if poses and (args.rotate or args.pose):
        sys.exit("--animate a otáčení najednou nejde: framy cyklu a směry jsou dvě různé "
                 "sady. Udělej nejdřív směry a teprve z jednoho z nich animaci.")
    if args.rotate and args.pose:
        sys.exit("--rotate a --pose jsou dvě různé cesty k témuž a nedají se sloučit.\n"
                 "  --pose   ControlNet + kostra; pohled se skutečně změní\n"
                 "  --rotate img2img; překreslí čelní pohled na variantu téhož pohledu")
    if (poses or args.rotate or args.pose) and not args.src:
        sys.exit("Animace i otočení potřebují základ: --from <sprite.png>.\n"
                 "Vznikají z JEDNOHO spritu — bez něj by každý frame byla jiná příšera.")

    if not args.prompt:
        sys.exit("Chybí prompt. Příklady:\n"
                 '  python tools/gen.py "energy drink creature with legs" --name endrink\n'
                 '  python tools/gen.py "energy drink creature" --from build/gen/x/cand_03.png')

    # Cilova velikost spritu a z ni rozliseni renderu. Obojí pocita gen_ref, aby matematika
    # kolem pomeru stran nebyla ve dvou nastrojich dvakrat — a pokazde trochu jinak.
    try:
        tw, th = gen_ref.parse_size(args.size)
    except ValueError as e:
        sys.exit(str(e))
    rw, rh = gen_ref.render_size(tw, th, args.render)
    ppx = gen_ref.px_per_sprite_pixel(tw, th, args.render)

    ref_img = ref_pal = ref_ip = None
    if args.ref:
        try:
            ref_a = gen_ref.load_ref(args.ref)
            if args.ref_mode in ("zaklad", "oboji"):
                ref_img = gen_ref.ref_init(ref_a, rw, rh, MAGENTA)
            if args.ref_mode in ("paleta", "oboji"):
                ref_pal = gen_ref.ref_palette(ref_a, args.colors)
            if args.ref_mode == "identita":
                ref_ip = gen_ref.ref_identity(ref_a, bg=MAGENTA,
                                              neutral=not args.ip_color)
            print("reference: " + gen_ref.describe(args.ref, args.ref_mode, args.colors))
        except ValueError as e:
            sys.exit(f"Reference: {e}")

    # Vychozi sila podle toho, co se dela — viz komentar u --strength.
    strength = args.strength
    if strength is None:
        strength = 0.45 if args.rotate else (0.6 if (ref_img is not None and not args.src)
                                             else 0.35)

    if args.src:
        if not os.path.isfile(args.src):
            sys.exit(f"Sprite neexistuje: {args.src}")
        parent = np.array(Image.open(args.src).convert("RGBA"))
        # Vychozi jmeno nese rodokmen: <sada rodice>_<soubor rodice>_<co se delo>. Dite se
        # tak nikdy netrefi do slozky rodice a je z nej videt, z ceho vzniklo.
        stem = os.path.splitext(os.path.basename(args.src))[0]
        pset = os.path.basename(os.path.dirname(os.path.abspath(args.src)))
        what = "pose" if args.pose else ("rotate" if args.rotate else (args.animate or "refine"))
        name = args.name or f"{pset}_{stem}_{what}"
    else:
        parent = None
        name = args.name or "".join(ch if ch.isalnum() else "_" for ch in args.prompt)[:32]

    d = os.path.join(OUT, name)
    os.makedirs(d, exist_ok=True)

    print(f"render {rw}×{rh} → sprite {tw}×{th}  ({ppx:.0f} px zdroje na pixel spritu)")
    if ppx < 8:
        print("  POZOR: pod 8 px na pixel spritu zmenšení vyhazuje detail rychleji, "
              "než ho model stihne nakreslit — zvyš --render.")

    # scores se klice SOUBOREM, ne poradim v items: items se u kandidatu jeste seradi podle
    # znamky, takze "treti v seznamu" uz neznamena cand_03.png.
    items, scores = [], {}

    def keep(a, fn, label):
        # Znamka dostane CILOVOU velikost, i kdyz je sprite prave ted stejne velky:
        # az bude, rozpocet palety se nezmeni pod rukama.
        sc = score(a, (tw, th))
        Image.fromarray(a, "RGBA").save(os.path.join(d, fn))
        scores[fn] = sc
        items.append((a, sc, label))

    dirs_done = {}
    if parent is None:
        pipe = build_pipe(args.lora_weight)
        if ref_ip is not None:
            load_ip_adapter(pipe, args.ip_scale)
        print(f'generuji {args.n}× „{args.prompt}"')
        raws = generate(pipe, args.prompt, args.n, args.steps, args.seed,
                        size=(rw, rh), init=ref_img, strength=strength, ip_image=ref_ip)
        for i, img in enumerate(raws, 1):
            if args.keep_raw:
                img.save(os.path.join(d, f"raw_{i:02d}.png"))
            keep(to_sprite(img, (tw, th), args.colors, ref_pal), f"cand_{i:02d}.png", f"#{i}")
    elif args.pose:
        # Kostrova cesta si stavi vlastni rouru (text2img + ControlNet), takze zadny
        # build_img2img — ten by tu jen zbytecne zabral misto na karte, na ktere uz je
        # ControlNet a IP-Adapter tesno.
        pipe1 = build_pipe(args.lora_weight)
        dirs = [s.strip() for s in args.dirs.split(",") if s.strip()] if args.dirs else None
        print(f"otáčím {len(dirs or DIRECTIONS)}× z {args.src} přes kostru "
              f"(kánon {args.canon}, kostra {args.control_scale}, identita {args.ip_scale})")
        res = rotate_pose(pipe1, parent, args.prompt, dirs=dirs, steps=args.steps,
                          seed=args.seed, size=(tw, th), colors=args.colors,
                          ip_scale=args.ip_scale, control_scale=args.control_scale,
                          canon=args.canon, render=args.render,
                          on_dir=lambda i, n, dd: print(f"  {dd} ({i}/{n})"))
        for dname, a in res.items():
            fn = f"dir_{dname.replace('-', '_')}.png"
            dirs_done[dname] = fn
            keep(a, fn, dname)
    else:
        pipe2 = build_img2img(build_pipe(args.lora_weight))
        if args.rotate:
            dirs = [s.strip() for s in args.dirs.split(",") if s.strip()] if args.dirs else None
            print(f"otáčím {len(dirs or DIRECTIONS)}× z {args.src} (síla {strength})")
            res = rotate(pipe2, parent, args.prompt, dirs=dirs, strength=strength,
                         steps=args.steps, seed=args.seed, size=(tw, th),
                         colors=args.colors,
                         on_dir=lambda i, n, dd: print(f"  {dd} ({i}/{n})"))
            for dname, a in res.items():
                # Pomlcka v nazvu souboru se prevadi na podtrzitko kvuli hre: soubory se
                # jmenuji <id>_north_frame_1.png a split_family v art_check deli podtrzitkem.
                fn = f"dir_{dname.replace('-', '_')}.png"
                dirs_done[dname] = fn
                keep(a, fn, dname)
        elif poses:
            print(f"animace {len(poses)}× z {args.src}")
            frames = animate(pipe2, parent, [f"{args.prompt}, {p}" for p in poses],
                             strength=strength, steps=args.steps, seed=args.seed,
                             size=(tw, th), colors=args.colors,
                             on_frame=lambda i, n: print(f"  frame {i}/{n}"))
            for i, a in enumerate(frames, 1):
                keep(a, f"frame_{i:02d}.png", f"f{i}")
        else:
            print(f"dolaďuji {args.n}× z {args.src} (síla {strength})")
            for i in range(1, args.n + 1):
                a = refine(pipe2, parent, args.prompt, strength=strength,
                           steps=args.steps, seed=args.seed + i - 1, size=(tw, th),
                           colors=args.colors)
                keep(a, f"cand_{i:02d}.png", f"#{i}")
                print(f"  kandidát {i}/{args.n}")

    # Framy animace ani smery se NESERAZUJI podle znamky — jejich poradi neco znamena
    # (cyklus, kompas). U kandidatu je poradi podle znamky naopak to hlavni.
    ordered = bool(poses) or args.rotate or args.pose
    if not ordered:
        items.sort(key=lambda t: -t[1]["grade"])
    contact_sheet(items, os.path.join(d, "_prehled.png"))

    # meta.json cte i Sprite Studio (gen_ui.py). Rodic a sila jsou tu proto, ze bez nich je
    # rodokmen jen v hlave toho, kdo prikaz psal.
    json.dump({"prompt": args.prompt, "parent": args.src or None,
               "strength": strength if args.src else None,
               "size": [tw, th], "render": [rw, rh], "lora_weight": args.lora_weight,
               "ref": args.ref or None, "ref_mode": args.ref_mode if args.ref else None,
               "poses": poses or [], "dirs": dirs_done, "scores": scores},
              open(os.path.join(d, "meta.json"), "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)

    head = "směr" if (args.rotate or args.pose) else ("frame" if poses else "kandidát")
    print(f"\n{head:<10}{'známka':>8}{'barev':>7}{'šum':>7}{'plocha':>8}  poznámka")
    for a, sc, nm in items:
        print(f"{nm:<10}{sc['grade']:>8}{sc['cols']:>7}{sc['iso'] * 100:>6.0f}%"
              f"{sc['fill'] * 100:>7.0f}%  {sc['note']}")
    if poses:
        print("\nframy jsou v pořadí cyklu — známka je tu jen na kontrolu, ne na výběr.")
    else:
        best = items[0]
        print(f"\nnejlepší: {best[2]} ({best[1]['grade']}/10)")
    print(f"výstup:   {os.path.relpath(d, PROJ)}  (_prehled.png = všichni vedle sebe)")
    print("do hry to nejde samo — až tohle projdeš, nainstaluje se to zvlášť.")


if __name__ == "__main__":
    main()
