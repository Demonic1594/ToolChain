#ifndef GUARD_SABREVOIR_8BPP_H
#define GUARD_SABREVOIR_8BPP_H

bool32 SpeciesHas8bppSprites(u16 species);
const u8 *GetSpecies8bppFrontPic(u16 species);
const u16 *GetSpecies8bppFrontPal(u16 species, bool32 shiny);
void TryApply8bppMonSpriteOam(u8 spriteId, u16 species);

// OBJ palette layout used by the 8bpp battle art (color-entry offsets into palette RAM)
#define SABREVOIR_8BPP_FRONT_PAL_OFFSET 0x180 // OBJ entries 128-255
#define SABREVOIR_8BPP_FRONT_PAL_COLORS 128

#endif
