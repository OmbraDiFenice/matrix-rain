#!/usr/bin/env coffee

parseArgs = require 'minimist'
args = {}

art = require 'ascii-art'
strip = require 'strip-ansi'
mask = ''
maskWidth = maskHeight = 0
blankChar = ' '
computeMask = ->
    conf = 
        filepath: args.maskPath
        alphabet: "bits"
        width: Math.min(numCols, args.maskMaxWidth)
        height: Math.min(numRows, args.maskMaxHeight) * args.scalingFactor
    return new Promise((resolve, reject) ->
        (new art.Image(conf)).write((err, render) ->
            if err
                write tty.reset
                write tty.cursorVisible
                flush()
                c.log(err)
                reject(err)
                process.exit(1)
            mask = strip(render).split('\n')
            mask = mask.slice(0, mask.length-1)
            maskWidth = mask[0].length
            maskHeight = mask.length
            if args.invertMask
                blankChar = '#'
            else
                blankChar = ' '
            resolve(mask)
        )
    )

fs = require 'fs'
c = console
stdout = process.stdout
numRows = stdout.rows
numCols = stdout.columns
maxDroplets = 0
dropletCount = 0
shuffledCols = []
droplets = []
updateMs = 30
updateCount = 0
maxSpeed = 20
colorDropPropability = 0.001

# http://ascii-table.com/ansi-escape-sequences-vt-100.php
tty =
    clearScreen: "\x1b[2J",
    moveCursorToHome: "\x1b[H"
    moveCursorTo: (row,col) -> "\x1b[#{row};#{col}H"
    cursorVisible: '\x1b[?25h'
    cursorInvisible: '\x1b[?25l'
    fgColor: (c) -> "\x1b[38;5;#{c}m"
    bgColor: (c) -> "\x1b[48;5;#{c}m"
    underline: "\x1b[4m"
    bold: "\x1b[1m"
    off: "\x1b[0m"
    reset: "\x1bc"

outBuffer = ""
# perf is improved if we write to stdout in batches
write = (chars) -> outBuffer += chars
writeHead = (drop) ->
    if !args.maskPath
        write drop.headChar
        return
        
    row = drop.row - args.offsetRow
    col = drop.col - args.offsetCol
    maxRow = maskHeight
    maxCol = maskWidth
    
    if args.direction == 'h'
        [col, row] = [row, col]
        
    if row >= 0 && col >= 0 && row < maxRow && col < maxCol && mask[row][col] == blankChar
        write " "
    else
        write drop.headChar
        
flush = ->
    stdout.write(outBuffer)
    outBuffer = ""

# on resize
stdout.on 'resize', ->
    refreshDropletParams()

# on exit
process.on 'SIGINT', ->
    write tty.reset
    write tty.cursorVisible
    flush()
    process.exit()

refreshDropletParams = ->
    numCols = stdout.columns
    numRows = stdout.rows
    
    if args.maskPath
        computeMask()

    # invert rows and columns
    if args.direction == "h"
        [numCols, numRows] = [numRows, numCols]
        if not tty.moveCursorTo.proxied
            moveCursorTo = tty.moveCursorTo
            tty.moveCursorTo = (row, col) -> moveCursorTo(col, row)
            tty.moveCursorTo.proxied = true

    minLength = numRows
    maxLength = numRows
    maxDroplets = numCols  * 2

    #create shuffled cols array
    shuffledCols = [0...numCols]
    for i in [0...numCols]
        rnd = rand(0, numCols)
        [shuffledCols[i], shuffledCols[rnd]] = [shuffledCols[rnd], shuffledCols[i]]
        
    write tty.cursorInvisible
    flush()

createDroplet  = () ->
    droplet =
        col: shuffledCols[dropletCount++ % numCols]
        row: 0
        length: numRows
        speed: rand(1, maxSpeed)
    droplet.chars = getChars(droplet.length)
    droplets.push droplet
    return

