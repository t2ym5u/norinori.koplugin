local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local Blitbuffer = require("ffi/blitbuffer")
local Geom       = require("ui/geometry")
local Size       = require("ui/size")

local gwb               = lrequire("common/grid_widget_base")
local GridWidgetBase    = gwb.GridWidgetBase
local drawLine          = gwb.drawLine
local drawDiagonalLine  = gwb.drawDiagonalLine

local NorinoriBoard = lrequire("board")

-- ---------------------------------------------------------------------------
-- Colours: black and white, with grey only for notes and the hint target.
-- ---------------------------------------------------------------------------

local C_BG       = Blitbuffer.COLOR_WHITE
local C_LINE     = Blitbuffer.COLOR_BLACK
local C_SHADE    = Blitbuffer.COLOR_BLACK
local C_MARK     = Blitbuffer.COLOR_WHITE   -- drawn on a shaded tile
local C_SELECTED = Blitbuffer.COLOR_GRAY_D
local C_DOT      = Blitbuffer.COLOR_GRAY_4

-- ---------------------------------------------------------------------------
-- NorinoriBoardWidget
-- ---------------------------------------------------------------------------

local NorinoriBoardWidget = GridWidgetBase:extend{
    board = nil,
}

function NorinoriBoardWidget:init()
    local n   = self.board and self.board.n or NorinoriBoard.DEFAULT_N
    self.cols = n
    self.rows = n
    GridWidgetBase.init(self)
end

function NorinoriBoardWidget:onCellTap(row, col)
    if self.onCellAction then self.onCellAction(row, col, false) end
end

function NorinoriBoardWidget:onCellHold(row, col)
    if self.onCellAction then self.onCellAction(row, col, true) end
end

-- ---------------------------------------------------------------------------
-- paintTo
-- ---------------------------------------------------------------------------

function NorinoriBoardWidget:paintTo(bb, x, y)
    if not self.board then return end
    self.paint_rect = Geom:new{ x = x, y = y, w = self.dimen.w, h = self.dimen.h }

    local board = self.board
    local n     = board.n
    local cell  = self.dimen.w / n
    local show  = board:isShowingSolution()
    local sel   = board.selected

    bb:paintRect(x, y, self.dimen.w, self.dimen.h, C_BG)

    local conflicts = (not show) and board:getConflicts() or nil

    -- Shaded cells are tiles inset from the grid lines, so region borders
    -- stay visible between two shaded neighbours. The inset clears the
    -- outer frame (the thickest line) with a small white gap to spare.
    local thin      = Size.line.thin or 1
    local reg_thick = math.max(3, math.floor(cell * 0.09))
    local inset = reg_thick + math.max(2, math.floor(cell * 0.03))
    local tile  = math.max(1, math.floor(cell) - 2 * inset)
    local cross = math.max(2, math.floor(cell * 0.07))

    for r = 1, n do
        for c = 1, n do
            local cx = x + math.floor((c - 1) * cell)
            local cy = y + math.floor((r - 1) * cell)
            local is_sel = sel and sel[1] == r and sel[2] == c
            local shaded, dot
            if show then
                shaded = board.solution[r][c] == 1
            else
                shaded = board.marks[r][c] == NorinoriBoard.MARK_SHADE
                dot    = board.marks[r][c] == NorinoriBoard.MARK_DOT
            end
            if is_sel then
                bb:paintRect(cx, cy, math.ceil(cell), math.ceil(cell), C_SELECTED)
            end
            if shaded then
                local tx, ty = cx + inset, cy + inset
                bb:paintRect(tx, ty, tile, tile, C_SHADE)
                if conflicts and conflicts[r][c] then
                    -- A white cross on the tile: readable without colour.
                    local m = math.floor(tile * 0.22)
                    local len = tile - 2 * m - cross
                    drawDiagonalLine(bb, tx + m, ty + m, len, 1, 1, C_MARK, cross)
                    drawDiagonalLine(bb, tx + m, ty + tile - m - cross, len, 1, -1, C_MARK, cross)
                end
                if is_sel then
                    -- The hint target on a shaded tile: a white frame inside it.
                    local f = math.max(2, math.floor(cell * 0.05))
                    local m = math.floor(tile * 0.18)
                    local w = tile - 2 * m
                    drawLine(bb, tx + m, ty + m, w, f, C_MARK)
                    drawLine(bb, tx + m, ty + m + w - f, w, f, C_MARK)
                    drawLine(bb, tx + m, ty + m, f, w, C_MARK)
                    drawLine(bb, tx + m + w - f, ty + m, f, w, C_MARK)
                end
            elseif dot then
                bb:paintCircle(cx + math.floor(cell / 2), cy + math.floor(cell / 2),
                    math.max(2, math.floor(cell * 0.09)), C_DOT)
            end
        end
    end

    -- Thin grid lines; the outer frame is as thick as a region border.
    for i = 0, n do
        local lw = (i == 0 or i == n) and reg_thick or thin
        -- The closing line sits inside the widget: drawn at i * cell it
        -- would spill lw - 1 pixels past the right and bottom edges.
        local off = (i == n) and (self.dimen.w - lw) or math.floor(i * cell)
        drawLine(bb, x + off, y, lw, self.dimen.h, C_LINE)
        drawLine(bb, x, y + off, self.dimen.w, lw, C_LINE)
    end

    -- Thick region borders.
    for r = 1, n do
        for c = 1, n do
            if c < n and board.region[r][c] ~= board.region[r][c + 1] then
                local bx = x + math.floor(c * cell) - math.floor(reg_thick / 2)
                local by = y + math.floor((r - 1) * cell)
                drawLine(bb, bx, by, reg_thick, math.ceil(cell), C_LINE)
            end
            if r < n and board.region[r][c] ~= board.region[r + 1][c] then
                local bx = x + math.floor((c - 1) * cell)
                local by = y + math.floor(r * cell) - math.floor(reg_thick / 2)
                drawLine(bb, bx, by, math.ceil(cell), reg_thick, C_LINE)
            end
        end
    end
end

return NorinoriBoardWidget
