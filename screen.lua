local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local FrameContainer  = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local ProgressbarDialog = require("ui/widget/progressbardialog")
local Size            = require("ui/size")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("i18n")
local T               = require("ffi/util").template
local time            = require("ui/time")

local ScreenBase          = lrequire("common/screen_base")
local MenuHelper          = lrequire("common/menu_helper")
local NorinoriBoard       = lrequire("board")
local NorinoriBoardWidget = lrequire("board_widget")

local GAME_RULES_EN = _([[
Norinori — Rules

Shade some cells of the grid.

• Every outlined region contains exactly two shaded cells.
• Every shaded cell touches exactly one other shaded cell, side by side: the shaded cells form dominoes (pairs), never longer lines or blobs.
• A domino may lie inside one region or straddle two, giving one cell to each.
• Dominoes may touch diagonally, never side by side.

Tap a cell to cycle: shaded → dot (sure to stay empty) → blank. Hold a cell to blank it.
A shaded cell that already breaks a rule is crossed out.
]])

local GAME_RULES_FR = [[
Norinori — Règles

Noircissez certaines cases de la grille.

• Chaque région délimitée contient exactement deux cases noires.
• Chaque case noire touche exactement une autre case noire par un côté : les cases noires forment des dominos (des paires), jamais de lignes plus longues ni de blocs.
• Un domino peut tenir dans une seule région ou chevaucher deux régions, une case dans chacune.
• Les dominos peuvent se toucher en diagonale, jamais par un côté.

Touchez une case pour alterner : noire → point (sûrement vide) → vide. Restez appuyé pour la vider.
Une case noire qui enfreint déjà une règle est barrée.
]]

local NorinoriScreen = ScreenBase:extend{
    -- Generation shows a progress bar only once it has run this long, so
    -- the usual quick one shows nothing.
    progress_delay_ms = 200,
}

