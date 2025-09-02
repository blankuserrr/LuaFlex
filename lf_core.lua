-- LuaFlex: A performant and portable Lua layout engine that conforms to the FlexBox specification
-- Inspired by Facebook's Yoga

-- Performance: Localize frequently used globals
local max, min, abs, floor, huge = math.max, math.min, math.abs, math.floor, math.huge
local insert = table.insert

local LuaFlex = {}

-- Object pool for reducing GC pressure during layout calculations
-- Removed object pooling: premature optimization and added complexity

-- Enums for flexbox properties
LuaFlex.FlexDirection = {
    Column = "column",
    ColumnReverse = "column-reverse", 
    Row = "row",
    RowReverse = "row-reverse"
}

-- Performance: Internal numeric constants for hot-path comparisons
local FLEX_DIRECTION = {
    COLUMN = 1,
    COLUMN_REVERSE = 2,
    ROW = 3,
    ROW_REVERSE = 4
}

-- Helper to convert flex direction string to numeric for performance
local function flexDirectionToNum(dir)
    if dir == LuaFlex.FlexDirection.Column then return FLEX_DIRECTION.COLUMN
    elseif dir == LuaFlex.FlexDirection.ColumnReverse then return FLEX_DIRECTION.COLUMN_REVERSE
    elseif dir == LuaFlex.FlexDirection.Row then return FLEX_DIRECTION.ROW
    elseif dir == LuaFlex.FlexDirection.RowReverse then return FLEX_DIRECTION.ROW_REVERSE
    else return FLEX_DIRECTION.ROW -- default
    end
end

LuaFlex.JustifyContent = {
    FlexStart = "flex-start",
    FlexEnd = "flex-end",
    Center = "center",
    SpaceBetween = "space-between",
    SpaceAround = "space-around",
    SpaceEvenly = "space-evenly",
    -- Box Alignment L3
    Start = "start",
    End = "end",
    Left = "left",
    Right = "right",
    Normal = "normal"
}

LuaFlex.AlignItems = {
    FlexStart = "flex-start",
    FlexEnd = "flex-end",
    Center = "center",
    Stretch = "stretch",
    Baseline = "baseline",
    -- Box Alignment L3
    Start = "start",
    End = "end",
    SelfStart = "self-start",
    SelfEnd = "self-end",
    Normal = "normal"
}

LuaFlex.AlignSelf = {
    Auto = "auto",
    FlexStart = "flex-start",
    FlexEnd = "flex-end",
    Center = "center",
    Stretch = "stretch",
    Baseline = "baseline",
    -- Box Alignment L3
    Start = "start",
    End = "end",
    SelfStart = "self-start",
    SelfEnd = "self-end",
    Normal = "normal"
}

LuaFlex.AlignContent = {
    FlexStart = "flex-start",
    FlexEnd = "flex-end",
    Center = "center",
    Stretch = "stretch",
    SpaceBetween = "space-between",
    SpaceAround = "space-around",
    SpaceEvenly = "space-evenly",
    -- Box Alignment L3
    Start = "start",
    End = "end",
    Normal = "normal"
}

LuaFlex.FlexWrap = {
    NoWrap = "nowrap",
    Wrap = "wrap",
    WrapReverse = "wrap-reverse"
}

LuaFlex.PositionType = {
    Static = "static",
    Relative = "relative",
    Absolute = "absolute"
}

LuaFlex.Display = {
    Flex = "flex",
    None = "none"
}

-- Value types for dimensions
LuaFlex.ValueType = {
    Undefined = "undefined",
    Point = "point",
    Percent = "percent",
    Auto = "auto",
    Content = "content"
}

-- Helper function to create a value with type
local function createValue(value, valueType)
    return {
        value = value or 0,
        type = valueType or LuaFlex.ValueType.Undefined
    }
end

-- Helper function to parse dimension values from various types
local function parseDimension(val)
    if val == nil then
        return createValue(nil, LuaFlex.ValueType.Undefined)
    end
    local t = type(val)
    if t == "number" then
        return createValue(val, LuaFlex.ValueType.Point)
    elseif t == "string" then
        if val == "auto" then
            return createValue(nil, LuaFlex.ValueType.Auto)
        elseif val == "content" then
            return createValue(nil, LuaFlex.ValueType.Content)
        end
        local pct = string.match(val, "^(%-?%d+%.?%d*)%%$")
        if pct then
            return createValue(tonumber(pct), LuaFlex.ValueType.Percent)
        end
        local num = tonumber(val)
        if num then
            return createValue(num, LuaFlex.ValueType.Point)
        end
    end
    return createValue(nil, LuaFlex.ValueType.Undefined)
end

-- Unified value resolution function that returns (num, definite) or (nil, false)
-- This replaces the old numeric/resolveValue functions and properly handles indefinite percentages
local function resolveLength(value, basis)
    if value.type == LuaFlex.ValueType.Point then
        return value.value, true
    elseif value.type == LuaFlex.ValueType.Percent then
        if basis ~= nil and basis ~= math.huge and basis >= 0 then
            return (value.value / 100) * basis, true
        else
            return nil, false -- percent of indefinite size => indefinite
        end
    end
    return nil, false -- Auto/Content/Undefined are indefinite
end

-- Legacy numeric function for gradual migration - use resolveLength in new code
local function numeric(value, basis)
    local resolved = resolveLength(value, basis)
    return resolved or 0
end

-- Node class representing a flex container/item
LuaFlex.Node = {}
LuaFlex.Node.__index = LuaFlex.Node

function LuaFlex.Node.new(props)
    local node = {
        -- Style properties
        flexDirection = LuaFlex.FlexDirection.Row,
        justifyContent = LuaFlex.JustifyContent.FlexStart,
        alignItems = LuaFlex.AlignItems.Stretch,
        alignSelf = LuaFlex.AlignSelf.Auto,
        alignContent = LuaFlex.AlignContent.Stretch,
        justifyItems = "legacy", -- Not applicable to flex items, but used for abs-pos
        justifySelf = "auto", -- Not applicable to flex items, but used for abs-pos
        alignItemsSafety = "unsafe",
        alignSelfSafety = "unsafe",
        alignContentSafety = "unsafe",
        flexWrap = LuaFlex.FlexWrap.NoWrap,
        positionType = LuaFlex.PositionType.Static,
        display = LuaFlex.Display.Flex,
        order = 0,
        direction = "ltr",
        writingMode = "horizontal-tb",
        aspectRatio = nil,
        
        -- Flex properties
        flexGrow = 0,
        flexShrink = 1,
        flexBasis = createValue(nil, LuaFlex.ValueType.Auto),
        
        -- Dimensions
        width = createValue(),
        height = createValue(),
        minWidth = createValue(nil, LuaFlex.ValueType.Auto),
        minHeight = createValue(nil, LuaFlex.ValueType.Auto),
        maxWidth = createValue(),
        maxHeight = createValue(),
        
        -- Position
        left = createValue(),
        top = createValue(),
        right = createValue(),
        bottom = createValue(),
        
        -- Margin
        marginLeft = createValue(),
        marginTop = createValue(),
        marginRight = createValue(),
        marginBottom = createValue(),
        
        -- Padding
        paddingLeft = createValue(),
        paddingTop = createValue(),
        paddingRight = createValue(),
        paddingBottom = createValue(),
        
        -- Gap
        rowGap = createValue(),
        columnGap = createValue(),
        
        -- Border
        borderLeft = createValue(),
        borderTop = createValue(),
        borderRight = createValue(),
        borderBottom = createValue(),
        
        -- Layout results (computed)
        layout = {
            left = 0,
            top = 0,
            width = 0,
            height = 0,
            direction = LuaFlex.FlexDirection.Row,
            -- Baseline information per CSS spec 8.5
            firstBaseline = nil,  -- Distance from top of margin box to first baseline
            lastBaseline = nil    -- Distance from top of margin box to last baseline
        },
        
        -- Tree structure
        parent = nil,
        children = {},
        
        -- Internal flags
        isDirty = true,
        
        -- Measurement function for content sizing
        measureFunc = nil,
        
        -- Baseline function for text alignment
        baselineFunc = nil,
        
        -- Cached intrinsic size
        intrinsicSize = {
            width = 0,
            height = 0,
            hasIntrinsicWidth = false,
            hasIntrinsicHeight = false
        },
        
        -- Cached baseline information
        baseline = {
            position = 0,
            hasBaseline = false
        },
        
        -- Internal state for batching updates
        _suspendDirty = false
    }
    
    node = setmetatable(node, LuaFlex.Node)
    
    if props and type(props) == "table" then
        -- Simple property initializer; does not call setters to avoid dirty propagation during construction
        
        -- Data-driven property initialization
        local propertyMap = {
            -- Direct value properties
            flexDirection = "flexDirection",
            justifyContent = "justifyContent", 
            alignItems = "alignItems",
            alignSelf = "alignSelf",
            alignContent = "alignContent",
            flexWrap = "flexWrap",
            positionType = "positionType",
            display = "display",
            order = "order",
            flexGrow = "flexGrow",
            flexShrink = "flexShrink",
            
            -- Dimension properties (need parsing)
            flexBasis = "flexBasis_parsed",
            width = "width_parsed",
            height = "height_parsed", 
            minWidth = "minWidth_parsed",
            minHeight = "minHeight_parsed",
            maxWidth = "maxWidth_parsed",
            maxHeight = "maxHeight_parsed",
            rowGap = "rowGap_parsed",
            columnGap = "columnGap_parsed"
        }
        
        -- Apply direct and parsed properties
        for propKey, nodeKey in pairs(propertyMap) do
            local value = props[propKey]
            if value ~= nil then
                if nodeKey:match("_parsed$") then
                    -- Parse dimension value
                    local realNodeKey = nodeKey:gsub("_parsed$", "")
                    node[realNodeKey] = parseDimension(value)
                else
                    -- Direct assignment
                    node[nodeKey] = value
                end
            end
        end
        
        -- Handle shorthand properties
        if props.margin then
            local marginValue = parseDimension(props.margin)
            node.marginTop = marginValue
            node.marginRight = marginValue
            node.marginBottom = marginValue
            node.marginLeft = marginValue
        end
        
        if props.padding then
            local paddingValue = parseDimension(props.padding)
            node.paddingTop = paddingValue
            node.paddingRight = paddingValue
            node.paddingBottom = paddingValue
            node.paddingLeft = paddingValue
        end
        
        if props.gap then
            local gapValue = parseDimension(props.gap)
            node.rowGap = gapValue
            node.columnGap = gapValue
        end
    end
    
    return node
end

-- Style setter methods
function LuaFlex.Node:setFlexDirection(direction)
    if self.flexDirection ~= direction then
        self.flexDirection = direction
        if not self._suspendDirty then self:markDirty() end
    end
    return self
end

