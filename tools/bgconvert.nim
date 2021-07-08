import strutils, strformat, parseopt
import options, os, times
import trick
import ./common

type
  BgKind = enum
    bkReg4bpp  ## Regular background, 16 colors per-tile
    bkReg8bpp  ## Regular background, 256 colors
    bkAff      ## Affine background, 256 colors
  
  BgFlag = enum
    bfScreenblock
    bfBlankTile
    bfAutoPal
  
  BgRow = object
    ## Just the stuff parsed from the tsv
    pngPath: string
    name: string
    kind: BgKind
    palOffset: int      ## First palette ID
    tileOffset: int     ## First tile ID
    flags: set[BgFlag]  ## Misc. conversion options
  
  BgData = object
    kind: BgKind
    w, h: int
    imgWords: uint16
    mapWords: uint16
    palHalfwords: uint16
    palOffset: uint16
    tileOffset: uint16


proc applyOffsets(bg4: var Bg4, palOffset, tileOffset: int) =
  if palOffset > 0:
    for se in mitems(bg4.map):
      se.palbank = se.palbank + palOffset
  if tileOffset > 0:
    for se in mitems(bg4.map):
      se.tid = se.tid + tileOffset


include "templates/background.c.template"
include "templates/backgrounds.c.template"
include "templates/backgrounds.nim.template"


proc bgConvert*(tsvPath, script, indir, outdir: string) =
  
  var bgRows: seq[BgRow]
  
  let outputBgDir = outdir / "backgrounds"
  let outputCPath = outdir / "backgrounds.c"
  let outputNimPath = outdir / "backgrounds.nim"
  
  var oldestModifiedOut = oldest(outdir, outputCPath, outputNimPath, outputBgDir)
  var newestModifiedIn = newest(indir, script)
  
  createDir(outputBgDir)
  
  # parse items from .tsv and check their modification dates
  
  for row in tsvRows(tsvPath):
    
    let (dir, name, ext) = splitFile(row[0])
    doAssert ext in ["", ".png"], "Only PNG files accepted (" & name & ext & ")"
    
    let pngPath = indir / dir / name & ".png"
    if fileExists(pngPath):
      newestModifiedIn = newest(newestModifiedIn, pngPath)
    else:
      raiseAssert "No such file " & pngPath
    
    let bgName = "bg" & name.toCamelCase(firstUpper=true)
    
    bgRows.add BgRow(
      pngPath: pngPath,
      name: bgName,
      kind: parseEnum[BgKind](row[1]),
      palOffset: parseInt(row[2]),
      tileOffset: parseInt(row[3]),
      flags: cast[set[BgFlag]](parseUInt(row[4])),
    )
    
    oldestModifiedOut = oldest(oldestModifiedOut, outputBgDir / bgName & ".c")
  
  # regenerate the output files if any input files have changed:
  
  if newestModifiedIn > oldestModifiedOut:
    
    echo "Converting backgrounds:"
    
    var bgDatas: seq[BgData]
    
    for row in bgRows:
      echo row.pngPath
      
      let modified = true
      
      if modified:
        # convert the bg
        case row.kind
        of bkReg4bpp:
          var bg4 = loadBg4(
            row.pngPath,
            indexed = (bfAutoPal notin row.flags),
            firstBlank = (bfBlankTile in row.flags),
          )
          bg4.applyOffsets(row.palOffset, row.tileOffset)
          
          let img = bg4.img.toBytes()
          let pal = joinPalettes(bg4.pals).toBytes()
          let map = if bfScreenblock in row.flags:
                      bg4.map.toScreenblocks(bg4.w).toBytes()
                    else:
                      bg4.map.toBytes()
          
          withFile outputBgDir / row.name & ".c", fmWrite:
            file.writeBackgroundC(row.name, img, map, pal)
          
          bgDatas.add BgData(
            kind: row.kind,
            w: bg4.w,
            h: bg4.h,
            imgWords: (img.len div 4).uint16,
            mapWords: (map.len div 4).uint16,
            palHalfwords: (pal.len div 2).uint16,
            palOffset: row.palOffset.uint16,
            tileOffset: row.tileOffset.uint16,
          )
          
        of bkReg8bpp:
          var bg8 = loadBg8(row.pngPath, firstBlank = (bfBlankTile in row.flags))
          # TODO: decide offsets for bg8?
          #       tileOffset is fine...
          #       palOffset doesn't make much sense but we may wish to shift by individual colors?
          # bg4.applyOffsets(row.palOffset, row.tileOffset)
          raiseAssert("TODO.")
          
        of bkAff:
          doAssert(bfScreenblock notin row.flags, "Affine bgs don't use screenblocks.")
          raiseAssert("Affine not supported for now.")
    
    withFile outputCPath, fmWrite:
      file.writeBackgroundsC(bgRows)
    withFile outputNimPath, fmWrite:
      file.writeBackgroundsNim(bgRows, bgDatas)
    
  else:
    echo "Skipping backgrounds."


# Command Line Interface
# ----------------------

proc bgConvert*(p: var OptParser, progName: static[string] = "bgconvert") =
  
  const helpMsg = """

Usage:
  """ & progName & """ filename.tsv --indir:DIR --outdir:DIR

Desc
"""
  
  var
    filename: string
    indir: string
    outdir: string
    script: string
  
  while true:
    next(p)
    case p.kind
    of cmdArgument:
      filename = p.key
    of cmdLongOption, cmdShortOption:
      case p.key
      of "script": script = p.val
      of "indir": indir = p.val
      of "outdir": outdir = p.val
      of "h","help": quit(helpMsg, 0)
      else: quit("Unrecognised option '" & p.key & "'\n" & helpMsg)
    of cmdEnd:
      break
  
  if filename == "": quit("Please pass in a .tsv file\n" & helpMsg, 0)
  if script == "": quit("Please specify the bg script\n" & helpMsg, 0)
  if indir == "": quit("Please specify the input directory\n" & helpMsg, 0)
  if outdir == "": quit("Please specify the output directory\n" & helpMsg, 0)
  
  bgConvert(filename, script, indir, outdir)
