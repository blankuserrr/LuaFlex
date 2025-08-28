-- LuaFlex: A performant and portable Lua layout engine that conforms to the FlexBox specification
-- Inspired by Facebook's Yoga

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

LuaFlex.JustifyContent = {
    FlexStart = "flex-start",
    FlexEnd = "flex-end",
    Center = "center",
    SpaceBetween = "space-between",
    SpaceAround = "space-around",
    SpaceEvenly = "space-evenly"
}

LuaFlex.AlignItems = {
    FlexStart = "flex-start",
    FlexEnd = "flex-end",
    Center = "center",
    Stretch = "stretch",
    Baseline = "baseline"
}

LuaFlex.AlignSelf = {
    Auto = "auto",
    FlexStart = "flex-start",
    FlexEnd = "flex-end",
    Center = "center",
    Stretch = "stretch",
    Baseline = "baseline"
}

LuaFlex.AlignContent = {
    FlexStart = "flex-start",
    FlexEnd = "flex-end",
    Center = "center",
    Stretch = "stretch",
    SpaceBetween = "space-between",
    SpaceAround = "space-around",
    SpaceEvenly = "space-evenly"
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
    Auto = "auto"
}

-- Helper function to create a value with type
local function createValue(value, valueType)
    return {
        value = value or 0,
        type = valueType or LuaFlex.ValueType.Undefined
    }
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
        flexWrap = LuaFlex.FlexWrap.NoWrap,
        positionType = LuaFlex.PositionType.Static,
        display = LuaFlex.Display.Flex,
        order = 0,
        
        -- Flex properties
        flexGrow = 0,
        flexShrink = 1,
        flexBasis = createValue(nil, LuaFlex.ValueType.Auto),
        
        -- Dimensions
        width = createValue(),
        height = createValue(),
        minWidth = createValue(),
        minHeight = createValue(),
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
            direction = LuaFlex.FlexDirection.Row
        },
        
        -- Tree structure
        parent = nil,
        children = {},
        
        -- Internal flags
        isDirty = true,
        hasNewLayout = true,
        
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
        }
    }
    
    node = setmetatable(node, LuaFlex.Node)
    
    if props and type(props) == "table" then
        -- Simple property initializer; does not call setters to avoid dirty propagation during construction
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
        self:markDirty()
    end
    return self
end

function LuaFlex.Node:setJustifyContent(justify)
    if self.justifyContent ~= justify then
        self.justifyContent = justify
        self:markDirty()
    end
    return self
end

function LuaFlex.Node:setAlignItems(align)
    if self.alignItems ~= align then
        self.alignItems = align
        self:markDirty()
    end
    return self
end

function LuaFlex.Node:setAlignSelf(align)
    if self.alignSelf ~= align then
        self.alignSelf = align
        self:markDirty()
    end
    return self
end

function LuaFlex.Node:setFlexWrap(wrap)
    if self.flexWrap ~= wrap then
        self.flexWrap = wrap
        self:markDirty()
    end
    return self
end

function LuaFlex.Node:setAlignContent(align)
    if self.alignContent ~= align then
        self.alignContent = align
        self:markDirty()
    end
    return self
end

function LuaFlex.Node:setFlexGrow(grow)
    if self.flexGrow ~= grow then
        self.flexGrow = grow
        self:markDirty()
    end
    return self
end

function LuaFlex.Node:setFlexShrink(shrink)
    if self.flexShrink ~= shrink then
        self.flexShrink = shrink
        self:markDirty()
    end
    return self
end

function LuaFlex.Node:setFlexBasis(basis, valueType)
    local newBasis = createValue(basis, valueType)
    if self.flexBasis.value ~= newBasis.value or self.flexBasis.type ~= newBasis.type then
        self.flexBasis = newBasis
        self:markDirty()
    end
    return self
end

-- Dimension setters
function LuaFlex.Node:setWidth(width, valueType)
    local newWidth = createValue(width, valueType)
    if self.width.value ~= newWidth.value or self.width.type ~= newWidth.type then
        self.width = newWidth
        self:markDirty()
    end
    return self
end

function LuaFlex.Node:setHeight(height, valueType)
    local newHeight = createValue(height, valueType)
    if self.height.value ~= newHeight.value or self.height.type ~= newHeight.type then
        self.height = newHeight
        self:markDirty()
    end
    return self
end

-- Margin setters
function LuaFlex.Node:setMargin(top, right, bottom, left)
    self:setMarginTop(top, LuaFlex.ValueType.Point)
    self:setMarginRight(right or top, LuaFlex.ValueType.Point)
    self:setMarginBottom(bottom or top, LuaFlex.ValueType.Point)
    self:setMarginLeft(left or right or top, LuaFlex.ValueType.Point)
    return self
end

function LuaFlex.Node:setMarginTop(margin, valueType)
    local newMargin = createValue(margin, valueType)
    if self.marginTop.value ~= newMargin.value or self.marginTop.type ~= newMargin.type then
        self.marginTop = newMargin
        self:markDirty()
    end
    return self
end

function LuaFlex.Node:setMarginRight(margin, valueType)
    local newMargin = createValue(margin, valueType)
    if self.marginRight.value ~= newMargin.value or self.marginRight.type ~= newMargin.type then
        self.marginRight = newMargin
        self:markDirty()
    end
    return self
end