function LuaFlex.Node:setJustifyContent(justify)
    if self.justifyContent ~= justify then
        self.justifyContent = justify
        if not self._suspendDirty then self:markDirty() end
    end
    return self
end

function LuaFlex.Node:setAlignItems(align)
    if self.alignItems ~= align then
        self.alignItems = align
        if not self._suspendDirty then self:markDirty() end
    end
    return self
end

function LuaFlex.Node:setAlignSelf(align)
    if self.alignSelf ~= align then
        self.alignSelf = align
        if not self._suspendDirty then self:markDirty() end
    end
    return self
end

function LuaFlex.Node:setFlexWrap(wrap)
    if self.flexWrap ~= wrap then
        self.flexWrap = wrap
        if not self._suspendDirty then self:markDirty() end
    end
    return self
end

function LuaFlex.Node:setAlignContent(align, safety)
    if self.alignContent ~= align then
        self.alignContent = align
        if not self._suspendDirty then self:markDirty() end
    end
    if safety then self:setAlignContentSafety(safety) end
    return self
end

function LuaFlex.Node:setAlignItemsSafety(safety)
    if self.alignItemsSafety ~= safety then
        self.alignItemsSafety = safety
        if not self._suspendDirty then self:markDirty() end
    end
    return self
end

function LuaFlex.Node:setAlignSelfSafety(safety)
    if self.alignSelfSafety ~= safety then
        self.alignSelfSafety = safety
        if not self._suspendDirty then self:markDirty() end
    end
    return self
end

function LuaFlex.Node:setAlignContentSafety(safety)
    if self.alignContentSafety ~= safety then
        self.alignContentSafety = safety
        if not self._suspendDirty then self:markDirty() end
    end
    return self
end

function LuaFlex.Node:setFlexGrow(grow)
    -- Input validation: flex-grow must be non-negative number
    if type(grow) ~= "number" or grow < 0 or grow ~= grow then -- check for NaN
        error("flex-grow must be a non-negative number")
    end
    
    if self.flexGrow ~= grow then
        self.flexGrow = grow
        if not self._suspendDirty then self:markDirty() end
    end
    return self
end

function LuaFlex.Node:setFlexShrink(shrink)
    -- Input validation: flex-shrink must be non-negative number
    if type(shrink) ~= "number" or shrink < 0 or shrink ~= shrink then -- check for NaN
        error("flex-shrink must be a non-negative number")
    end
    
    if self.flexShrink ~= shrink then
        self.flexShrink = shrink
        if not self._suspendDirty then self:markDirty() end
    end
    return self
end

function LuaFlex.Node:setFlexBasis(basis)
    local newBasis = parseDimension(basis)
    if self.flexBasis.value ~= newBasis.value or self.flexBasis.type ~= newBasis.type then
        self.flexBasis = newBasis
        if not self._suspendDirty then self:markDirty() end
    end
    return self
end

-- Dimension setters
function LuaFlex.Node:setWidth(width)
    local newWidth = parseDimension(width)
    if self.width.value ~= newWidth.value or self.width.type ~= newWidth.type then
        self.width = newWidth
        if not self._suspendDirty then self:markDirty() end
    end
    return self
end

function LuaFlex.Node:setHeight(height)
    local newHeight = parseDimension(height)
    if self.height.value ~= newHeight.value or self.height.type ~= newHeight.type then
        self.height = newHeight
        if not self._suspendDirty then self:markDirty() end
    end
    return self
end

function LuaFlex.Node:setMinWidth(minWidth)
    local v = parseDimension(minWidth)
    if self.minWidth.value ~= v.value or self.minWidth.type ~= v.type then
        self.minWidth = v
        if not self._suspendDirty then self:markDirty() end
    end
    return self
end

function LuaFlex.Node:setMinHeight(minHeight)
    local v = parseDimension(minHeight)
    if self.minHeight.value ~= v.value or self.minHeight.type ~= v.type then
        self.minHeight = v
        if not self._suspendDirty then self:markDirty() end
    end
    return self
end

function LuaFlex.Node:setMaxWidth(maxWidth)
    local v = parseDimension(maxWidth)
    if self.maxWidth.value ~= v.value or self.maxWidth.type ~= v.type then
        self.maxWidth = v
        if not self._suspendDirty then self:markDirty() end
    end
    return self
end

function LuaFlex.Node:setMaxHeight(maxHeight)
    local v = parseDimension(maxHeight)
    if self.maxHeight.value ~= v.value or self.maxHeight.type ~= v.type then
        self.maxHeight = v
        if not self._suspendDirty then self:markDirty() end
    end
    return self
end

-- Margin setters
function LuaFlex.Node:setMargin(top, right, bottom, left)
    self:setMarginTop(parseDimension(top))
    self:setMarginRight(parseDimension(right or top))
    self:setMarginBottom(parseDimension(bottom or top))
    self:setMarginLeft(parseDimension(left or right or top))
    return self
end

function LuaFlex.Node:setMarginTop(newMargin)
    if self.marginTop.value ~= newMargin.value or self.marginTop.type ~= newMargin.type then
        self.marginTop = newMargin
        if not self._suspendDirty then self:markDirty() end
    end
    return self
end

function LuaFlex.Node:setMarginRight(newMargin)
    if self.marginRight.value ~= newMargin.value or self.marginRight.type ~= newMargin.type then
        self.marginRight = newMargin
        if not self._suspendDirty then self:markDirty() end
    end
    return self
end

function LuaFlex.Node:setMarginBottom(newMargin)
    if self.marginBottom.value ~= newMargin.value or self.marginBottom.type ~= newMargin.type then
        self.marginBottom = newMargin
        if not self._suspendDirty then self:markDirty() end
    end
    return self
end

function LuaFlex.Node:setMarginLeft(newMargin)
    if self.marginLeft.value ~= newMargin.value or self.marginLeft.type ~= newMargin.type then
        self.marginLeft = newMargin
        if not self._suspendDirty then self:markDirty() end
    end
    return self
end

-- Padding setters
function LuaFlex.Node:setPadding(top, right, bottom, left)
    self:setPaddingTop(parseDimension(top))
    self:setPaddingRight(parseDimension(right or top))
    self:setPaddingBottom(parseDimension(bottom or top))
    self:setPaddingLeft(parseDimension(left or right or top))
    return self
end

function LuaFlex.Node:setPaddingTop(newPadding)
    if self.paddingTop.value ~= newPadding.value or self.paddingTop.type ~= newPadding.type then
        self.paddingTop = newPadding
        if not self._suspendDirty then self:markDirty() end
    end
    return self
end

function LuaFlex.Node:setPaddingRight(newPadding)
    if self.paddingRight.value ~= newPadding.value or self.paddingRight.type ~= newPadding.type then
        self.paddingRight = newPadding
        if not self._suspendDirty then self:markDirty() end
    end
    return self
end

function LuaFlex.Node:setPaddingBottom(newPadding)
    if self.paddingBottom.value ~= newPadding.value or self.paddingBottom.type ~= newPadding.type then
        self.paddingBottom = newPadding
        if not self._suspendDirty then self:markDirty() end
    end
    return self
end

function LuaFlex.Node:setPaddingLeft(newPadding)
    if self.paddingLeft.value ~= newPadding.value or self.paddingLeft.type ~= newPadding.type then
        self.paddingLeft = newPadding
        if not self._suspendDirty then self:markDirty() end
    end
    return self
end

-- Gap setters
function LuaFlex.Node:setGap(v)
    if type(v) == "string" then
        local a,b = v:match("^%s*(%S+)%s*(%S*)%s*$")
        if a then
            local g1 = parseDimension(a)
            local g2 = b and b ~= "" and parseDimension(b) or g1
            local changed = (self.rowGap.type ~= g1.type or self.rowGap.value ~= g1.value) or
                            (self.columnGap.type ~= g2.type or self.columnGap.value ~= g2.value)
            if changed then
                self.rowGap, self.columnGap = g1, g2
                if not self._suspendDirty then self:markDirty() end
            end
        end
        return self
    end

    -- Fallback for numbers or single value tables
    local p = parseDimension(v)
    if (self.rowGap.type ~= p.type or self.rowGap.value ~= p.value) or
       (self.columnGap.type ~= p.type or self.columnGap.value ~= p.value) then
        self.rowGap = p
        self.columnGap = p
        if not self._suspendDirty then self:markDirty() end
    end
    return self
end

function LuaFlex.Node:setRowGap(gap)
    local v = parseDimension(gap)
    if self.rowGap.type ~= v.type or self.rowGap.value ~= v.value then
        self.rowGap = v
        if not self._suspendDirty then self:markDirty() end
    end
    return self
end

function LuaFlex.Node:setColumnGap(gap)
    local v = parseDimension(gap)
    if self.columnGap.type ~= v.type or self.columnGap.value ~= v.value then
        self.columnGap = v
        if not self._suspendDirty then self:markDirty() end
    end
    return self
end

-- Position setters
function LuaFlex.Node:setPosition(top, right, bottom, left)
    if top then 
        self:setTop(parseDimension(top)) 
    end
    if right then 
        self:setRight(parseDimension(right)) 
    end
    if bottom then 
        self:setBottom(parseDimension(bottom)) 
    end
    if left then 
        self:setLeft(parseDimension(left)) 
    end
    return self
end

function LuaFlex.Node:setTop(newTop)
    if self.top.value ~= newTop.value or self.top.type ~= newTop.type then
        self.top = newTop
        if not self._suspendDirty then self:markDirty() end
    end
    return self
end

function LuaFlex.Node:setRight(newRight)
    if self.right.value ~= newRight.value or self.right.type ~= newRight.type then
        self.right = newRight
        if not self._suspendDirty then self:markDirty() end
    end
    return self
end

function LuaFlex.Node:setBottom(newBottom)
    if self.bottom.value ~= newBottom.value or self.bottom.type ~= newBottom.type then
        self.bottom = newBottom
        if not self._suspendDirty then self:markDirty() end
    end
    return self
end

function LuaFlex.Node:setLeft(newLeft)
    if self.left.value ~= newLeft.value or self.left.type ~= newLeft.type then
        self.left = newLeft
        if not self._suspendDirty then self:markDirty() end
    end
    return self
end

function LuaFlex.Node:setPositionType(positionType)
    if self.positionType ~= positionType then
        self.positionType = positionType
        if not self._suspendDirty then self:markDirty() end
    end
    return self
end

function LuaFlex.Node:setDisplay(display)
    if self.display ~= display then
        self.display = display
        if not self._suspendDirty then self:markDirty() end
    end
    return self
end

function LuaFlex.Node:setOrder(order)
    -- Input validation: order must be integer (browsers treat as integer)
    if type(order) ~= "number" or order ~= order then -- check for NaN
        error("order must be a number")
    end
    
    -- Round to nearest integer for consistent behavior
    order = floor(order + 0.5)
    
    if self.order ~= order then
        self.order = order
        -- Order changes affect the parent's layout, not just this node
        if self.parent then
            if not self._suspendDirty then self.parent:markDirty() end
        end
    end
    return self
