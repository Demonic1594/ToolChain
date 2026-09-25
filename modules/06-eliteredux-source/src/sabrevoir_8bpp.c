#include "global.h"
#include "sabrevoir_8bpp.h"

// 8bpp detailed battle fronts (palette entries 128-255; entries 0-127 reserved
// for the four battler palettes and tag-allocated battle UI sprites).
const u8 gSabrevoir8bppFrontShield[] = INCBIN_U8("graphics/pokemon/sabrevoir/anim_front8.8bpp");
const u8 gSabrevoir8bppFrontSword[] = INCBIN_U8("graphics/pokemon/sabrevoir/sword/anim_front8.8bpp");
const u16 gSabrevoir8bppPalShield[] = INCBIN_U16("graphics/pokemon/sabrevoir/anim_front8.gbapal");
const u16 gSabrevoir8bppPalShieldShiny[] = INCBIN_U16("graphics/pokemon/sabrevoir/anim_front8_shiny.gbapal");
const u16 gSabrevoir8bppPalSword[] = INCBIN_U16("graphics/pokemon/sabrevoir/sword/anim_front8.gbapal");
const u16 gSabrevoir8bppPalSwordShiny[] = INCBIN_U16("graphics/pokemon/sabrevoir/sword/anim_front8_shiny.gbapal");

// 8bpp detailed menu icon (palette entries 160-255; both formes share it).
const u8 gSabrevoir8bppIcon[] = INCBIN_U8("graphics/pokemon/sabrevoir/icon8.8bpp");
const u16 gSabrevoir8bppIconPal[] = INCBIN_U16("graphics/pokemon/sabrevoir/icon8.gbapal");

bool32 SpeciesHas8bppSprites(u16 species)
{
    return species == SPECIES_SABREVOIR || species == SPECIES_SABREVOIR_SWORD;
}

const u8 *GetSpecies8bppFrontPic(u16 species)
{
    if (species == SPECIES_SABREVOIR_SWORD)
        return gSabrevoir8bppFrontSword;
    return gSabrevoir8bppFrontShield;
}

const u16 *GetSpecies8bppFrontPal(u16 species, bool32 shiny)
{
    if (species == SPECIES_SABREVOIR_SWORD)
        return shiny ? gSabrevoir8bppPalSwordShiny : gSabrevoir8bppPalSword;
    return shiny ? gSabrevoir8bppPalShieldShiny : gSabrevoir8bppPalShield;
}