function LuaFlex.Node:setMarginBottom(margin, valueType)
    local newMargin = createValue(margin, valueType)
    if self.marginBottom.value ~= newMargin.value or self.marginBottom.type ~= newMargin.type then
        self.marginBottom = newMargin
        self:markDirty()
    end
    return self
end

function LuaFlex.Node:setMarginLeft(margin, valueType)
    local newMargin = createValue(margin, valueType)
    if self.marginLeft.value ~= newMargin.value or self.marginLeft.type ~= newMargin.type then
        self.marginLeft = newMargin
        self:markDirty()
    end
    return self
end

-- Padding setters
function LuaFlex.Node:setPadding(top, right, bottom, left)
    self:setPaddingTop(top, LuaFlex.ValueType.Point)
    self:setPaddingRight(right or top, LuaFlex.ValueType.Point)
    self:setPaddingBottom(bottom or top, LuaFlex.ValueType.Point)
    self:setPaddingLeft(left or right or top, LuaFlex.ValueType.Point)
    return self
end

function LuaFlex.Node:setPaddingTop(padding, valueType)
    local newPadding = createValue(padding, valueType)
    if self.paddingTop.value ~= newPadding.value or self.paddingTop.type ~= newPadding.type then
        self.paddingTop = newPadding
        self:markDirty()
    end
    return self
end

function LuaFlex.Node:setPaddingRight(padding, valueType)
    local newPadding = createValue(padding, valueType)
    if self.paddingRight.value ~= newPadding.value or self.paddingRight.type ~= newPadding.type then
        self.paddingRight = newPadding
        self:markDirty()
    end
    return self
end

function LuaFlex.Node:setPaddingBottom(padding, valueType)
    local newPadding = createValue(padding, valueType)
    if self.paddingBottom.value ~= newPadding.value or self.paddingBottom.type ~= newPadding.type then
        self.paddingBottom = newPadding
        self:markDirty()
    end
    return self
end

function LuaFlex.Node:setPaddingLeft(padding, valueType)
    local newPadding = createValue(padding, valueType)
    if self.paddingLeft.value ~= newPadding.value or self.paddingLeft.type ~= newPadding.type then
        self.paddingLeft = newPadding
        self:markDirty()
    end
    return self
end

-- Gap setters
function LuaFlex.Node:setGap(gap, valueType)
    self:setRowGap(gap, valueType)
    self:setColumnGap(gap, valueType)
    return self
end

function LuaFlex.Node:setRowGap(gap, valueType)
    local newGap = createValue(gap, valueType)
    if self.rowGap.value ~= newGap.value or self.rowGap.type ~= newGap.type then
        self.rowGap = newGap
        self:markDirty()
    end
    return self
end

function LuaFlex.Node:setColumnGap(gap, valueType)
    local newGap = createValue(gap, valueType)
    if self.columnGap.value ~= newGap.value or self.columnGap.type ~= newGap.type then
        self.columnGap = newGap
        self:markDirty()
    end
    return self
end

-- Position setters
function LuaFlex.Node:setPosition(top, right, bottom, left)
    if top then 
        self:setTop(top, LuaFlex.ValueType.Point) 
    end
    if right then 
        self:setRight(right, LuaFlex.ValueType.Point) 
    end
    if bottom then 
        self:setBottom(bottom, LuaFlex.ValueType.Point) 
    end
    if left then 
        self:setLeft(left, LuaFlex.ValueType.Point) 
    end
    return self
end

function LuaFlex.Node:setTop(top, valueType)
    local newTop = createValue(top, valueType)
    if self.top.value ~= newTop.value or self.top.type ~= newTop.type then
        self.top = newTop
        self:markDirty()
    end
    return self
end

function LuaFlex.Node:setRight(right, valueType)
    local newRight = createValue(right, valueType)
    if self.right.value ~= newRight.value or self.right.type ~= newRight.type then
        self.right = newRight
        self:markDirty()
    end
    return self
end

function LuaFlex.Node:setBottom(bottom, valueType)
    local newBottom = createValue(bottom, valueType)
    if self.bottom.value ~= newBottom.value or self.bottom.type ~= newBottom.type then
        self.bottom = newBottom
        self:markDirty()
    end
    return self
end

function LuaFlex.Node:setLeft(left, valueType)
    local newLeft = createValue(left, valueType)
    if self.left.value ~= newLeft.value or self.left.type ~= newLeft.type then
        self.left = newLeft
        self:markDirty()
    end
    return self
end

function LuaFlex.Node:setPositionType(positionType)
    if self.positionType ~= positionType then
        self.positionType = positionType
        self:markDirty()
    end
    return self
end

function LuaFlex.Node:setDisplay(display)
    if self.display ~= display then
        self.display = display
        self:markDirty()
    end
    return self
end

function LuaFlex.Node:setOrder(order)
    if self.order ~= order then
        self.order = order
        -- Order changes affect the parent's layout, not just this node
        if self.parent then
            self.parent:markDirty()
        end
    end
    return self
end

-- Set a custom measure function for intrinsic content sizing
-- measureFunc should be a function(node, availableWidth, availableHeight) -> measuredWidth, measuredHeight
function LuaFlex.Node:setMeasureFunc(measureFunc)
    self.measureFunc = measureFunc
    self:markDirty()
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
            self.parent:markDirty()
        end
    end
end