end

function LuaFlex.Node:setDirection(direction)
    if self.direction ~= direction then
        self.direction = direction
        if not self._suspendDirty then self:markDirty() end
    end
    return self
end

function LuaFlex.Node:setWritingMode(writingMode)
    if self.writingMode ~= writingMode then
        self.writingMode = writingMode
        if not self._suspendDirty then self:markDirty() end
    end
    return self
end

function LuaFlex.Node:setAspectRatio(ratio)
    local newRatio = nil
    if type(ratio) == "number" and ratio > 0 then
        newRatio = ratio
    elseif type(ratio) == "string" then
        local w, h = ratio:match("^(%d+%.?%d*)%s*/%s*(%d+%.?%d*)$")
        if w and h and tonumber(h) > 0 then
            newRatio = tonumber(w) / tonumber(h)
        end
    end

    if self.aspectRatio ~= newRatio then
        self.aspectRatio = newRatio
        if not self._suspendDirty then self:markDirty() end
    end
    return self
end

-- Batch style updates to avoid repeated dirty propagation
function LuaFlex.Node:batch(fn)
    local prev = self._suspendDirty
    self._suspendDirty = true
    fn(self)
    self._suspendDirty = prev
    if not self._suspendDirty then self:markDirty() end
    return self
end

-- Set a custom measure function for intrinsic content sizing
-- measureFunc should be a function(node, availableWidth, availableHeight) -> measuredWidth, measuredHeight
function LuaFlex.Node:setMeasureFunc(measureFunc)
    self.measureFunc = measureFunc
    if not self._suspendDirty then self:markDirty() end
    return self
end

-- Set a custom baseline function for text alignment
-- baselineFunc should be a function(node, width, height) -> baselinePosition
-- baselinePosition is the distance from the top of the content area to the text baseline
function LuaFlex.Node:setBaselineFunc(baselineFunc)
    self.baselineFunc = baselineFunc
    self:invalidateBaseline()
    return self
end

-- Invalidate cached intrinsic size
function LuaFlex.Node:invalidateIntrinsicSize()
    self.intrinsicSize.hasIntrinsicWidth = false
    self.intrinsicSize.hasIntrinsicHeight = false
    if self.parent then
        self.parent:invalidateIntrinsicSize()
    end
end

-- Invalidate cached baseline
function LuaFlex.Node:invalidateBaseline()
    self.baseline.hasBaseline = false
    -- Clear layout baselines too since they depend on child layout
    self.layout.firstBaseline = nil
    self.layout.lastBaseline = nil
    if self.parent then
        self.parent:invalidateBaseline()
    end
end

-- Helper methods
function LuaFlex.Node:markDirty()
    if not self.isDirty then
        self.isDirty = true
        self:invalidateIntrinsicSize()
        self:invalidateBaseline()
        if self.parent then
            if not self._suspendDirty then self.parent:markDirty() end
        end
    end
end

function LuaFlex.Node:isFlexDirectionRow()
    local dir = flexDirectionToNum(self.flexDirection)
    return dir == FLEX_DIRECTION.ROW or dir == FLEX_DIRECTION.ROW_REVERSE
end

function LuaFlex.Node:isFlexDirectionColumn()
    local dir = flexDirectionToNum(self.flexDirection)
    return dir == FLEX_DIRECTION.COLUMN or dir == FLEX_DIRECTION.COLUMN_REVERSE
end

function LuaFlex.Node:isFlexDirectionReverse()
    local dir = flexDirectionToNum(self.flexDirection)
    return dir == FLEX_DIRECTION.ROW_REVERSE or dir == FLEX_DIRECTION.COLUMN_REVERSE
end

function LuaFlex.Node:isInlineAxisHorizontal()
    return self.writingMode == "horizontal-tb"
end

function LuaFlex.Node:isInlineReverse()
    return self.direction == "rtl" and self:isInlineAxisHorizontal()
end

function LuaFlex.Node:isMainAxisReversed()
    if self.flexDirection == LuaFlex.FlexDirection.Row then
        return self:isInlineReverse()
    elseif self.flexDirection == LuaFlex.FlexDirection.RowReverse then
        return not self:isInlineReverse()
    elseif self.flexDirection == LuaFlex.FlexDirection.Column then
        return false -- columns use block flow direction
    else -- ColumnReverse
        return true
    end
end

-- Tree manipulation
function LuaFlex.Node:appendChild(child)
    if child.parent then
        child.parent:removeChild(child)
    end
    
    child.parent = self
    table.insert(self.children, child)
    self:markDirty()
    return self
end

function LuaFlex.Node:removeChild(child)
    for i, c in ipairs(self.children) do
        if c == child then
            table.remove(self.children, i)
            child.parent = nil
            self:markDirty()
            break
        end
    end
    return self
end

function LuaFlex.Node:getChildCount()
    return #self.children
end

function LuaFlex.Node:getChild(index)
    return self.children[index]
end

-- Layout getters
function LuaFlex.Node:getComputedLeft()
    return self.layout.left
end

function LuaFlex.Node:getComputedTop()
    return self.layout.top
end

function LuaFlex.Node:getComputedWidth()
    return self.layout.width
end

function LuaFlex.Node:getComputedHeight()
    return self.layout.height
end

-- Forward declaration for calculateIntrinsicSize to resolve linter warning
local calculateIntrinsicSize

-- Resolves Box Alignment L3 keywords to their flexbox equivalents for a given axis direction
local function resolveJustifyContent(justify, container)
    if justify == LuaFlex.JustifyContent.Start then return LuaFlex.JustifyContent.FlexStart end
    if justify == LuaFlex.JustifyContent.End then return LuaFlex.JustifyContent.FlexEnd end
    if justify == LuaFlex.JustifyContent.Normal then return LuaFlex.JustifyContent.FlexStart end
    if justify == LuaFlex.JustifyContent.Left then
        return container:isInlineReverse() and LuaFlex.JustifyContent.FlexEnd or LuaFlex.JustifyContent.FlexStart
    end
    if justify == LuaFlex.JustifyContent.Right then
        return container:isInlineReverse() and LuaFlex.JustifyContent.FlexStart or LuaFlex.JustifyContent.FlexEnd
    end
    return justify
end

local function resolveAlign(align)
    if align == LuaFlex.AlignItems.Start or align == LuaFlex.AlignItems.SelfStart then return LuaFlex.AlignItems.FlexStart end
    if align == LuaFlex.AlignItems.End or align == LuaFlex.AlignItems.SelfEnd then return LuaFlex.AlignItems.FlexEnd end
    if align == LuaFlex.AlignItems.Normal then return LuaFlex.AlignItems.Stretch end -- `normal` for align-* is `stretch` in flexbox
    return align
end

local function resolveAlignContent(v)
    if v == LuaFlex.AlignContent.Start then return LuaFlex.AlignContent.FlexStart end
    if v == LuaFlex.AlignContent.End then return LuaFlex.AlignContent.FlexEnd end
    if v == LuaFlex.AlignContent.Normal then return LuaFlex.AlignContent.Stretch end
    return v
end

-- Clamps a child's position to prevent overflow if 'safe' alignment is used
local function clampSafe(pos, size, lineStart, lineSize)
    if pos < lineStart then return lineStart end
    if pos + size > lineStart + lineSize then return math.max(lineStart, lineStart + lineSize - size) end
    return pos
end

-- Helper function to get the inline size of a node based on its writing mode
local function inlineSizeOf(node)
    if node:isInlineAxisHorizontal() then
        return node.layout.width
    else
        return node.layout.height
    end
end

-- Helper function to set main axis position, handling reverse directions
local function setMainAxisPosition(child, offsetFromMainStart, size,
                                   container, mainStartOffset, innerMainSize)
    local isRow = container:isFlexDirectionRow()
    if container:isMainAxisReversed() then
        local mirror = mainStartOffset + (innerMainSize - (offsetFromMainStart - mainStartOffset) - size)
        if isRow then child.layout.left = mirror else child.layout.top = mirror end
    else
        if isRow then child.layout.left = offsetFromMainStart else child.layout.top = offsetFromMainStart end
    end
end

-- Helper function to set cross axis position
local function setCrossAxisPosition(container, child, position)
    if container:isFlexDirectionRow() then
        child.layout.top = position
    else
        child.layout.left = position
    end
end

-- Axis helper structure to reduce branching and simplify main/cross axis operations
local function createAxisInfo(container, contentWidth, contentHeight, padding, border)
    local isMainAxisRow = container:isFlexDirectionRow()
    
    local axis = {
        isMainAxisRow = isMainAxisRow,
        
        -- Size properties
        mainSizeProp = isMainAxisRow and "width" or "height",
        crossSizeProp = isMainAxisRow and "height" or "width",
        
        -- Min/max properties
        minMainProp = isMainAxisRow and "minWidth" or "minHeight",
        maxMainProp = isMainAxisRow and "maxWidth" or "maxHeight",
        minCrossProp = isMainAxisRow and "minHeight" or "minWidth",
        maxCrossProp = isMainAxisRow and "maxHeight" or "maxWidth",
        
        -- Available sizes
        availableMainSize = isMainAxisRow and contentWidth or contentHeight,
        availableCrossSize = isMainAxisRow and contentHeight or contentWidth,
        
        -- Start offsets
        mainStartOffset = isMainAxisRow and (padding.left + border.left) or (padding.top + border.top),
        crossStartOffset = isMainAxisRow and (padding.top + border.top) or (padding.left + border.left),
        
        -- Margin properties
        marginMainStartProp = isMainAxisRow and "marginLeft" or "marginTop",
        marginMainEndProp = isMainAxisRow and "marginRight" or "marginBottom",
        marginCrossStartProp = isMainAxisRow and "marginTop" or "marginLeft",
        marginCrossEndProp = isMainAxisRow and "marginBottom" or "marginRight",
        
        -- Gap properties
        mainAxisGapProp = isMainAxisRow and "columnGap" or "rowGap",
        crossAxisGapProp = isMainAxisRow and "rowGap" or "columnGap",
        
        -- Position properties
        mainStartPosProp = isMainAxisRow and "left" or "top",
        mainEndPosProp = isMainAxisRow and "right" or "bottom",
        crossStartPosProp = isMainAxisRow and "top" or "left",
        crossEndPosProp = isMainAxisRow and "bottom" or "right"
    }
    
    -- Helper functions for this axis configuration
    function axis:getMainSize(node)
        return self.isMainAxisRow and node.layout.width or node.layout.height
    end
    
    function axis:getCrossSize(node)
        return self.isMainAxisRow and node.layout.height or node.layout.width
    end
    
    function axis:setMainSize(node, size)
        if self.isMainAxisRow then
            node.layout.width = size
        else
            node.layout.height = size
        end
    end
    
    function axis:setCrossSize(node, size)
        if self.isMainAxisRow then
            node.layout.height = size
        else
            node.layout.width = size
        end
    end
    
    function axis:getMainPos(node)
        return self.isMainAxisRow and node.layout.left or node.layout.top
    end
    
    function axis:getCrossPos(node)
        return self.isMainAxisRow and node.layout.top or node.layout.left
    end
    
    function axis:setMainPos(node, pos)
        if self.isMainAxisRow then
            node.layout.left = pos
        else
            node.layout.top = pos
        end
    end
    
    function axis:setCrossPos(node, pos)
        if self.isMainAxisRow then
            node.layout.top = pos
        else
            node.layout.left = pos
        end
    end
    
    return axis
