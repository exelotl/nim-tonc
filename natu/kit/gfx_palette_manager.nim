# Natu Palette Manager
# --------------------
# Before including this file, be sure to: `include my_project/res/gfx`


import natu/mgba
proc panic(msg: cstring) {.noreturn.} =
  # TODO: better implementation
  mgba.printf("%s", msg)
  while true: discard


# General Obj PAL RAM allocator
# -----------------------------
# This lets you allocate or free palettes for sprites.

type
  PalState {.size: 1.} = enum
    palUnused = 0
    palUsed = 1

var objPals {.codegenDecl:EWRAM_DATA.}: array[16, PalState]

proc allocObjPal*: int =
  ## Allocate a 4bpp palette in Obj PAL RAM.
  for i, v in objPals:
    if v == palUnused:
      objPals[i] = palUsed
      return i
  when defined(natuPanicWhenOutOfPals):
    panic("Ran out of obj palettes")
  else:
    objPals.len-1

proc freeObjPal*(i: int) =
  ## Deallocate a 4bpp palette in Obj PAL RAM.
  objPals[i] = palUnused
  when defined(natuShowFreePals):
    objPalMem[i][0] = clrRed


# Graphic palette allocation
# --------------------------
# Every graphic in your graphics.nims gets an associated palNum.
# Graphics defined under a `sharePal` block will have the same palNum.

type
  PalUsage {.size: sizeof(uint16).} = object
    index {.bitsize: 4.}: uint
    count {.bitsize: 12.}: uint

var palUsages {.codegenDecl:EWRAM_DATA.}: array[numPalettes, PalUsage]

proc acquireObjPal(palNum: int, palData: cstring, palHalfwords: int): int {.discardable.} =
  var u = palUsages[palNum]
  var count = u.count
  if count == 0:
    let palId = allocObjPal()
    u.index = palId.uint
    memcpy16(addr objPalMem[palId], palData, palHalfwords)
    result = palId
  else:
    result = u.index.int
  inc count
  u.count = count
  palUsages[palNum] = u

proc releaseObjPal(palNum: int) =
  var u = palUsages[palNum]
  var count = u.count
  if count > 0'u:
    dec count
    if count == 0'u:
      freeObjPal(u.index.int)
    u.count = count
    palUsages[palNum] = u
  else:
    panic("Tried to release an obj palette not in use")

template acquireObjPal*(g: Graphic): int =
  ## 
  ## Increase palUsage reference count.
  ## If the count was zero, allocate a free slot in Obj PAL RAM and
  ## copy the palette into there.
  ## 
  ## Returns which slot in Obj PAL RAM was used, but you don't have
  ## to use the returned value, as you can always check it later
  ## with `getPalId`
  ## 
  acquireObjPal(g.data.palNum, addr palData[g.data.palPos], g.data.palHalfwords)

template releaseObjPal*(g: Graphic) =
  ## Decrease palUsage reference count.
  ## If the count reaches zero, the palette will be freed.
  releaseObjPal(g.data.palNum)

template getPalId*(g: Graphic): int =
  ## Get the current slot in Obj PAL RAM used by a graphic.
  let u = palUsages[g.data.palNum]
  assert(u.count > 0, "Tried to get palId of graphic whose palette is not in use.")
  u.index.int

template loadPal*(g: Graphic) =
  ## Load palette data from a graphic into the correct slot in Obj PAL RAM.
  memcpy16(addr objPalMem[getPalId(g)], unsafeAddr palData[g.data.palPos], g.data.palHalfwords)