function LuaFlex.Node:isFlexDirectionRow()
    return self.flexDirection == LuaFlex.FlexDirection.Row or 
           self.flexDirection == LuaFlex.FlexDirection.RowReverse
end

function LuaFlex.Node:isFlexDirectionColumn()
    return self.flexDirection == LuaFlex.FlexDirection.Column or 
           self.flexDirection == LuaFlex.FlexDirection.ColumnReverse
end

function LuaFlex.Node:isFlexDirectionReverse()
    return self.flexDirection == LuaFlex.FlexDirection.RowReverse or 
           self.flexDirection == LuaFlex.FlexDirection.ColumnReverse
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

-- Layout calculation functions

-- Helper function to resolve a value based on parent size
local function resolveValue(value, parentSize)
    if value.type == LuaFlex.ValueType.Point then
        return value.value
    elseif value.type == LuaFlex.ValueType.Percent then
        return (value.value / 100) * parentSize
    elseif value.type == LuaFlex.ValueType.Auto then
        return 0  -- Will be calculated during layout
    else
        return 0
    end
end

-- (Removed several unused helpers to reduce complexity and linter warnings)

-- Helper function to set main axis position
local function setMainAxisPosition(node, position)
    if node:isFlexDirectionRow() then
        node.layout.left = position
    else
        node.layout.top = position
    end
end

-- Helper function to set cross axis position
local function setCrossAxisPosition(node, position)
    if node:isFlexDirectionRow() then
        node.layout.top = position
    else
        node.layout.left = position
    end
end

-- Box model helper functions
local function getMarginLeft(node, parentWidth)
    return resolveValue(node.marginLeft, parentWidth)
end

local function getMarginRight(node, parentWidth)
    return resolveValue(node.marginRight, parentWidth)
end

local function getMarginTop(node, parentHeight)
    return resolveValue(node.marginTop, parentHeight)
end

local function getMarginBottom(node, parentHeight)
    return resolveValue(node.marginBottom, parentHeight)
end

local function getPaddingLeft(node, parentWidth)
    return resolveValue(node.paddingLeft, parentWidth)
end

local function getPaddingRight(node, parentWidth)
    return resolveValue(node.paddingRight, parentWidth)
end

local function getPaddingTop(node, parentHeight)
    return resolveValue(node.paddingTop, parentHeight)
end

local function getPaddingBottom(node, parentHeight)
    return resolveValue(node.paddingBottom, parentHeight)
end

local function getBorderLeft(node)
    return resolveValue(node.borderLeft, 0)  -- Borders are always in points
end

local function getBorderRight(node)
    return resolveValue(node.borderRight, 0)
end

local function getBorderTop(node)
    return resolveValue(node.borderTop, 0)
end

local function getBorderBottom(node)
    return resolveValue(node.borderBottom, 0)
end

-- (Removed unused margin+padding aggregators)

-- Get margin for positioning (margin only, not padding/border)
local function getMainAxisMargin(node, isMainAxisRow, parentWidth, parentHeight)
    if isMainAxisRow then
        return getMarginLeft(node, parentWidth), getMarginRight(node, parentWidth)
    else
        return getMarginTop(node, parentHeight), getMarginBottom(node, parentHeight)
    end
end

local function getCrossAxisMargin(node, isMainAxisRow, parentWidth, parentHeight)
    if isMainAxisRow then
        return getMarginTop(node, parentHeight), getMarginBottom(node, parentHeight)
    else
        return getMarginLeft(node, parentWidth), getMarginRight(node, parentWidth)
    end
end

-- Get the content area (excluding padding and border)
local function getContentArea(node, parentWidth, parentHeight)
    local paddingLeft = getPaddingLeft(node, parentWidth)
    local paddingRight = getPaddingRight(node, parentWidth)
    local paddingTop = getPaddingTop(node, parentHeight)
    local paddingBottom = getPaddingBottom(node, parentHeight)
    
    local borderLeft = getBorderLeft(node)
    local borderRight = getBorderRight(node)
    local borderTop = getBorderTop(node)
    local borderBottom = getBorderBottom(node)
    
    local contentWidth = node.layout.width - paddingLeft - paddingRight - borderLeft - borderRight
    local contentHeight = node.layout.height - paddingTop - paddingBottom - borderTop - borderBottom
    
    return math.max(0, contentWidth), math.max(0, contentHeight)
end

-- Clamp a main-axis size against min/max constraints
local function clampMainAxis(node, isMainAxisRow, size, availableMainSize)
    local minVal, maxVal
    if isMainAxisRow then
        minVal = resolveValue(node.minWidth, availableMainSize)
        maxVal = resolveValue(node.maxWidth, availableMainSize)
    else
        minVal = resolveValue(node.minHeight, availableMainSize)
        maxVal = resolveValue(node.maxHeight, availableMainSize)
    end
    if maxVal > 0 and size > maxVal then
        size = maxVal
    end
    if minVal > 0 and size < minVal then
        size = minVal
    end
    return size
end