end

-- Apply aspect ratio transfer per CSS Sizing spec
local function applyAspectRatio(node, width, widthDef, height, heightDef, ar)
    if not ar or ar <= 0 then 
        return width, widthDef, height, heightDef 
    end
    
    if widthDef and not heightDef then
        return width, true, width / ar, true
    elseif heightDef and not widthDef then
        return height * ar, true, height, true
    end
    
    -- Both auto or both definite - no transfer
    return width, widthDef, height, heightDef
end

-- Calculate automatic minimum size for flex items (spec 4.5, 7.7)
local function autoMinMainSize(node, isMainAxisRow, availableMainSize, availableCrossSize)
    -- Use measured content size as a proxy for min-content size
    -- In a full implementation, this would be min-content, but measured size is a reasonable approximation
    local cw, ch = calculateIntrinsicSize(node, 
        isMainAxisRow and availableMainSize or availableCrossSize,
        isMainAxisRow and availableCrossSize or availableMainSize)
    
    -- Apply aspect ratio transfer to content size
    local arWidth, arHeight = cw, ch
    if node.aspectRatio and node.aspectRatio > 0 then
        arWidth, _, arHeight, _ = applyAspectRatio(node, cw, true, ch, true, node.aspectRatio)
    end
    
    return isMainAxisRow and arWidth or arHeight
end

-- Clamp a main-axis size against min/max constraints with proper auto min-size handling
local function clampMainAxis(node, isMainAxisRow, size, availableMainSize, availableCrossSize)
    local minConstraint = isMainAxisRow and node.minWidth or node.minHeight
    local maxConstraint = isMainAxisRow and node.maxWidth or node.maxHeight

    -- Resolve max constraint first
    local maxValResolved, maxDef = resolveLength(maxConstraint, availableMainSize)
    if maxDef and maxValResolved > 0 and size > maxValResolved then
        size = maxValResolved
    end
    
    -- Resolve min constraint with automatic minimum size support
    local minValResolved, minDef = resolveLength(minConstraint, availableMainSize)
    if not minDef and minConstraint.type == LuaFlex.ValueType.Auto then
        -- Auto min-size: use content-based minimum per spec
        minValResolved = autoMinMainSize(node, isMainAxisRow, availableMainSize, availableCrossSize or huge)
        minDef = true
    end

    if minDef and minValResolved > 0 and size < minValResolved then
        size = minValResolved
    end

    return size
end

-- Calculate the baseline position of a single item (leaf node)
local function calculateItemBaseline(node, width, height)
    -- If node has a custom baseline function, use it
    if node.baselineFunc then
        return node.baselineFunc(node, width, height)
    else
        -- Default: use the bottom of the content area as baseline
        local inlineSize = inlineSizeOf(node)
        local contentTop = numeric(node.paddingTop, inlineSize) + numeric(node.borderTop, 0)
        local contentHeight = height - 
                              numeric(node.paddingTop, inlineSize) - 
                              numeric(node.paddingBottom, inlineSize) - 
                              numeric(node.borderTop, 0) - numeric(node.borderBottom, 0)
        return contentTop + contentHeight
    end
end

-- Calculate the baseline position of a node (spec-compliant, line-aware for flex containers)
local function calculateBaseline(node)
    -- Return cached baseline if available
    if node.baseline.hasBaseline then
        return node.baseline.position
    end
    
    local baselinePosition = 0
    
    -- For flex containers, prefer the computed layout baseline if available
    if node.layout.firstBaseline ~= nil then
        baselinePosition = node.layout.firstBaseline
    elseif node.baselineFunc then
        -- Custom baseline function
        baselinePosition = node.baselineFunc(node, node.layout.width, node.layout.height)
    else
        -- Fallback: use bottom of content area
        baselinePosition = calculateItemBaseline(node, node.layout.width, node.layout.height)
    end
    
    -- Cache the result
    node.baseline.position = baselinePosition
    node.baseline.hasBaseline = true
    
    return baselinePosition
end

-- Get the baseline position of this node
function LuaFlex.Node:getBaseline()
    return calculateBaseline(self)
end

-- Get the first baseline of this flex container (distance from top of margin box)
function LuaFlex.Node:getFirstBaseline()
    return self.layout.firstBaseline
end

-- Get the last baseline of this flex container (distance from top of margin box)  
function LuaFlex.Node:getLastBaseline()
    return self.layout.lastBaseline
end

-- Forward declaration
local measureNode

-- Measure a flex container based on its children
local function measureFlexContainer(node, availableWidth, availableHeight)
    local isMainAxisRow = node:isFlexDirectionRow()
    local totalMainSize = 0
    local maxCrossSize = 0
    
    -- Account for padding and border
    local inlineSize = node:isInlineAxisHorizontal() and availableWidth or availableHeight
    local paddingLeft = numeric(node.paddingLeft, inlineSize)
    local paddingRight = numeric(node.paddingRight, inlineSize)
    local paddingTop = numeric(node.paddingTop, inlineSize)
    local paddingBottom = numeric(node.paddingBottom, inlineSize)
    local borderLeft = numeric(node.borderLeft, 0)
    local borderRight = numeric(node.borderRight, 0)
    local borderTop = numeric(node.borderTop, 0)
    local borderBottom = numeric(node.borderBottom, 0)
    
    local contentAvailableWidth = math.max(0, availableWidth - paddingLeft - paddingRight - borderLeft - borderRight)
    local contentAvailableHeight = math.max(0, availableHeight - paddingTop - paddingBottom - borderTop - borderBottom)
    
    -- Measure each child
    for _, child in ipairs(node.children) do
        if child.display ~= LuaFlex.Display.None and child.positionType ~= LuaFlex.PositionType.Absolute then
            local childWidth, childHeight = measureNode(child, contentAvailableWidth, contentAvailableHeight)
            
            -- Add margins
            local inlineSize = availableWidth
            local mls, mle, mcs, mce
            if isMainAxisRow then
                mls = numeric(child.marginLeft, inlineSize)
                mle = numeric(child.marginRight, inlineSize)
                mcs = numeric(child.marginTop, inlineSize)
                mce = numeric(child.marginBottom, inlineSize)
            else
                mls = numeric(child.marginTop, inlineSize)
                mle = numeric(child.marginBottom, inlineSize)
                mcs = numeric(child.marginLeft, inlineSize)
                mce = numeric(child.marginRight, inlineSize)
            end
            local childMainSize = (isMainAxisRow and childWidth or childHeight) + mls + mle
            local childCrossSize = (isMainAxisRow and childHeight or childWidth) + mcs + mce
            
            if node.flexWrap == LuaFlex.FlexWrap.NoWrap then
                -- Single line - add up main sizes
                totalMainSize = totalMainSize + childMainSize
                maxCrossSize = math.max(maxCrossSize, childCrossSize)
            else
                -- Multi-line - this is a simplified calculation
                -- In a real implementation, we'd need to simulate line breaking
                totalMainSize = math.max(totalMainSize, childMainSize)
                maxCrossSize = maxCrossSize + childCrossSize
            end
        end
    end
    
    local measuredWidth, measuredHeight
    if isMainAxisRow then
        measuredWidth = totalMainSize + paddingLeft + paddingRight + borderLeft + borderRight
        measuredHeight = maxCrossSize + paddingTop + paddingBottom + borderTop + borderBottom
    else
        measuredWidth = maxCrossSize + paddingLeft + paddingRight + borderLeft + borderRight
        measuredHeight = totalMainSize + paddingTop + paddingBottom + borderTop + borderBottom
    end
    
    return measuredWidth, measuredHeight
end

-- Perform measurement pass to calculate intrinsic sizes
measureNode = function(node, availableWidth, availableHeight)
    availableWidth = availableWidth or math.huge
    availableHeight = availableHeight or math.huge
    
    -- Skip if already measured and cache is valid
    if node.intrinsicSize.hasIntrinsicWidth and node.intrinsicSize.hasIntrinsicHeight then
        return node.intrinsicSize.width, node.intrinsicSize.height
    end
    
    local measuredWidth = 0
    local measuredHeight = 0
    
    -- If node has a custom measure function (for content like text)
    if node.measureFunc then
        measuredWidth, measuredHeight = node.measureFunc(node, availableWidth, availableHeight)
    else
        -- For flex containers, measure based on children
        if #node.children > 0 then
            measuredWidth, measuredHeight = measureFlexContainer(node, availableWidth, availableHeight)
        else
            -- Leaf node without measure function - use zero size
            measuredWidth = 0
            measuredHeight = 0
        end
    end
    
    -- Cache the results
    node.intrinsicSize.width = measuredWidth
    node.intrinsicSize.height = measuredHeight
    node.intrinsicSize.hasIntrinsicWidth = true
    node.intrinsicSize.hasIntrinsicHeight = true
    
    return measuredWidth, measuredHeight
end

-- Calculate the intrinsic size of a node (updated to use measurement)
calculateIntrinsicSize = function(node, availableWidth, availableHeight)
    local width = 0
    local height = 0
    
    -- If node has explicit dimensions, use them
    if node.width.type == LuaFlex.ValueType.Point then
        width = node.width.value
    elseif node.width.type == LuaFlex.ValueType.Percent then
        width = (node.width.value / 100) * availableWidth
    elseif node.width.type == LuaFlex.ValueType.Auto or node.width.type == LuaFlex.ValueType.Undefined then
        -- Use measured intrinsic width
        if node.intrinsicSize.hasIntrinsicWidth then
            width = node.intrinsicSize.width
        else
            local measuredWidth, _ = measureNode(node, availableWidth, availableHeight)
            width = measuredWidth
        end
    end
    
    if node.height.type == LuaFlex.ValueType.Point then
        height = node.height.value
    elseif node.height.type == LuaFlex.ValueType.Percent then
        height = (node.height.value / 100) * availableHeight
    elseif node.height.type == LuaFlex.ValueType.Auto or node.height.type == LuaFlex.ValueType.Undefined then
        -- Use measured intrinsic height
        if node.intrinsicSize.hasIntrinsicHeight then
            height = node.intrinsicSize.height
        else
            local _, measuredHeight = measureNode(node, availableWidth, availableHeight)
            height = measuredHeight
        end
    end
    
    return width, height