updateDroplets = ->
    updateCount++
    remainingDroplets = []
    for drop in droplets
        # remove out of bounds drops
        if (drop.row - drop.length) >= numRows or drop.col >= numCols
            continue
        else
            remainingDroplets.push(drop)

        # process drop speed
        if (updateCount % drop.speed) == 0
            # update old head
            if drop.row > 0 and drop.row <= (numRows + 1)
                write tty.moveCursorTo(drop.row - 1, drop.col)
                if Math.random() < colorDropPropability
                    write tty.fgColor(rand(1,255))
                    writeHead drop
                    write tty.off
                else
                    # change head back to default
                    writeHead drop

            if drop.row <= numRows
                write tty.moveCursorTo(drop.row, drop.col)
                # write new head
                write tty.fgColor(7) #white
                #write tty.underline
                drop.headChar = drop.chars.charAt(drop.row)
                writeHead drop
                write tty.off

            if (drop.row - drop.length) >= 0
                # remove tail
                write tty.moveCursorTo(drop.row - drop.length, drop.col)
                write " "

            drop.row++

    droplets = remainingDroplets
    if droplets.length < maxDroplets
        createDroplet()
    flush()

rand = (start, end) ->
    start + Math.floor(Math.random() * (end - start))

getChars = (len) ->
    chars = ""
    for i in [0...len] by 1
        chars += String.fromCharCode(rand(0x21, 0x7E))
    return chars

getFileChars = (fileContents) ->
    filePos = 0
    return (len) ->
        chars = fileContents.substr(filePos, len)
        if chars.length isnt len
            filePos = len - chars.length
            chars += fileContents.substr(0, filePos)
        else
            filePos += len
        return chars

readFileContents = (filePath) ->
    fileContents = fs.readFileSync(filePath, "utf-8")
    fileContents = fileContents.replace(/^\s+|\r|\n/gm, " ")
    getChars = getFileChars(fileContents)
        
parseCliParams = ->
    args = parseArgs(process.argv.splice(2), {
        string: ['direction', 'd', 'maskPath', 'm', 'scalingFactor']
        boolean: ['help', 'h', 'invertMask', 'i', 'printMask']
        alias: {
            'direction': 'd'
            'maskPath': 'm'
            'invertMask': 'i'
            'help': 'h'
        }
        default: {
            'direction': 'v'
            'invertMask': false
            'help': false
            'offsetRow': 0
            'offsetCol': 0
            'scalingFactor': 2
            'maskMaxWidth': numCols
            'maskMaxHeight': numRows
            'printMask': false
        }
    })
    
    if args.help
        c.log "Usage: matrix-rain [opts] [filePath]"
        c.log "filePath: Read characters from file, otherwise generate random ascii characters"
        c.log "opts:"
        c.log "      -h|--help               show this help and exit"
        c.log "      -d|--direction=v|h      change direction. If reading from file direction is h (horizontal). Default: v"
        c.log "      -m|--maskPath=filePath  use the specified image to build a mask for the raindrops"
        c.log "      -i|--invertMask         invert the mask specified with --maskPath"
        c.log "      --offsetRow=n           move the upper left corner of the mask down n rows"
        c.log "      --offsetCol=n           move the upper left corner of the mask right n columns"
        c.log "      --scalingFactor=n       ratio between character height over width in the terminal. Default: 2"
        c.log "      --maskMaxWidth=n        max width of the mask image, in columns. Default: terminal current columns"
        c.log "      --maskMaxHeight=n       max height of the mask image, in rows. Default: terminal current rows"
        c.log "      --printMask             print mask and exit"
        process.exit(0)

    if args.printMask
        if not args.maskPath
            c.log "no mask provided. Use --maskPath option to set one"
            process.exit()
            
        computeMask().then( (mask) -> 
            for r in [0..args.offsetRow]
                c.log ""
            mask.forEach((row, i) -> 
                c.log " ".repeat(args.offsetCol), row
            )
            process.exit()
        )
        
    match = args.direction.match(/^(v|h)$/)
    if not match
        c.error "unrecognized direction arg '", args.direction, "'"
        process.exit(1)

    if args._.length > 0
        filePath = args._[0] # ignore other non option arguments
        if not fs.existsSync(filePath)
            c.error "Can't find", filePath
            process.exit(1)
        else
            readFileContents(filePath)
            
    if args.maskPath and not fs.existsSync(args.maskPath)
        c.error "Can't find", args.maskPath
        process.exit(1)
            
# initialize
parseCliParams()
write tty.clearScreen
write tty.cursorInvisible
flush()
refreshDropletParams()
setInterval updateDroplets, 10