-- Calculate the baseline position of a node
local function calculateBaseline(node)
    -- Return cached baseline if available
    if node.baseline.hasBaseline then
        return node.baseline.position
    end
    
    local baselinePosition = 0
    
    -- If node has a custom baseline function, use it
    if node.baselineFunc then
        baselinePosition = node.baselineFunc(node, node.layout.width, node.layout.height)
    else
        -- For flex containers or nodes without baseline function, use the baseline of the first child
        -- or fall back to the bottom of the content area
        if #node.children > 0 then
            -- Find the first child that participates in baseline alignment
            for _, child in ipairs(node.children) do
                if child.display ~= LuaFlex.Display.None and 
                   child.positionType ~= LuaFlex.PositionType.Absolute then
                    local childBaseline = calculateBaseline(child)
                    -- Add the child's position relative to this node
                    local childTop = child:getComputedTop() - node:getComputedTop()
                    baselinePosition = childTop + childBaseline
                    break
                end
            end
        else
            -- No children, use the bottom of the content area as baseline
            local contentTop = getPaddingTop(node, node.layout.height) + getBorderTop(node)
            local contentHeight = node.layout.height - 
                                  getPaddingTop(node, node.layout.height) - 
                                  getPaddingBottom(node, node.layout.height) - 
                                  getBorderTop(node) - getBorderBottom(node)
            baselinePosition = contentTop + contentHeight
        end
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

-- Forward declaration
local measureNode

-- Measure a flex container based on its children
local function measureFlexContainer(node, availableWidth, availableHeight)
    local isMainAxisRow = node:isFlexDirectionRow()
    local totalMainSize = 0
    local maxCrossSize = 0
    
    -- Account for padding and border
    local paddingLeft = getPaddingLeft(node, availableWidth)
    local paddingRight = getPaddingRight(node, availableWidth)
    local paddingTop = getPaddingTop(node, availableHeight)
    local paddingBottom = getPaddingBottom(node, availableHeight)
    local borderLeft = getBorderLeft(node)
    local borderRight = getBorderRight(node)
    local borderTop = getBorderTop(node)
    local borderBottom = getBorderBottom(node)
    
    local contentAvailableWidth = math.max(0, availableWidth - paddingLeft - paddingRight - borderLeft - borderRight)
    local contentAvailableHeight = math.max(0, availableHeight - paddingTop - paddingBottom - borderTop - borderBottom)
    
    -- Measure each child
    for _, child in ipairs(node.children) do
        if child.display ~= LuaFlex.Display.None and child.positionType ~= LuaFlex.PositionType.Absolute then
            local childWidth, childHeight = measureNode(child, contentAvailableWidth, contentAvailableHeight)
            
            -- Add margins
            local childMainMarginStart, childMainMarginEnd = getMainAxisMargin(child, isMainAxisRow, availableWidth, availableHeight)
            local childCrossMarginStart, childCrossMarginEnd = getCrossAxisMargin(child, isMainAxisRow, availableWidth, availableHeight)
            
            local childMainSize = (isMainAxisRow and childWidth or childHeight) + childMainMarginStart + childMainMarginEnd
            local childCrossSize = (isMainAxisRow and childHeight or childWidth) + childCrossMarginStart + childCrossMarginEnd
            
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
local function calculateIntrinsicSize(node, availableWidth, availableHeight)
    local width = 0
    local height = 0
    
    -- If node has explicit dimensions, use them
    if node.width.type == LuaFlex.ValueType.Point then
        width = node.width.value
    elseif node.width.type == LuaFlex.ValueType.Percent then
        width = (node.width.value / 100) * availableWidth
    elseif node.width.type == LuaFlex.ValueType.Auto then
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
    elseif node.height.type == LuaFlex.ValueType.Auto then
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