end

-- Main layout function
function LuaFlex.Node:calculateLayout(parentWidth, parentHeight)
    parentWidth = parentWidth or 0
    parentHeight = parentHeight or 0
    
    -- Skip layout if display is none
    if self.display == LuaFlex.Display.None then
        self.layout.width = 0
        self.layout.height = 0
        return
    end
    
    -- Perform measurement pass if needed (for auto dimensions)
    if self:needsMeasurement() then
        self:performMeasurementPass(parentWidth, parentHeight)
    end
    
    -- Calculate own dimensions
    local ownWidth, ownHeight = calculateIntrinsicSize(self, parentWidth, parentHeight)
    
    -- Clamp against container's own min/max constraints
    local wMax = numeric(self.maxWidth, parentWidth)
    if wMax > 0 and ownWidth > wMax then ownWidth = wMax end
    local wMin = numeric(self.minWidth, parentWidth)
    if wMin > 0 and ownWidth < wMin then ownWidth = wMin end
    
    local hMax = numeric(self.maxHeight, parentHeight)
    if hMax > 0 and ownHeight > hMax then ownHeight = hMax end
    local hMin = numeric(self.minHeight, parentHeight)
    if hMin > 0 and ownHeight < hMin then ownHeight = hMin end
    
    self.layout.width = ownWidth
    self.layout.height = ownHeight
    self.layout.direction = self.flexDirection
    
    -- If no children, we're done
    if #self.children == 0 then
        self.isDirty = false
        return
    end
    
    -- Calculate layout for children
    self:layoutChildren()
    
    self.isDirty = false
end

-- Check if this node or any descendants need measurement
function LuaFlex.Node:needsMeasurement()
    -- Check if this node needs measurement
    if ((self.width.type == LuaFlex.ValueType.Auto or self.width.type == LuaFlex.ValueType.Undefined) or
        (self.height.type == LuaFlex.ValueType.Auto or self.height.type == LuaFlex.ValueType.Undefined)) and
       (not self.intrinsicSize.hasIntrinsicWidth or not self.intrinsicSize.hasIntrinsicHeight) then
        return true
    end
    
    -- Check children recursively
    for _, child in ipairs(self.children) do
        if child:needsMeasurement() then
            return true
        end
    end
    
    return false
end

-- Perform measurement pass on this node and all descendants
function LuaFlex.Node:performMeasurementPass(availableWidth, availableHeight)
    -- Measure children first (bottom-up)
    for _, child in ipairs(self.children) do
        if child.display ~= LuaFlex.Display.None then
            child:performMeasurementPass(availableWidth, availableHeight)
        end
    end
    
    -- Then measure this node
    measureNode(self, availableWidth, availableHeight)
end

-- Partition children into flex lines for wrapping
local function partitionChildrenIntoLines(children, childMainSizes, childMargins, availableMainSize, flexWrap)
    if flexWrap == LuaFlex.FlexWrap.NoWrap then
        -- Single line - return all children in one line
        local singleLine = {}
        for _, child in ipairs(children) do
            table.insert(singleLine, child)
        end
        local lines = {}
        table.insert(lines, singleLine)
        return lines
    end
    
    local lines = {}
    local currentLine = {}
    local currentLineMainSize = 0
    
    for i, child in ipairs(children) do
        local childSize = childMainSizes[i]
        local margin = childMargins[i]
        local totalChildSize = childSize + margin.mainStart + margin.mainEnd
        
        -- If an item is larger than the container, it becomes a line of its own.
        if totalChildSize > availableMainSize and #currentLine > 0 then
            -- Finish the current line first.
            table.insert(lines, currentLine)
            -- Start a new line with the current item.
            currentLine = { child }
            currentLineMainSize = totalChildSize
        -- If the item doesn't fit on the current non-empty line, start a new line.
        elseif #currentLine > 0 and (currentLineMainSize + totalChildSize) > availableMainSize then
            table.insert(lines, currentLine)
            currentLine = { child }
            currentLineMainSize = totalChildSize
        -- Otherwise, add the item to the current line.
        else
            table.insert(currentLine, child)
            currentLineMainSize = currentLineMainSize + totalChildSize
        end
    end
    
    -- Add the last line if it has children
    if #currentLine > 0 then
        table.insert(lines, currentLine)
    end
    
    -- Handle wrap-reverse
    if flexWrap == LuaFlex.FlexWrap.WrapReverse then
        -- Reverse the order of lines
        local reversedLines = {}
        for i = #lines, 1, -1 do
            table.insert(reversedLines, lines[i])
        end
        return reversedLines
    end
    
    return lines
end

-- Resolve flexible lengths for a flex line using CSS spec algorithm
local function resolveFlexibleLengths(container, lineChildren, availableMainSize, availableCrossSize, childMainSizes, childMargins, childIndexMap)
    local isMainAxisRow = container:isFlexDirectionRow()
    
    -- Build line-specific data structures
    local lineBaseSizes = {}
    local lineMargins = {}
    for i = 1, #lineChildren do
        local child = lineChildren[i]
        local originalIndex = childIndexMap[child]
        if originalIndex then
            lineBaseSizes[i] = childMainSizes[originalIndex]
            lineMargins[i] = childMargins[originalIndex]
        else
            lineBaseSizes[i] = 0
            lineMargins[i] = {mainStart = 0, mainEnd = 0}
        end
    end

    local frozen = {}
    local targetSizes = {}
    for i=1, #lineChildren do
        targetSizes[i] = lineBaseSizes[i]
    end

    local function calculateFreeSpace()
        local usedSpace = 0
        for i = 1, #lineChildren do
            usedSpace = usedSpace + targetSizes[i] + lineMargins[i].mainStart + lineMargins[i].mainEnd
        end
        return availableMainSize - usedSpace
    end

    -- Iteratively resolve flexible lengths, "freezing" items that hit min/max constraints
    for pass = 1, #lineChildren do
        local freeSpace = calculateFreeSpace()
        if math.abs(freeSpace) < 1e-7 then break end
        local anyChange = false

        local totalFlexFactor = 0
        for i = 1, #lineChildren do
            local child = lineChildren[i]
            if not frozen[i] then
                if freeSpace > 0 and child.flexGrow > 0 then
                    totalFlexFactor = totalFlexFactor + child.flexGrow
                elseif freeSpace < 0 and child.flexShrink > 0 then
                    totalFlexFactor = totalFlexFactor + (child.flexShrink * lineBaseSizes[i])
                end
            end
        end

        if totalFlexFactor == 0 then
            break -- No more flexible items
        end

        for i = 1, #lineChildren do
            if not frozen[i] then
                local child = lineChildren[i]
                local factor = 0
                if freeSpace > 0 and child.flexGrow > 0 then
                    factor = child.flexGrow
                elseif freeSpace < 0 and child.flexShrink > 0 then
                    factor = child.flexShrink * lineBaseSizes[i]
                end

                if factor > 0 then
                    local delta = (factor / totalFlexFactor) * freeSpace
                    local nextSize = targetSizes[i] + delta
                    local clampedSize = clampMainAxis(child, isMainAxisRow, nextSize, availableMainSize, availableCrossSize)
                    
                    if clampedSize ~= nextSize then
                        frozen[i] = true -- This item is now frozen at its constraint
                    end
                    
                    if clampedSize ~= targetSizes[i] then
                        anyChange = true
                    end
                    targetSizes[i] = clampedSize
                end
            end
        end

        if not anyChange then
            break -- Converged
        end
    end

    return targetSizes
end