-- Generation runs synchronously, so nothing would repaint while it works
-- (seconds for a big grid on an e-reader). As in sudoku-common's
-- base_screen, the generator's progress callback drives a ProgressbarDialog,
-- which forces its own repaints. The callback only reads the clock to decide
-- whether to show the dialog; the generator never does, so the grid (and the
-- Daily Challenge's) does not depend on how fast the device is.
function NorinoriScreen:generateBoard(board)
    local start = time.now()
    local dialog
    board:generate(function(fraction)
        if not dialog then
            if time.to_ms(time.since(start)) < self.progress_delay_ms then return end
            dialog = ProgressbarDialog:new{
                title                = _("Generating puzzle…"),
                progress_max         = 1,
                refresh_time_seconds = 0.15,
                dismissable          = false,
            }
            dialog:show()
        end
        dialog:reportProgress(fraction)
    end)
    if dialog then dialog:close() end
end

function NorinoriScreen:init()
    local state = self.plugin:loadState()
    self.board  = NorinoriBoard:new{
        n          = self.plugin:getSetting("grid_n", NorinoriBoard.DEFAULT_N),
        difficulty = self.plugin:getSetting("difficulty", "easy"),
    }
    if not self.board:load(state) then
        self:generateBoard(self.board)
    end
    ScreenBase.init(self)
end

function NorinoriScreen:serializeState()
    return self.board:serialize()
end

function NorinoriScreen:buildLayout()
    local is_landscape = self:isLandscape()

    local title_bar = self:buildTitleBar(_("Norinori"), function()
        return {
            { text = _("New game"),               callback = function() self:onNewGame() end },
            self:makeDailyButtonConfig(),
            { text = self:getSizeButtonText(),    callback = function() self:openSizeMenu() end },
            { text = self:getDiffButtonText(),    callback = function() self:openDifficultyMenu() end },
            { text = self:getRevealButtonText(),  callback = function() self:toggleSolution() end },
            self:makeRulesButtonConfig(GAME_RULES_EN, GAME_RULES_FR),
        }
    end)

    -- Controls first: the board is sized from whatever room they leave.
    self.status_text:setMaxWidth(self:getControlsWidth())
    local action_bar = self:buildActionBar({
        { id = "undo_button", text = _("Undo"), callback = function() self:onUndo() end },
        { text = _("Hint"),    callback = function() self:onHint() end },
        { text = _("Restart"), callback = function() self:onRestart() end },
    })
    self.undo_button = action_bar:getButtonById("undo_button")
    local controls = VerticalGroup:new{
        align = "center",
        self.status_text,
        VerticalSpan:new{ width = Size.span.vertical_large },
        action_bar,
    }

    -- The widget draws its own thick outer border, so the frame only pads.
    local frame_pad   = Size.padding.large
    local frame_extra = 2 * frame_pad
    local budget_w, budget_h = self:getBoardBudget(title_bar, controls)
    self.board_widget = NorinoriBoardWidget:new{
        board        = self.board,
        max_size     = math.min(budget_w, budget_h) - frame_extra,
        onCellAction = function(r, c, is_hold) self:onCellAction(r, c, is_hold) end,
    }
    local board_frame = FrameContainer:new{
        padding    = frame_pad,
        margin     = 0,
        bordersize = 0,
        self.board_widget,
    }
    self:_updateUndoButton()

    if is_landscape then
        local content = HorizontalGroup:new{
            align = "center",
            board_frame,
            HorizontalSpan:new{ width = self:getGutter() },
            controls,
        }
        self:buildLandscapeLayout(title_bar, content)
    else
        self:buildPortraitLayout(title_bar, board_frame,
            VerticalGroup:new{ align = "center", controls, VerticalSpan:new{ width = self:getGutter() } })
    end
    self:updateStatus()
end

-- Anything that changed the marks: save, redraw, and let the action bar
-- swap to "New game" if the puzzle just got solved.
function NorinoriScreen:_afterMove()
    self.plugin:saveState(self.board:serialize())
    self:_updateUndoButton()
    self.board_widget:refresh()
    self:updateStatus()
    self:refreshActionBar()
end

function NorinoriScreen:onCellAction(r, c, is_hold)
    if self.board:isShowingSolution() then
        self:updateStatus(_("Hide the solution to keep playing."))
        return
    end
    local ok
    if is_hold then
        ok = self.board:setMark(r, c, NorinoriBoard.MARK_EMPTY)
    else
        ok = self.board:cycleCell(r, c)
    end
    if ok then self:_afterMove() end
end

function NorinoriScreen:onUndo()
    if self.board:undoMove() then self:_afterMove() end
end

function NorinoriScreen:onRestart()
    if self.board:clearAll() then self:_afterMove() end
end

function NorinoriScreen:isRoundOver()
    return self.board:isSolved()
end

-- A hint can place the last cell, so the round may end here.
function NorinoriScreen:onHint()
    ScreenBase.onHint(self)
    self:_updateUndoButton()
    self:refreshActionBar()
end

function NorinoriScreen:onNewGame()
    self.board = NorinoriBoard:new{
        n          = self.plugin:getSetting("grid_n", NorinoriBoard.DEFAULT_N),
        difficulty = self.plugin:getSetting("difficulty", "easy"),
    }
    self:generateBoard(self.board)
    self.hint_cell = nil
    self.plugin:saveState(self.board:serialize())
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

function NorinoriScreen:toggleSolution()
    self.board:toggleSolution()
    self.board_widget:refresh()
    self:_updateUndoButton()
    self:updateStatus()
end

function NorinoriScreen:openSizeMenu()
    local sizes = {}
    for _, n in ipairs(NorinoriBoard.SIZES) do
        sizes[#sizes + 1] = { id = n, text = n .. "\xC3\x97" .. n }
    end
    MenuHelper.openSizeMenu{
        title     = _("Select size"),
        sizes     = sizes,
        current   = self.plugin:getSetting("grid_n", NorinoriBoard.DEFAULT_N),
        parent    = self,
        on_select = function(n)
            self.plugin:saveSetting("grid_n", n)
            self:onNewGame()
        end,
    }
end

function NorinoriScreen:openDifficultyMenu()
    MenuHelper.openDifficultyMenu{
        current   = self.plugin:getSetting("difficulty", "easy"),
        parent    = self,
        on_select = function(id)
            self.plugin:saveSetting("difficulty", id)
            self:onNewGame()
        end,
    }
end

function NorinoriScreen:updateStatus(msg)
    local status
    if msg then
        status = msg
    elseif self.board:isShowingSolution() then
        status = _("Solution is shown; editing is disabled.")
    elseif self.board:isSolved() then
        status = T(_("Solved! Time: %1"), self.board.timer:format())
    else
        local diff = self.board.difficulty
        status = self:joinStatus(
            T("%1×%1", self.board.n),
            MenuHelper.DIFFICULTY_LABELS[diff] or diff,
            T(_("Shaded: %1/%2"), self.board:countShaded(), self.board:totalShaded()))
    end
    ScreenBase.updateStatus(self, status)
end

function NorinoriScreen:getSizeButtonText()
    return T(_("Size: %1"), self.board.n .. "\xC3\x97" .. self.board.n)
end

function NorinoriScreen:getDiffButtonText()
    local diff = self.plugin:getSetting("difficulty", "easy")
    return T(_("Difficulty: %1"), MenuHelper.DIFFICULTY_LABELS[diff] or diff)
end

function NorinoriScreen:getRevealButtonText()
    return self.board:isShowingSolution() and _("Hide solution") or _("Show solution")
end

function NorinoriScreen:_updateUndoButton()
    if not self.undo_button then return end
    self.undo_button:enableDisable(self.board:canUndo())
end

return NorinoriScreen