-- (Removed unused flex factor aggregator)

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
    
    -- If no explicit dimensions, calculate based on content or parent
    if ownWidth == 0 and ownHeight == 0 then
        if self.width.type == LuaFlex.ValueType.Auto or self.height.type == LuaFlex.ValueType.Auto then
            -- Use measured intrinsic size for auto dimensions
            if self.width.type == LuaFlex.ValueType.Auto then
                ownWidth = self.intrinsicSize.width or 0
            else
                ownWidth = parentWidth
            end
            
            if self.height.type == LuaFlex.ValueType.Auto then
                ownHeight = self.intrinsicSize.height or 0
            else
                ownHeight = parentHeight
            end
        else
            ownWidth = parentWidth
            ownHeight = parentHeight
        end
    end
    
    self.layout.width = ownWidth
    self.layout.height = ownHeight
    
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
    if (self.width.type == LuaFlex.ValueType.Auto or self.height.type == LuaFlex.ValueType.Auto) and
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
        
        -- Check if adding this child would exceed available space
        if #currentLine > 0 and (currentLineMainSize + totalChildSize) > availableMainSize then
            -- Start a new line
            table.insert(lines, currentLine)
            currentLine = {}
            table.insert(currentLine, child)
            currentLineMainSize = totalChildSize
        else
            -- Add to current line
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
local function resolveFlexibleLengths(container, lineChildren, availableMainSize, childMainSizes, childMargins, originalIndices)
    local isMainAxisRow = container:isFlexDirectionRow()
    local resolvedSizes = {}
    local lineChildMargins = {}
    
    -- Build line-specific data structures
    for i, child in ipairs(lineChildren) do
        local originalIndex = originalIndices[child]
        
        if originalIndex then
            resolvedSizes[i] = childMainSizes[originalIndex]
            lineChildMargins[i] = childMargins[originalIndex]
        else
            resolvedSizes[i] = 0
            lineChildMargins[i] = {mainStart = 0, mainEnd = 0}
        end
    end
    
    -- Calculate total space used by items and margins
    local totalUsedSpace = 0
    for i, _ in ipairs(lineChildren) do
        local margin = lineChildMargins[i]
        totalUsedSpace = totalUsedSpace + resolvedSizes[i] + margin.mainStart + margin.mainEnd
    end
    
    local remainingSpace = availableMainSize - totalUsedSpace
    
    -- Early exit if no flexible items
    local hasFlexibleItems = false
    for _, child in ipairs(lineChildren) do
        if child.flexGrow > 0 or child.flexShrink > 0 then
            hasFlexibleItems = true
            break
        end
    end
    
    if not hasFlexibleItems then
        return resolvedSizes
    end
    
    -- Apply flexible length resolution algorithm
    if remainingSpace > 0 then
        -- Growing: distribute positive space via flex-grow
        local totalFlexGrow = 0
        for _, child in ipairs(lineChildren) do
            totalFlexGrow = totalFlexGrow + child.flexGrow
        end
        
        if totalFlexGrow > 0 then
            for i, child in ipairs(lineChildren) do
                if child.flexGrow > 0 then
                    local growAmount = (child.flexGrow / totalFlexGrow) * remainingSpace
                    local targetSize = resolvedSizes[i] + growAmount
                    
                    -- Clamp against max constraint
                    targetSize = clampMainAxis(child, isMainAxisRow, targetSize, availableMainSize)
                    resolvedSizes[i] = targetSize
                end
            end
        end
    elseif remainingSpace < 0 then
        -- Shrinking: distribute negative space via flex-shrink
        local totalFlexShrink = 0
        for i, child in ipairs(lineChildren) do
            if child.flexShrink > 0 then
                totalFlexShrink = totalFlexShrink + child.flexShrink * resolvedSizes[i]
            end
        end
        
        if totalFlexShrink > 0 then
            for i, child in ipairs(lineChildren) do
                if child.flexShrink > 0 then
                    local shrinkRatio = (child.flexShrink * resolvedSizes[i]) / totalFlexShrink
                    local shrinkAmount = shrinkRatio * math.abs(remainingSpace)
                    local targetSize = resolvedSizes[i] - shrinkAmount
                    
                    -- Clamp against min constraint
                    targetSize = clampMainAxis(child, isMainAxisRow, targetSize, availableMainSize)
                    resolvedSizes[i] = targetSize
                end
            end
        end
    end
    
    return resolvedSizes
end

