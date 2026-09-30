#include "global.h"
#include "sprite.h"
#include "sabrevoir_8bpp.h"

// 8bpp detailed battle fronts only (palette entries 128-255; entries 0-127
// reserved for the four battler palettes and tag-allocated battle UI sprites).
// Menu icons deliberately use the classic 4bpp icon art: only the battle and
// PC-storage sprite paths were adapted for 8bpp, every other icon consumer
// (party menu, summary, move-learning UI, ...) has fixed 16-tile/16-color slots.
const u8 gSabrevoir8bppFrontShield[] = INCBIN_U8("graphics/pokemon/sabrevoir/anim_front8.8bpp");
const u8 gSabrevoir8bppFrontSword[] = INCBIN_U8("graphics/pokemon/sabrevoir/sword/anim_front8.8bpp");
const u16 gSabrevoir8bppPalShield[] = INCBIN_U16("graphics/pokemon/sabrevoir/anim_front8.gbapal");
const u16 gSabrevoir8bppPalShieldShiny[] = INCBIN_U16("graphics/pokemon/sabrevoir/anim_front8_shiny.gbapal");
const u16 gSabrevoir8bppPalSword[] = INCBIN_U16("graphics/pokemon/sabrevoir/sword/anim_front8.gbapal");
const u16 gSabrevoir8bppPalSwordShiny[] = INCBIN_U16("graphics/pokemon/sabrevoir/sword/anim_front8_shiny.gbapal");

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

// Only battle sprites created AFTER BattleLoadMonSpriteGfx loaded 8bpp tiles
// may switch to the 8bpp OAM. Menu screens (summary, evolution, trade, ...)
// call SetMultiuseSpriteTemplateToPokemon with opponent positions too, but
// they load classic 4bpp front pics — the template itself must stay 4bpp.
void TryApply8bppMonSpriteOam(u8 spriteId, u16 species)
{
    if (SpeciesHas8bppSprites(species)) {
        gSprites[spriteId].oam.bpp = ST_OAM_8BPP;
        gSprites[spriteId].oam.paletteNum = 0; // 8bpp reads span the whole OBJ palette
    }
}