-- Position flex items along main axis using justify-content
local function positionFlexItemsMainAxis(container, lineChildren, resolvedMainSizes, 
                                         lineChildMargins, availableMainSize, mainStartOffset)
    local currentMainPosition = mainStartOffset
    local spacing = 0
    
    -- Determine the gap for the main axis
    local mainAxisGap = 0
    if #lineChildren > 1 then
        local inlineSize = inlineSizeOf(container) -- Per spec, gaps resolve against inline size
        if container:isFlexDirectionRow() then
            -- Use parent width for columnGap percentage resolution
            mainAxisGap = numeric(container.columnGap, inlineSize) 
        else
            -- Use parent inline size for rowGap percentage resolution
            mainAxisGap = numeric(container.rowGap, inlineSize)
        end
    end

    -- Calculate actual used space after flexible length resolution
    local totalUsedSpace = 0
    for i, _ in ipairs(lineChildren) do
        local margin = lineChildMargins[i]
        totalUsedSpace = totalUsedSpace + resolvedMainSizes[i] + margin.mainStart + margin.mainEnd
    end
    
    local totalGapSpace = mainAxisGap * (#lineChildren > 1 and #lineChildren - 1 or 0)
    local remainingSpace = availableMainSize - totalUsedSpace - totalGapSpace
    
    -- Handle auto margins first (they consume remaining space)
    local autoMarginCount = 0
    for i = 1, #lineChildren do
        local m = lineChildMargins[i]
        if m.mainStartType == LuaFlex.ValueType.Auto then autoMarginCount = autoMarginCount + 1 end
        if m.mainEndType   == LuaFlex.ValueType.Auto then autoMarginCount = autoMarginCount + 1 end
    end
    
    if autoMarginCount > 0 and remainingSpace > 0 then
        local spacePerAutoMargin = remainingSpace / autoMarginCount
        for i = 1, #lineChildren do
            local m = lineChildMargins[i]
            if m.mainStartType == LuaFlex.ValueType.Auto then m.mainStart = m.mainStart + spacePerAutoMargin end
            if m.mainEndType   == LuaFlex.ValueType.Auto then m.mainEnd   = m.mainEnd   + spacePerAutoMargin end
        end
        spacing = 0
    else
        -- Apply justify-content distribution
        local justifyContent = resolveJustifyContent(container.justifyContent, container)
        if justifyContent == LuaFlex.JustifyContent.FlexEnd then
            currentMainPosition = mainStartOffset + remainingSpace
        elseif justifyContent == LuaFlex.JustifyContent.Center then
            currentMainPosition = mainStartOffset + remainingSpace / 2
        elseif justifyContent == LuaFlex.JustifyContent.SpaceBetween then
            if #lineChildren > 1 then
                spacing = math.max(0, remainingSpace / (#lineChildren - 1))
            end
        elseif justifyContent == LuaFlex.JustifyContent.SpaceAround then
            spacing = math.max(0, remainingSpace / #lineChildren)
            currentMainPosition = mainStartOffset + spacing / 2
        elseif justifyContent == LuaFlex.JustifyContent.SpaceEvenly then
            spacing = math.max(0, remainingSpace / (#lineChildren + 1))
            currentMainPosition = mainStartOffset + spacing
        end
    end
    
    -- Position each item
    for i, child in ipairs(lineChildren) do
        local margin = lineChildMargins[i]
        currentMainPosition = currentMainPosition + margin.mainStart
        setMainAxisPosition(child, currentMainPosition, resolvedMainSizes[i],
                            container, mainStartOffset, availableMainSize)
        
        -- Move current position forward
        currentMainPosition = currentMainPosition + resolvedMainSizes[i] + margin.mainEnd + spacing
        
        -- Add gap if not the last item
        if i < #lineChildren then
            currentMainPosition = currentMainPosition + mainAxisGap
        end
    end
end

-- Layout a complete flex line: resolve flexible lengths, position on both axes
local function layoutLine(container, lineChildren, availableMainSize, availableCrossSize,
                          childMainSizes, childCrossSizes, childMargins, 
                          mainStartOffset, crossStartOffset, lineCrossSize, childIndexMap)
    local isMainAxisRow = container:isFlexDirectionRow()
    
    -- Step 1: Resolve flexible lengths for this line
    local resolvedMainSizes = resolveFlexibleLengths(container, lineChildren, availableMainSize, availableCrossSize,
                                                     childMainSizes, childMargins, childIndexMap)
    
    -- Step 2: Build line-specific margins for positioning
    local lineChildMargins = {}
    for i, child in ipairs(lineChildren) do
        local originalIndex = childIndexMap[child]
        if originalIndex then
            lineChildMargins[i] = childMargins[originalIndex]
        end
    end
    
    -- Step 3: Position items along main axis using justify-content
    positionFlexItemsMainAxis(container, lineChildren, resolvedMainSizes, 
                              lineChildMargins, availableMainSize, mainStartOffset)
    
    -- Step 4: Compute baseline alignment reference for this line (spec 8.3, 8.5)
    local hasBaselineItems = false
    local maxBaselineFromTop = 0
    local baselineItems = {}
    local lineFirstBaseline = nil
    local lineLastBaseline = nil
    
    for i = 1, #lineChildren do
        local child = lineChildren[i]
        local originalIndex = childIndexMap[child]
        if originalIndex then
            local alignSelf = child.alignSelf
            if alignSelf == LuaFlex.AlignSelf.Auto then
                alignSelf = container.alignItems
            end
            if alignSelf == LuaFlex.AlignItems.Baseline then
                local margin = childMargins[originalIndex]
                local crossSizeRaw = childCrossSizes[originalIndex]
                local mainCandidate = resolvedMainSizes[i]
                
                -- Calculate item's baseline using proper dimensions
                local baseline = 0
                if isMainAxisRow then
                    baseline = calculateItemBaseline(child, mainCandidate, crossSizeRaw)
                else
                    baseline = calculateItemBaseline(child, crossSizeRaw, mainCandidate)
                end
                
                local baselineFromTop = margin.crossStart + baseline
                maxBaselineFromTop = max(maxBaselineFromTop, baselineFromTop)
                
                baselineItems[i] = {
                    child = child,
                    originalIndex = originalIndex,
                    baseline = baseline,
                    margin = margin,
                    crossSize = crossSizeRaw
                }
                hasBaselineItems = true
            end
            
            -- Track line baselines for container baseline computation
            -- First baseline item in document order (after ordering) determines line baseline
            if lineFirstBaseline == nil and child.display ~= LuaFlex.Display.None then
                local margin = childMargins[originalIndex]
                local crossSizeRaw = childCrossSizes[originalIndex]
                local mainCandidate = resolvedMainSizes[i]
                
                local itemBaseline
                if isMainAxisRow then
                    itemBaseline = calculateItemBaseline(child, mainCandidate, crossSizeRaw)
                else
                    itemBaseline = calculateItemBaseline(child, crossSizeRaw, mainCandidate)
                end
                
                lineFirstBaseline = crossStartOffset + margin.crossStart + itemBaseline
            end
        end
    end
    
    -- Set line last baseline (for now, same as first - could be enhanced for multi-line text)
    lineLastBaseline = lineFirstBaseline
    
    -- Step 5: Position children along cross axis and set final dimensions
    for i, child in ipairs(lineChildren) do
        local originalIndex = childIndexMap[child]
        
        if originalIndex then
            local alignSelf = child.alignSelf
            if alignSelf == LuaFlex.AlignSelf.Auto then
                alignSelf = container.alignItems
            end
            
            -- Resolve L3 keywords
            alignSelf = resolveAlign(alignSelf)

            local margin = childMargins[originalIndex]
            local crossPosition = crossStartOffset
            local crossSize = childCrossSizes[originalIndex]
            local availableCrossForChild = lineCrossSize - margin.crossStart - margin.crossEnd
            
            local hasAutoCrossMargin = margin.crossStartType == LuaFlex.ValueType.Auto or margin.crossEndType == LuaFlex.ValueType.Auto
            
            if hasAutoCrossMargin then
                local remainingCrossSpaceForChild = math.max(0, lineCrossSize - crossSize - margin.crossStart - margin.crossEnd)
                if margin.crossStartType == LuaFlex.ValueType.Auto and margin.crossEndType == LuaFlex.ValueType.Auto then
                    crossPosition = crossStartOffset + margin.crossStart + remainingCrossSpaceForChild / 2
                elseif margin.crossStartType == LuaFlex.ValueType.Auto then
                    crossPosition = crossStartOffset + margin.crossStart + remainingCrossSpaceForChild
                else -- only crossEnd is auto
                    crossPosition = crossStartOffset + margin.crossStart
                end
            elseif alignSelf == LuaFlex.AlignItems.FlexEnd then
                crossPosition = crossStartOffset + lineCrossSize - crossSize - margin.crossEnd
            elseif alignSelf == LuaFlex.AlignItems.Center then
                crossPosition = crossStartOffset + margin.crossStart + (availableCrossForChild - crossSize) / 2
            elseif alignSelf == LuaFlex.AlignItems.Stretch then
                -- Only stretch if cross-axis dimension is auto, not explicitly set
                local shouldStretch = false
                if isMainAxisRow then
                    shouldStretch = (child.height.type == LuaFlex.ValueType.Auto or 
                                   child.height.type == LuaFlex.ValueType.Undefined)
                else
                    shouldStretch = (child.width.type == LuaFlex.ValueType.Auto or
                                   child.width.type == LuaFlex.ValueType.Undefined)
                end
                
                if shouldStretch then
                    local stretchedSize = math.max(0, availableCrossForChild)
                    
                    -- Clamp against min/max constraints
                    if isMainAxisRow then
                        local minH = numeric(child.minHeight, availableCrossSize)
                        local maxH = numeric(child.maxHeight, availableCrossSize)
                        if maxH > 0 and stretchedSize > maxH then
                            stretchedSize = maxH
                        end
                        if minH > 0 and stretchedSize < minH then
                            stretchedSize = minH
                        end
                    else
                        local minW = numeric(child.minWidth, availableCrossSize)
                        local maxW = numeric(child.maxWidth, availableCrossSize)
                        if maxW > 0 and stretchedSize > maxW then
                            stretchedSize = maxW
                        end
                        if minW > 0 and stretchedSize < minW then
                            stretchedSize = minW
                        end
                    end
                    
                    crossSize = stretchedSize
                end
                
                crossPosition = crossStartOffset + margin.crossStart
            elseif alignSelf == LuaFlex.AlignItems.Baseline then
                if hasBaselineItems and baselineItems[i] then
                    local baselineInfo = baselineItems[i]
                    local targetBaselineFromTop = maxBaselineFromTop
                    crossPosition = crossStartOffset + (targetBaselineFromTop - baselineInfo.baseline - margin.crossStart)
                else
                    crossPosition = crossStartOffset + margin.crossStart
                end
            else -- FlexStart (default)
                crossPosition = crossStartOffset + margin.crossStart
            end
            
            -- Apply 'safe' alignment clamping if specified
            local safety = child.alignSelfSafety
            if child.alignSelf == LuaFlex.AlignSelf.Auto then
                safety = container.alignItemsSafety
            end
            if safety == "safe" then
                crossPosition = clampSafe(crossPosition, crossSize, crossStartOffset, lineCrossSize)
            end

            setCrossAxisPosition(container, child, crossPosition)
            
            -- Set final dimensions with cross-axis clamping
            local actualMainSize = resolvedMainSizes[i]
            
            -- Aspect Ratio transfer before final clamping per CSS Sizing spec
            local ar = child.aspectRatio
            if ar and ar > 0 then
                local mainDef = true -- main size was resolved through flex
                local crossDef = not (isMainAxisRow and 
                    (child.height.type == LuaFlex.ValueType.Auto or child.height.type == LuaFlex.ValueType.Undefined) or
                    not isMainAxisRow and 
                    (child.width.type == LuaFlex.ValueType.Auto or child.width.type == LuaFlex.ValueType.Undefined))
                
                local newMainSize, newCrossSize
                if isMainAxisRow then
                    newMainSize, _, newCrossSize, _ = applyAspectRatio(child, actualMainSize, mainDef, crossSize, crossDef, ar)
                else
                    newCrossSize, _, newMainSize, _ = applyAspectRatio(child, crossSize, crossDef, actualMainSize, mainDef, ar)
                end
                
                actualMainSize = newMainSize
                crossSize = newCrossSize
            end
            resolvedMainSizes[i] = actualMainSize

            if isMainAxisRow then
                child.layout.width = actualMainSize
                local clampedCross = crossSize
                local minH = numeric(child.minHeight, availableCrossSize)
                local maxH = numeric(child.maxHeight, availableCrossSize)
                if maxH > 0 and clampedCross > maxH then
                    clampedCross = maxH
                end
                if minH > 0 and clampedCross < minH then
                    clampedCross = minH
                end
                child.layout.height = clampedCross
            else
                local clampedCross = crossSize
                local minW = numeric(child.minWidth, availableCrossSize)
                local maxW = numeric(child.maxWidth, availableCrossSize)
                if maxW > 0 and clampedCross > maxW then
                    clampedCross = maxW
                end
                if minW > 0 and clampedCross < minW then
                    clampedCross = minW
                end
                child.layout.width = clampedCross
                child.layout.height = actualMainSize
            end
            
            -- Handle position: relative - apply visual offset after normal layout
            if child.positionType == LuaFlex.PositionType.Relative then
                local parentContentWidth, parentContentHeight
                if isMainAxisRow then
                    parentContentWidth = availableMainSize
                    parentContentHeight = availableCrossSize
                else
                    parentContentWidth = availableCrossSize
                    parentContentHeight = availableMainSize
                end

                -- 'top' and 'bottom' control vertical offset. 'top' wins if both are set.
                local offsetY = 0
                if child.top.type ~= LuaFlex.ValueType.Undefined then
                    offsetY = numeric(child.top, parentContentHeight)
                elseif child.bottom.type ~= LuaFlex.ValueType.Undefined then
                    offsetY = -numeric(child.bottom, parentContentHeight)
                end

                -- 'left' and 'right' control horizontal offset. 'left' wins if both are set.
                local offsetX = 0
                if child.left.type ~= LuaFlex.ValueType.Undefined then
                    offsetX = numeric(child.left, parentContentWidth)
                elseif child.right.type ~= LuaFlex.ValueType.Undefined then
                    offsetX = -numeric(child.right, parentContentWidth)
                end
                
                -- Apply the offset to the final computed position
                child.layout.left = child.layout.left + offsetX
                child.layout.top = child.layout.top + offsetY
            end
            
            -- Recursively layout children
            child:calculateLayout(child.layout.width, child.layout.height)
        end
    end
    
    return resolvedMainSizes, lineFirstBaseline, lineLastBaseline
end

-- Layout absolutely positioned children
local function layoutAbsoluteChildren(container, absoluteChildren, contentWidth, contentHeight, 
                                      mainStartOffset, crossStartOffset)
    for _, child in ipairs(absoluteChildren) do
        local childLeft = child.layout.left
        local childTop = child.layout.top
        local childWidth = child.layout.width
        local childHeight = child.layout.height
        
        -- Calculate child's intrinsic size if not explicitly set
        if child.width.type == LuaFlex.ValueType.Undefined and 
           child.height.type == LuaFlex.ValueType.Undefined then
            childWidth, childHeight = calculateIntrinsicSize(child, contentWidth, contentHeight)
        elseif child.width.type == LuaFlex.ValueType.Undefined then
            childWidth, _ = calculateIntrinsicSize(child, contentWidth, contentHeight)
        elseif child.height.type == LuaFlex.ValueType.Undefined then
            _, childHeight = calculateIntrinsicSize(child, contentWidth, contentHeight)
        end
        
        -- Resolve explicit dimensions
        if child.width.type == LuaFlex.ValueType.Point then
            childWidth = child.width.value
        elseif child.width.type == LuaFlex.ValueType.Percent then
            childWidth = (child.width.value / 100) * contentWidth
        end
        
        if child.height.type == LuaFlex.ValueType.Point then
            childHeight = child.height.value
        elseif child.height.type == LuaFlex.ValueType.Percent then
            childHeight = (child.height.value / 100) * contentHeight
        end
        
        -- Position based on top, left, right, bottom properties
        local hasLeft = child.left.type ~= LuaFlex.ValueType.Undefined
        local hasRight = child.right.type ~= LuaFlex.ValueType.Undefined
        local hasTop = child.top.type ~= LuaFlex.ValueType.Undefined
        local hasBottom = child.bottom.type ~= LuaFlex.ValueType.Undefined
        
        -- Resolve align-self/justify-self for abs-pos children with auto offsets
        local alignSelf = resolveAlign(child.alignSelf == 'auto' and container.alignItems or child.alignSelf)
        local justifySelf = resolveJustifyContent(child.justifySelf == 'auto' and container.justifyItems or child.justifySelf, container)

        -- Aspect ratio transfer for absolute children per CSS Sizing spec
        local ar = child.aspectRatio
        if ar and ar > 0 then
            local wDef = not (child.width.type == LuaFlex.ValueType.Auto or child.width.type == LuaFlex.ValueType.Undefined)
            local hDef = not (child.height.type == LuaFlex.ValueType.Auto or child.height.type == LuaFlex.ValueType.Undefined)
            childWidth, _, childHeight, _ = applyAspectRatio(child, childWidth, wDef, childHeight, hDef, ar)
        end
        
        -- Calculate left position
        if hasLeft and hasRight then
            -- Both left and right specified - calculate width and use left
            local leftValue = numeric(child.left, contentWidth)
            local rightValue = numeric(child.right, contentWidth)
            childWidth = contentWidth - leftValue - rightValue
            childLeft = mainStartOffset + leftValue
        elseif hasLeft then
            -- Only left specified
            childLeft = mainStartOffset + numeric(child.left, contentWidth)
        elseif hasRight then
            -- Only right specified
            local rightValue = numeric(child.right, contentWidth)
            childLeft = mainStartOffset + contentWidth - childWidth - rightValue
        else
            -- Neither left nor right specified - use justify-self
            if justifySelf == LuaFlex.JustifyContent.FlexEnd then
                childLeft = mainStartOffset + contentWidth - childWidth
            elseif justifySelf == LuaFlex.JustifyContent.Center then
                childLeft = mainStartOffset + (contentWidth - childWidth) / 2
            else -- FlexStart
                childLeft = mainStartOffset
            end
        end
        
        -- Calculate top position
        if hasTop and hasBottom then
            -- Both top and bottom specified - calculate height and use top
            local topValue = numeric(child.top, contentHeight)
            local bottomValue = numeric(child.bottom, contentHeight)
            childHeight = contentHeight - topValue - bottomValue
            childTop = crossStartOffset + topValue
        elseif hasTop then
            -- Only top specified
            childTop = crossStartOffset + numeric(child.top, contentHeight)
        elseif hasBottom then
            -- Only bottom specified
            local bottomValue = numeric(child.bottom, contentHeight)
            childTop = crossStartOffset + contentHeight - childHeight - bottomValue
        else
            -- Neither top nor bottom specified - use align-self
            if alignSelf == LuaFlex.AlignItems.FlexEnd then
                childTop = crossStartOffset + contentHeight - childHeight
            elseif alignSelf == LuaFlex.AlignItems.Center then
                childTop = crossStartOffset + (contentHeight - childHeight) / 2
            else -- FlexStart
                childTop = crossStartOffset
            end
        end
        
        -- Apply calculated layout
        child.layout.left = childLeft
        child.layout.top = childTop
        child.layout.width = math.max(0, childWidth)
        child.layout.height = math.max(0, childHeight)
        
        -- Recursively layout the absolutely positioned child
        child:calculateLayout(child.layout.width, child.layout.height)
    end
end

-- Layout children using flexbox algorithm
function LuaFlex.Node:layoutChildren()
    local children = {}
    local absoluteChildren = {}
    
    -- Filter children by positioning type
    for i = 1, #self.children do
        local child = self.children[i]
        if child.display ~= LuaFlex.Display.None then
            if child.positionType == LuaFlex.PositionType.Absolute then
                absoluteChildren[#absoluteChildren + 1] = child
            else
                children[#children + 1] = child
            end
        end
    end
    
    -- Sort children by order property (lower values come first)
    -- Items with the same order maintain their source document order
    -- Create index map once for O(1) lookups during sorting (avoids O(N² log N) complexity)
    local originalIndices = {}
    for i = 1, #self.children do
        originalIndices[self.children[i]] = i
    end
    
    table.sort(children, function(a, b)
        if a.order == b.order then
            -- O(1) index lookup instead of O(N) search
            return originalIndices[a] < originalIndices[b]
        else
            return a.order < b.order
        end
    end)
    
    -- Create a map for O(1) lookup of a child's index within the sorted `children` array
    local sortedOriginalIndices = {}
    for i = 1, #children do
        sortedOriginalIndices[children[i]] = i
    end
    
    -- Calculate the content area (available space for children after padding/border)
    local inlineSize = inlineSizeOf(self)
    local padding = {
        left = numeric(self.paddingLeft, inlineSize),
        right = numeric(self.paddingRight, inlineSize),
        top = numeric(self.paddingTop, inlineSize),
        bottom = numeric(self.paddingBottom, inlineSize)
    }
    local border = {
        left = numeric(self.borderLeft, 0),
        right = numeric(self.borderRight, 0),
        top = numeric(self.borderTop, 0),
        bottom = numeric(self.borderBottom, 0)
    }
    local contentWidth = max(0, self.layout.width - padding.left - padding.right - border.left - border.right)
    local contentHeight = max(0, self.layout.height - padding.top - padding.bottom - border.top - border.bottom)

    -- Create axis helper to reduce branching throughout layout
    local axis = createAxisInfo(self, contentWidth, contentHeight, padding, border)
    
    -- If no normally positioned children, just layout absolute children
    if #children == 0 then
        if #absoluteChildren > 0 then
            layoutAbsoluteChildren(self, absoluteChildren, contentWidth, contentHeight, 
                                   axis.mainStartOffset, axis.crossStartOffset)
        end
        return
    end
    
    -- Phase 1: Establish flex base size and hypothetical main size
    local childMainSizes = {}
    local childCrossSizes = {}
    local childMargins = {}
    
    for i = 1, #children do
        local child = children[i]
        -- Compute flex base size (simplified): flex-basis > percent > auto(content) > undefined(content)
        local baseMain
        if child.flexBasis.type == LuaFlex.ValueType.Point then
            baseMain = child.flexBasis.value
        elseif child.flexBasis.type == LuaFlex.ValueType.Percent then
            baseMain = (child.flexBasis.value / 100) * axis.availableMainSize
        elseif child.flexBasis.type == LuaFlex.ValueType.Content then
            -- "content" basis keyword always resolves to content size, ignoring width/height
            local cw, ch = calculateIntrinsicSize(child,
                axis.isMainAxisRow and axis.availableMainSize or axis.availableCrossSize,
                axis.isMainAxisRow and axis.availableCrossSize or axis.availableMainSize)
            baseMain = axis.isMainAxisRow and cw or ch
        else -- flexBasis is auto or undefined
            -- Per spec, 'auto' basis resolves to the main size property if defined, otherwise content size.
            local mainSizeProperty = axis.isMainAxisRow and child.width or child.height
            if mainSizeProperty.type == LuaFlex.ValueType.Point then
                baseMain = mainSizeProperty.value
            elseif mainSizeProperty.type == LuaFlex.ValueType.Percent then
                baseMain = (mainSizeProperty.value / 100) * axis.availableMainSize
            else -- width/height is also auto or undefined, so use content size
                local cw, ch = calculateIntrinsicSize(child,
                    axis.isMainAxisRow and axis.availableMainSize or axis.availableCrossSize,
                    axis.isMainAxisRow and axis.availableCrossSize or axis.availableMainSize)
                baseMain = axis.isMainAxisRow and cw or ch
            end
        end
        baseMain = clampMainAxis(child, axis.isMainAxisRow, baseMain, axis.availableMainSize, axis.availableCrossSize)
        local cw2, ch2 = calculateIntrinsicSize(child,
            axis.isMainAxisRow and axis.availableMainSize or axis.availableCrossSize,
            axis.isMainAxisRow and axis.availableCrossSize or axis.availableMainSize)
        local baseCross = axis.isMainAxisRow and ch2 or cw2
        
        -- Margin data table
        local marginData = {}
        local containerInlineSize = inlineSizeOf(self) -- Per spec, percentage margins are against inline size.

        if axis.isMainAxisRow then
            marginData.mainStart = numeric(child.marginLeft, containerInlineSize)
            marginData.mainEnd = numeric(child.marginRight, containerInlineSize)
            marginData.crossStart = numeric(child.marginTop, containerInlineSize)
            marginData.crossEnd = numeric(child.marginBottom, containerInlineSize)
            marginData.mainStartType = child.marginLeft.type
            marginData.mainEndType = child.marginRight.type
            marginData.crossStartType = child.marginTop.type
            marginData.crossEndType = child.marginBottom.type
        else
            marginData.mainStart = numeric(child.marginTop, containerInlineSize)
            marginData.mainEnd = numeric(child.marginBottom, containerInlineSize)
            marginData.crossStart = numeric(child.marginLeft, containerInlineSize)
            marginData.crossEnd = numeric(child.marginRight, containerInlineSize)
            marginData.mainStartType = child.marginTop.type
            marginData.mainEndType = child.marginBottom.type
            marginData.crossStartType = child.marginLeft.type
            marginData.crossEndType = child.marginRight.type
        end
        childMargins[i] = marginData
        
        childMainSizes[i] = baseMain
        childCrossSizes[i] = baseCross
    end
    
    -- Phase 2: Partition children into flex lines
    local flexLines = partitionChildrenIntoLines(children, childMainSizes, childMargins, 
                                                 axis.availableMainSize, self.flexWrap)
    
    -- Phase 3 & 4: Resolve flexible lengths per line, then position
    -- lineMainSizes reserved for future refactor; remove to satisfy linter for now
    -- local lineMainSizes = {}
    local lineCrossSizes = {}
    local lineChildMainSizes = {}
    
    -- Calculate cross size for each line first (needed for line layout)
    for lineIndex, lineChildren in ipairs(flexLines) do
        local maxCrossSize = 0
        for _, child in ipairs(lineChildren) do
            local originalIndex = sortedOriginalIndices[child] -- O(1) lookup
            
            if originalIndex then
                local crossSize = childCrossSizes[originalIndex]
                local margin = childMargins[originalIndex]
                local totalCrossSize = crossSize + margin.crossStart + margin.crossEnd
                maxCrossSize = math.max(maxCrossSize, totalCrossSize)
            end
        end
        
        lineCrossSizes[lineIndex] = maxCrossSize
    end
    
    -- For a single line, if the container has a definite cross size, the line's cross size is that size.
    -- This is what enables align-items: stretch to work correctly per spec 9.4, 9.6.
    if self.flexWrap == LuaFlex.FlexWrap.NoWrap and #flexLines == 1 then
        local crossSizeProperty = axis.isMainAxisRow and self.height or self.width
        local parentCrossSize = axis.isMainAxisRow and (self.parent and self.parent.layout.height or huge) or 
                                                       (self.parent and self.parent.layout.width or huge)
        
        -- Check if cross size is definite
        local crossResolved, crossDef = resolveLength(crossSizeProperty, parentCrossSize)
        if crossDef and crossResolved >= 0 then
            lineCrossSizes[1] = axis.availableCrossSize
        end
    end
    
    -- Distribute lines using align-content
    local totalLineCrossSize = 0
    for _, lineSize in ipairs(lineCrossSizes) do
        totalLineCrossSize = totalLineCrossSize + lineSize
    end
    
    -- Determine the gap for the cross axis (between lines)
    local crossAxisGap = 0
    if #flexLines > 1 then
        local inlineSize = inlineSizeOf(self)
        if axis.isMainAxisRow then
            crossAxisGap = numeric(self.rowGap, inlineSize)
        else
            crossAxisGap = numeric(self.columnGap, inlineSize)
        end
    end
    
    -- Account for gaps in total cross size
    totalLineCrossSize = totalLineCrossSize + (crossAxisGap * (#flexLines > 1 and #flexLines - 1 or 0))

    local remainingCrossSpace = axis.availableCrossSize - totalLineCrossSize
    local currentCrossPosition = axis.crossStartOffset
    local lineSpacing = 0
    
    if self.flexWrap == LuaFlex.FlexWrap.WrapReverse and #flexLines == 1 then
        currentCrossPosition = axis.crossStartOffset + axis.availableCrossSize - lineCrossSizes[1]
    end
    
    local alignContent = self.alignContent
    if self.flexWrap == LuaFlex.FlexWrap.WrapReverse then
        if alignContent == LuaFlex.AlignContent.FlexStart or alignContent == LuaFlex.AlignContent.Start then
            alignContent = LuaFlex.AlignContent.FlexEnd
        elseif alignContent == LuaFlex.AlignContent.FlexEnd or alignContent == LuaFlex.AlignContent.End then
            alignContent = LuaFlex.AlignContent.FlexStart
        end
    end
    
    if #flexLines > 1 then
        local resolvedAlignContent = resolveAlignContent(alignContent)
        if resolvedAlignContent == LuaFlex.AlignContent.FlexEnd then
            currentCrossPosition = axis.crossStartOffset + axis.availableCrossSize - totalLineCrossSize
        elseif resolvedAlignContent == LuaFlex.AlignContent.Center then
            currentCrossPosition = axis.crossStartOffset + remainingCrossSpace / 2
        elseif resolvedAlignContent == LuaFlex.AlignContent.SpaceBetween then
            lineSpacing = remainingCrossSpace / (#flexLines - 1)
        elseif resolvedAlignContent == LuaFlex.AlignContent.SpaceAround then
            lineSpacing = remainingCrossSpace / #flexLines
            currentCrossPosition = axis.crossStartOffset + lineSpacing / 2
        elseif resolvedAlignContent == LuaFlex.AlignContent.SpaceEvenly then
            lineSpacing = remainingCrossSpace / (#flexLines + 1)
            currentCrossPosition = axis.crossStartOffset + lineSpacing
        elseif resolvedAlignContent == LuaFlex.AlignContent.Stretch then
            if remainingCrossSpace > 0 then
                local additionalSpacePerLine = remainingCrossSpace / #flexLines
                for i = 1, #lineCrossSizes do
                    lineCrossSizes[i] = lineCrossSizes[i] + additionalSpacePerLine
                end
            end
        end
    end
    
    -- Track container baselines from first and last lines
    local containerFirstBaseline = nil
    local containerLastBaseline = nil
    
    -- Layout each flex line
    for lineIndex, lineChildren in ipairs(flexLines) do
        local lineCrossSize = lineCrossSizes[lineIndex]
        
        -- Layout this complete line using the new layoutLine function
        local actualChildMainSizes, lineFirstBaseline, lineLastBaseline = layoutLine(self, lineChildren, 
                                                axis.availableMainSize, axis.availableCrossSize,
                                                childMainSizes, childCrossSizes, childMargins,
                                                axis.mainStartOffset, currentCrossPosition, lineCrossSize, sortedOriginalIndices)
        
        lineChildMainSizes[lineIndex] = actualChildMainSizes
        
        -- Set container baselines from first and last lines (spec 8.5)
        if lineIndex == 1 and lineFirstBaseline ~= nil then
            containerFirstBaseline = lineFirstBaseline
        end
        if lineIndex == #flexLines and lineLastBaseline ~= nil then
            containerLastBaseline = lineLastBaseline
        end
        
        -- Move to next line
        currentCrossPosition = currentCrossPosition + lineCrossSize + lineSpacing
        
        -- Add cross-axis gap if not the last line
        if lineIndex < #flexLines then
            currentCrossPosition = currentCrossPosition + crossAxisGap
        end
    end
    
    -- Set computed container baselines in layout
    self.layout.firstBaseline = containerFirstBaseline
    self.layout.lastBaseline = containerLastBaseline
    
    -- Layout absolutely positioned children after normal flow
    if #absoluteChildren > 0 then
        layoutAbsoluteChildren(self, absoluteChildren, contentWidth, contentHeight, 
                               axis.mainStartOffset, axis.crossStartOffset)
    end
    
    -- No object pooling; rely on Lua GC for temporary allocations
end



-- Convenience method for common flex properties
function LuaFlex.Node:setFlex(grow, shrink, basis)
    if grow ~= nil then self:setFlexGrow(grow) end
    if shrink ~= nil then self:setFlexShrink(shrink) end
    if basis ~= nil then
        self:setFlexBasis(basis)
    end
    return self
end

-- Set individual style property with validation
function LuaFlex.Node:set(prop, value)
    if prop == "flexDirection" then return self:setFlexDirection(value)
    elseif prop == "justifyContent" then return self:setJustifyContent(value)
    elseif prop == "alignItems" then return self:setAlignItems(value)
    elseif prop == "alignSelf" then return self:setAlignSelf(value)
    elseif prop == "alignContent" then return self:setAlignContent(value)
    elseif prop == "flexWrap" then return self:setFlexWrap(value)
    elseif prop == "flexGrow" then return self:setFlexGrow(value)
    elseif prop == "flexShrink" then return self:setFlexShrink(value)
    elseif prop == "flexBasis" then return self:setFlexBasis(value)
    elseif prop == "width" then return self:setWidth(value)
    elseif prop == "height" then return self:setHeight(value)
    elseif prop == "minWidth" then return self:setMinWidth(value)
    elseif prop == "minHeight" then return self:setMinHeight(value)
    elseif prop == "maxWidth" then return self:setMaxWidth(value)
    elseif prop == "maxHeight" then return self:setMaxHeight(value)
    elseif prop == "margin" then return self:setMargin(value)
    elseif prop == "padding" then return self:setPadding(value)
    elseif prop == "gap" then return self:setGap(value)
    elseif prop == "rowGap" then return self:setRowGap(value)
    elseif prop == "columnGap" then return self:setColumnGap(value)
    elseif prop == "positionType" then return self:setPositionType(value)
    elseif prop == "display" then return self:setDisplay(value)
    elseif prop == "order" then return self:setOrder(value)
    elseif prop == "aspectRatio" then return self:setAspectRatio(value)
    else
        error("Unknown style property: " .. tostring(prop))
    end
end

-- Set multiple style properties at once with batched dirty marking
function LuaFlex.Node:style(tbl)
    if type(tbl) ~= "table" then
        error("style() requires a table of properties")
    end
    
    return self:batch(function(node)
        for prop, value in pairs(tbl) do
            node:set(prop, value)
        end
    end)
end

-- Method to mark layout as clean
function LuaFlex.Node:markLayoutClean()
    self.isDirty = false
end

-- Debug function to print the layout tree
function LuaFlex.Node:printLayout(indent)
    indent = indent or 0
    local prefix = string.rep("  ", indent)
    print(string.format("%sNode: %.2f,%.2f %.2fx%.2f", 
        prefix, 
        self.layout.left, 
        self.layout.top, 
        self.layout.width, 
        self.layout.height))
    
    for _, child in ipairs(self.children) do
        child:printLayout(indent + 1)
    end
end

function LuaFlex.Node:setJustifyItems(justify)
    if self.justifyItems ~= justify then
        self.justifyItems = justify
        if not self._suspendDirty then self:markDirty() end
    end
    return self
end

function LuaFlex.Node:setJustifySelf(justify)
    if self.justifySelf ~= justify then
        self.justifySelf = justify
        if not self._suspendDirty then self:markDirty() end
    end
    return self
end

return LuaFlex