-- Position flex items along main axis using justify-content
local function positionFlexItemsMainAxis(container, lineChildren, resolvedMainSizes, 
                                         lineChildMargins, availableMainSize, mainStartOffset)
    local currentMainPosition = mainStartOffset
    local spacing = 0
    
    -- Determine the gap for the main axis
    local mainAxisGap = 0
    if #lineChildren > 1 then
        if container:isFlexDirectionRow() then
            -- Use parent width for columnGap percentage resolution
            mainAxisGap = resolveValue(container.columnGap, container.layout.width) 
        else
            -- Use parent height for rowGap percentage resolution
            mainAxisGap = resolveValue(container.rowGap, container.layout.height)
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
    for i, _ in ipairs(lineChildren) do
        local margin = lineChildMargins[i]
        if margin.mainStartType == LuaFlex.ValueType.Auto or margin.mainEndType == LuaFlex.ValueType.Auto then
            autoMarginCount = autoMarginCount + 1
        end
    end
    
    if autoMarginCount > 0 and remainingSpace > 0 then
        local spacePerAutoMargin = remainingSpace / autoMarginCount
        for i, _ in ipairs(lineChildren) do
            local margin = lineChildMargins[i]
            if margin.mainStartType == LuaFlex.ValueType.Auto then
                margin.mainStart = margin.mainStart + spacePerAutoMargin
            end
            if margin.mainEndType == LuaFlex.ValueType.Auto then
                margin.mainEnd = margin.mainEnd + spacePerAutoMargin
            end
        end
        spacing = 0
    else
        -- Apply justify-content distribution
        if container.justifyContent == LuaFlex.JustifyContent.FlexEnd then
            currentMainPosition = mainStartOffset + remainingSpace
        elseif container.justifyContent == LuaFlex.JustifyContent.Center then
            currentMainPosition = mainStartOffset + remainingSpace / 2
        elseif container.justifyContent == LuaFlex.JustifyContent.SpaceBetween then
            if #lineChildren > 1 then
                spacing = math.max(0, remainingSpace / (#lineChildren - 1))
            end
        elseif container.justifyContent == LuaFlex.JustifyContent.SpaceAround then
            spacing = math.max(0, remainingSpace / #lineChildren)
            currentMainPosition = mainStartOffset + spacing / 2
        elseif container.justifyContent == LuaFlex.JustifyContent.SpaceEvenly then
            spacing = math.max(0, remainingSpace / (#lineChildren + 1))
            currentMainPosition = mainStartOffset + spacing
        end
    end
    
    -- Position each item
    for i, child in ipairs(lineChildren) do
        local margin = lineChildMargins[i]
        currentMainPosition = currentMainPosition + margin.mainStart
        setMainAxisPosition(child, currentMainPosition)
        
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
                          mainStartOffset, crossStartOffset, lineCrossSize, originalIndices)
    local isMainAxisRow = container:isFlexDirectionRow()
    
    -- Step 1: Resolve flexible lengths for this line
    local resolvedMainSizes = resolveFlexibleLengths(container, lineChildren, availableMainSize,
                                                     childMainSizes, childMargins, originalIndices)
    
    -- Step 2: Build line-specific margins for positioning
    local lineChildMargins = {}
    for i, child in ipairs(lineChildren) do
        local originalIndex = originalIndices[child]
        if originalIndex then
            lineChildMargins[i] = childMargins[originalIndex]
        end
    end
    
    -- Step 3: Position items along main axis using justify-content
    positionFlexItemsMainAxis(container, lineChildren, resolvedMainSizes, 
                              lineChildMargins, availableMainSize, mainStartOffset)
    
    -- Step 4: Precompute baseline alignment reference if needed
    local hasBaselineItems = false
    local maxBaselineFromTop = 0
    local baselineItems = {}
    
    for i, child in ipairs(lineChildren) do
        local originalIndex = originalIndices[child]
        if originalIndex then
            local alignSelf = child.alignSelf
            if alignSelf == LuaFlex.AlignSelf.Auto then
                alignSelf = container.alignItems
            end
            if alignSelf == LuaFlex.AlignItems.Baseline then
                local margin = childMargins[originalIndex]
                local crossSizeRaw = childCrossSizes[originalIndex]
                local mainCandidate = resolvedMainSizes[i]
                
                local baseline = 0
                if type(child.baselineFunc) == "function" then
                    local widthCandidate, heightCandidate
                    if isMainAxisRow then
                        widthCandidate = mainCandidate
                        heightCandidate = crossSizeRaw
                    else
                        widthCandidate = crossSizeRaw
                        heightCandidate = mainCandidate
                    end
                    baseline = child.baselineFunc(child, widthCandidate, heightCandidate) or 0
                else
                    -- Use bottom of content area as baseline if no baseline function
                    baseline = crossSizeRaw
                end
                
                local baselineFromTop = margin.crossStart + baseline
                maxBaselineFromTop = math.max(maxBaselineFromTop, baselineFromTop)
                
                baselineItems[i] = {
                    child = child,
                    originalIndex = originalIndex,
                    baseline = baseline,
                    margin = margin,
                    crossSize = crossSizeRaw
                }
                hasBaselineItems = true
            end
        end
    end
    
    -- Step 5: Position children along cross axis and set final dimensions
    for i, child in ipairs(lineChildren) do
        local originalIndex = originalIndices[child]
        
        if originalIndex then
            local alignSelf = child.alignSelf
            if alignSelf == LuaFlex.AlignSelf.Auto then
                alignSelf = container.alignItems
            end
            
            local margin = childMargins[originalIndex]
            local crossPosition = crossStartOffset
            local crossSize = childCrossSizes[originalIndex]
            local availableCrossForChild = lineCrossSize - margin.crossStart - margin.crossEnd
            
            if alignSelf == LuaFlex.AlignItems.FlexEnd then
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
                        local minH = resolveValue(child.minHeight, availableCrossSize)
                        local maxH = resolveValue(child.maxHeight, availableCrossSize)
                        if maxH > 0 and stretchedSize > maxH then
                            stretchedSize = maxH
                        end
                        if minH > 0 and stretchedSize < minH then
                            stretchedSize = minH
                        end
                    else
                        local minW = resolveValue(child.minWidth, availableCrossSize)
                        local maxW = resolveValue(child.maxWidth, availableCrossSize)
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
            
            setCrossAxisPosition(child, crossPosition)
            
            -- Set final dimensions with cross-axis clamping
            local actualMainSize = resolvedMainSizes[i]
            if isMainAxisRow then
                child.layout.width = actualMainSize
                local clampedCross = crossSize
                local minH = resolveValue(child.minHeight, availableCrossSize)
                local maxH = resolveValue(child.maxHeight, availableCrossSize)
                if maxH > 0 and clampedCross > maxH then
                    clampedCross = maxH
                end
                if minH > 0 and clampedCross < minH then
                    clampedCross = minH
                end
                child.layout.height = clampedCross
            else
                local clampedCross = crossSize
                local minW = resolveValue(child.minWidth, availableCrossSize)
                local maxW = resolveValue(child.maxWidth, availableCrossSize)
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
                    offsetY = resolveValue(child.top, parentContentHeight)
                elseif child.bottom.type ~= LuaFlex.ValueType.Undefined then
                    offsetY = -resolveValue(child.bottom, parentContentHeight)
                end

                -- 'left' and 'right' control horizontal offset. 'left' wins if both are set.
                local offsetX = 0
                if child.left.type ~= LuaFlex.ValueType.Undefined then
                    offsetX = resolveValue(child.left, parentContentWidth)
                elseif child.right.type ~= LuaFlex.ValueType.Undefined then
                    offsetX = -resolveValue(child.right, parentContentWidth)
                end
                
                -- Apply the offset to the final computed position
                child.layout.left = child.layout.left + offsetX
                child.layout.top = child.layout.top + offsetY
            end
            
            -- Recursively layout children
            child:calculateLayout(child.layout.width, child.layout.height)
        end
    end
    
    return resolvedMainSizes
end



-- Layout absolutely positioned children
local function layoutAbsoluteChildren(absoluteChildren, contentWidth, contentHeight, 
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
        
        -- Calculate left position
        if hasLeft and hasRight then
            -- Both left and right specified - calculate width and use left
            local leftValue = resolveValue(child.left, contentWidth)
            local rightValue = resolveValue(child.right, contentWidth)
            childWidth = contentWidth - leftValue - rightValue
            childLeft = mainStartOffset + leftValue
        elseif hasLeft then
            -- Only left specified
            childLeft = mainStartOffset + resolveValue(child.left, contentWidth)
        elseif hasRight then
            -- Only right specified
            local rightValue = resolveValue(child.right, contentWidth)
            childLeft = mainStartOffset + contentWidth - childWidth - rightValue
        else
            -- Neither left nor right specified - use current position
            childLeft = mainStartOffset
        end
        
        -- Calculate top position
        if hasTop and hasBottom then
            -- Both top and bottom specified - calculate height and use top
            local topValue = resolveValue(child.top, contentHeight)
            local bottomValue = resolveValue(child.bottom, contentHeight)
            childHeight = contentHeight - topValue - bottomValue
            childTop = crossStartOffset + topValue
        elseif hasTop then
            -- Only top specified
            childTop = crossStartOffset + resolveValue(child.top, contentHeight)
        elseif hasBottom then
            -- Only bottom specified
            local bottomValue = resolveValue(child.bottom, contentHeight)
            childTop = crossStartOffset + contentHeight - childHeight - bottomValue
        else
            -- Neither top nor bottom specified - use current position
            childTop = crossStartOffset
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
    for _, child in ipairs(self.children) do
        if child.display ~= LuaFlex.Display.None then
            if child.positionType == LuaFlex.PositionType.Absolute then
                table.insert(absoluteChildren, child)
            else
                table.insert(children, child)
            end
        end
    end
    
    -- Sort children by order property (lower values come first)
    -- Items with the same order maintain their source document order
    -- Create index map once for O(1) lookups during sorting (avoids O(N² log N) complexity)
    local originalIndices = {}
    for i, child in ipairs(self.children) do
        originalIndices[child] = i
    end
    
    table.sort(children, function(a, b)
        if a.order == b.order then
            -- O(1) index lookup instead of O(N) search
            return originalIndices[a] < originalIndices[b]
        else
            return a.order < b.order
        end
    end)
    
    local isMainAxisRow = self:isFlexDirectionRow()
    
    -- Calculate the content area (available space for children after padding/border)
    local contentWidth, contentHeight = getContentArea(self, self.layout.width, self.layout.height)
    local availableMainSize = isMainAxisRow and contentWidth or contentHeight
    local availableCrossSize = isMainAxisRow and contentHeight or contentWidth
    
    -- Calculate the starting position offset due to padding and border
    local mainStartOffset = 0
    local crossStartOffset = 0
    
    if isMainAxisRow then
        mainStartOffset = getPaddingLeft(self, self.layout.width) + getBorderLeft(self)
        crossStartOffset = getPaddingTop(self, self.layout.height) + getBorderTop(self)
    else
        mainStartOffset = getPaddingTop(self, self.layout.height) + getBorderTop(self)
        crossStartOffset = getPaddingLeft(self, self.layout.width) + getBorderLeft(self)
    end
    
    -- If no normally positioned children, just layout absolute children
    if #children == 0 then
        if #absoluteChildren > 0 then
            layoutAbsoluteChildren(absoluteChildren, contentWidth, contentHeight, 
                                   mainStartOffset, crossStartOffset)
        end
        return
    end
    
    -- Phase 1: Establish flex base size and hypothetical main size
    local childMainSizes = {}
    local childCrossSizes = {}
    local childMargins = {}
    
    for i, child in ipairs(children) do
        -- Compute flex base size (simplified): flex-basis > percent > auto(content) > undefined(content)
        local baseMain
        if child.flexBasis.type == LuaFlex.ValueType.Point then
            baseMain = child.flexBasis.value
        elseif child.flexBasis.type == LuaFlex.ValueType.Percent then
            baseMain = (child.flexBasis.value / 100) * availableMainSize
        else -- flexBasis is auto or undefined
            -- Per spec, 'auto' basis resolves to the main size property if defined, otherwise content size.
            local mainSizeProperty = isMainAxisRow and child.width or child.height
            if mainSizeProperty.type == LuaFlex.ValueType.Point then
                baseMain = mainSizeProperty.value
            elseif mainSizeProperty.type == LuaFlex.ValueType.Percent then
                baseMain = (mainSizeProperty.value / 100) * availableMainSize
            else -- width/height is also auto or undefined, so use content size
                local cw, ch = calculateIntrinsicSize(child,
                    isMainAxisRow and availableMainSize or availableCrossSize,
                    isMainAxisRow and availableCrossSize or availableMainSize)
                baseMain = isMainAxisRow and cw or ch
            end
        end
        baseMain = clampMainAxis(child, isMainAxisRow, baseMain, availableMainSize)
        local cw2, ch2 = calculateIntrinsicSize(child,
            isMainAxisRow and availableMainSize or availableCrossSize,
            isMainAxisRow and availableCrossSize or availableMainSize)
        local baseCross = isMainAxisRow and ch2 or cw2
        
        -- Calculate margins for this child
        local mainMarginStart, mainMarginEnd = getMainAxisMargin(child, isMainAxisRow, 
            self.layout.width, self.layout.height)
        local crossMarginStart, crossMarginEnd = getCrossAxisMargin(child, isMainAxisRow,
            self.layout.width, self.layout.height)
        
        -- Margin data table
        local marginData = {}
        marginData.mainStart = mainMarginStart
        marginData.mainEnd = mainMarginEnd
        marginData.crossStart = crossMarginStart
        marginData.crossEnd = crossMarginEnd
        -- Preserve original margin types for auto-margin handling
        if isMainAxisRow then
            marginData.mainStartType = child.marginLeft.type
            marginData.mainEndType = child.marginRight.type
            marginData.crossStartType = child.marginTop.type
            marginData.crossEndType = child.marginBottom.type
        else
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
                                                 availableMainSize, self.flexWrap)
    
    -- Phase 3 & 4: Resolve flexible lengths per line, then position
    -- lineMainSizes reserved for future refactor; remove to satisfy linter for now
    -- local lineMainSizes = {}
    local lineCrossSizes = {}
    local lineChildMainSizes = {}
    
    -- Calculate cross size for each line first (needed for line layout)
    for lineIndex, lineChildren in ipairs(flexLines) do
        local maxCrossSize = 0
        for _, child in ipairs(lineChildren) do
            local originalIndex = nil
            for j, originalChild in ipairs(children) do
                if originalChild == child then
                    originalIndex = j
                    break
                end
            end
            
            if originalIndex then
                local crossSize = childCrossSizes[originalIndex]
                local margin = childMargins[originalIndex]
                local totalCrossSize = crossSize + margin.crossStart + margin.crossEnd
                maxCrossSize = math.max(maxCrossSize, totalCrossSize)
            end
        end
        
        lineCrossSizes[lineIndex] = maxCrossSize
    end
    
    -- Distribute lines using align-content
    local totalLineCrossSize = 0
    for _, lineSize in ipairs(lineCrossSizes) do
        totalLineCrossSize = totalLineCrossSize + lineSize
    end
    
    -- Determine the gap for the cross axis (between lines)
    local crossAxisGap = 0
    if #flexLines > 1 then
        if isMainAxisRow then
            crossAxisGap = resolveValue(self.rowGap, self.layout.height)
        else
            crossAxisGap = resolveValue(self.columnGap, self.layout.width)
        end
    end
    
    -- Account for gaps in total cross size
    totalLineCrossSize = totalLineCrossSize + (crossAxisGap * (#flexLines > 1 and #flexLines - 1 or 0))

    local remainingCrossSpace = availableCrossSize - totalLineCrossSize
    local currentCrossPosition = crossStartOffset
    local lineSpacing = 0
    
    if #flexLines > 1 then
        if self.alignContent == LuaFlex.AlignContent.FlexEnd then
            currentCrossPosition = crossStartOffset + availableCrossSize - totalLineCrossSize
        elseif self.alignContent == LuaFlex.AlignContent.Center then
            currentCrossPosition = crossStartOffset + remainingCrossSpace / 2
        elseif self.alignContent == LuaFlex.AlignContent.SpaceBetween then
            lineSpacing = remainingCrossSpace / (#flexLines - 1)
        elseif self.alignContent == LuaFlex.AlignContent.SpaceAround then
            lineSpacing = remainingCrossSpace / #flexLines
            currentCrossPosition = crossStartOffset + lineSpacing / 2
        elseif self.alignContent == LuaFlex.AlignContent.SpaceEvenly then
            lineSpacing = remainingCrossSpace / (#flexLines + 1)
            currentCrossPosition = crossStartOffset + lineSpacing
        elseif self.alignContent == LuaFlex.AlignContent.Stretch then
            if remainingCrossSpace > 0 then
                local additionalSpacePerLine = remainingCrossSpace / #flexLines
                for i = 1, #lineCrossSizes do
                    lineCrossSizes[i] = lineCrossSizes[i] + additionalSpacePerLine
                end
            end
        end
    end
    
    -- Layout each flex line
    for lineIndex, lineChildren in ipairs(flexLines) do
        local lineCrossSize = lineCrossSizes[lineIndex]
        
        -- Layout this complete line using the new layoutLine function
        local actualChildMainSizes = layoutLine(self, lineChildren, 
                                                availableMainSize, availableCrossSize,
                                                childMainSizes, childCrossSizes, childMargins,
                                                mainStartOffset, currentCrossPosition, lineCrossSize, originalIndices)
        
        lineChildMainSizes[lineIndex] = actualChildMainSizes
        
        -- Move to next line
        currentCrossPosition = currentCrossPosition + lineCrossSize + lineSpacing
        
        -- Add cross-axis gap if not the last line
        if lineIndex < #flexLines then
            currentCrossPosition = currentCrossPosition + crossAxisGap
        end
    end
    
    -- Layout absolutely positioned children after normal flow
    if #absoluteChildren > 0 then
        layoutAbsoluteChildren(absoluteChildren, contentWidth, contentHeight, 
                               mainStartOffset, crossStartOffset)
    end
    
    -- No object pooling; rely on Lua GC for temporary allocations
end



-- Convenience method for common flex properties
function LuaFlex.Node:setFlex(grow, shrink, basis)
    self:setFlexGrow(grow or 0)
    self:setFlexShrink(shrink or 1)
    self:setFlexBasis(basis, LuaFlex.ValueType.Auto)
    return self
end

-- Method to mark layout as clean
function LuaFlex.Node:markLayoutClean()
    self.isDirty = false
    self.hasNewLayout = false
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

return LuaFlex

