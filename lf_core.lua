-- LuaFlex: A performant and portable LuaU layout engine that conforms to the FlexBox specification
-- Inspired by Facebook's Yoga

local LuaFlex = {}

-- Object pool for reducing GC pressure during layout calculations
local ObjectPool = {
    arrays = {},
    tables = {},
    maxPoolSize = 100  -- Prevent unbounded growth
}

-- Get a recycled array or create a new one
local function getArray()
    if #ObjectPool.arrays > 0 then
        local array = table.remove(ObjectPool.arrays)
        -- Clear the array (but keep the table allocated)
        for i = #array, 1, -1 do
            array[i] = nil
        end
        return array
    else
        return {}
    end
end

-- Return an array to the pool for reuse
local function recycleArray(array)
    if #ObjectPool.arrays < ObjectPool.maxPoolSize then
        table.insert(ObjectPool.arrays, array)
    end
end

-- Get a recycled table or create a new one
local function getTable()
    if #ObjectPool.tables > 0 then
        local tbl = table.remove(ObjectPool.tables)
        -- Clear the table (but keep it allocated)
        for k in pairs(tbl) do
            tbl[k] = nil
        end
        return tbl
    else
        return {}
    end
end

-- Return a table to the pool for reuse
local function recycleTable(tbl)
    if #ObjectPool.tables < ObjectPool.maxPoolSize then
        table.insert(ObjectPool.tables, tbl)
    end
end

-- Clear all pools (useful for memory management)
function LuaFlex.clearObjectPools()
    ObjectPool.arrays = {}
    ObjectPool.tables = {}
end

-- Get pool statistics (useful for debugging)
function LuaFlex.getPoolStats()
    return {
        arrays = #ObjectPool.arrays,
        tables = #ObjectPool.tables,
        maxSize = ObjectPool.maxPoolSize
    }
end

-- Configure the maximum pool size (useful for memory-constrained environments)
function LuaFlex.setMaxPoolSize(size)
    ObjectPool.maxPoolSize = math.max(0, size or 100)
    
    -- Trim pools if they exceed the new limit
    while #ObjectPool.arrays > ObjectPool.maxPoolSize do
        table.remove(ObjectPool.arrays)
    end
    while #ObjectPool.tables > ObjectPool.maxPoolSize do
        table.remove(ObjectPool.tables)
    end
end

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

function LuaFlex.Node.new()
    local node = {
        -- Style properties
        flexDirection = LuaFlex.FlexDirection.Column,
        justifyContent = LuaFlex.JustifyContent.FlexStart,
        alignItems = LuaFlex.AlignItems.Stretch,
        alignSelf = LuaFlex.AlignSelf.Auto,
        alignContent = LuaFlex.AlignContent.Stretch,
        flexWrap = LuaFlex.FlexWrap.NoWrap,
        positionType = LuaFlex.PositionType.Static,
        display = LuaFlex.Display.Flex,
        
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
    
    return setmetatable(node, LuaFlex.Node)
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

-- Helper function to get the main axis size
local function getMainAxisSize(node)
    if node:isFlexDirectionRow() then
        return node.layout.width
    else
        return node.layout.height
    end
end

-- Helper function to get the cross axis size
local function getCrossAxisSize(node)
    if node:isFlexDirectionRow() then
        return node.layout.height
    else
        return node.layout.width
    end
end

-- Helper function to set main axis size
local function setMainAxisSize(node, size)
    if node:isFlexDirectionRow() then
        node.layout.width = size
    else
        node.layout.height = size
    end
end

-- Helper function to set cross axis size
local function setCrossAxisSize(node, size)
    if node:isFlexDirectionRow() then
        node.layout.height = size
    else
        node.layout.width = size
    end
end

-- Helper function to get main axis position
local function getMainAxisPosition(node)
    if node:isFlexDirectionRow() then
        return node.layout.left
    else
        return node.layout.top
    end
end

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

-- Calculate total margin, padding, border for main axis
local function getMainAxisMarginPaddingBorder(node, isMainAxisRow, parentWidth, parentHeight)
    if isMainAxisRow then
        return getMarginLeft(node, parentWidth) + getMarginRight(node, parentWidth) +
               getPaddingLeft(node, parentWidth) + getPaddingRight(node, parentWidth) +
               getBorderLeft(node) + getBorderRight(node)
    else
        return getMarginTop(node, parentHeight) + getMarginBottom(node, parentHeight) +
               getPaddingTop(node, parentHeight) + getPaddingBottom(node, parentHeight) +
               getBorderTop(node) + getBorderBottom(node)
    end
end

-- Calculate total margin, padding, border for cross axis
local function getCrossAxisMarginPaddingBorder(node, isMainAxisRow, parentWidth, parentHeight)
    if isMainAxisRow then
        return getMarginTop(node, parentHeight) + getMarginBottom(node, parentHeight) +
               getPaddingTop(node, parentHeight) + getPaddingBottom(node, parentHeight) +
               getBorderTop(node) + getBorderBottom(node)
    else
        return getMarginLeft(node, parentWidth) + getMarginRight(node, parentWidth) +
               getPaddingLeft(node, parentWidth) + getPaddingRight(node, parentWidth) +
               getBorderLeft(node) + getBorderRight(node)
    end
end

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

-- Calculate the total flex grow and shrink factors
local function calculateFlexFactors(children)
    local totalFlexGrow = 0
    local totalFlexShrink = 0
    
    for _, child in ipairs(children) do
        if child.display ~= LuaFlex.Display.None then
            totalFlexGrow = totalFlexGrow + child.flexGrow
            totalFlexShrink = totalFlexShrink + child.flexShrink
        end
    end
    
    return totalFlexGrow, totalFlexShrink
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
        local singleLine = getArray()
        for _, child in ipairs(children) do
            table.insert(singleLine, child)
        end
        local lines = getArray()
        table.insert(lines, singleLine)
        return lines
    end
    
    local lines = getArray()
    local currentLine = getArray()
    local currentLineMainSize = 0
    
    for i, child in ipairs(children) do
        local childSize = childMainSizes[i]
        local margin = childMargins[i]
        local totalChildSize = childSize + margin.mainStart + margin.mainEnd
        
        -- Check if adding this child would exceed available space
        if #currentLine > 0 and (currentLineMainSize + totalChildSize) > availableMainSize then
            -- Start a new line
            table.insert(lines, currentLine)
            currentLine = getArray()
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

-- Layout a single flex line
local function layoutFlexLine(self, lineChildren, availableMainSize, availableCrossSize, 
                              childMainSizes, childCrossSizes, childMargins, isMainAxisRow, 
                              mainStartOffset, crossStartOffset)
    
    -- Calculate flex grow/shrink for this line
    local lineTotalIntrinsicMainSize = 0
    local lineChildMainSizes = getArray()
    local lineChildMargins = getArray()
    
    for i, child in ipairs(lineChildren) do
        -- Find the original index of this child
        local originalIndex = nil
        for j, originalChild in ipairs(self.children) do
            if originalChild == child then
                originalIndex = j
                break
            end
        end
        
        if originalIndex then
            lineChildMainSizes[i] = childMainSizes[originalIndex]
            lineChildMargins[i] = childMargins[originalIndex]
            local margin = childMargins[originalIndex]
            lineTotalIntrinsicMainSize = lineTotalIntrinsicMainSize + 
                childMainSizes[originalIndex] + margin.mainStart + margin.mainEnd
        end
    end
    
    local remainingSpace = availableMainSize - lineTotalIntrinsicMainSize
    
    -- Distribute remaining space based on flex-grow/flex-shrink
    if remainingSpace > 0 then
        -- Growing
        local totalFlexGrow = 0
        for _, child in ipairs(lineChildren) do
            if child.display ~= LuaFlex.Display.None then
                totalFlexGrow = totalFlexGrow + child.flexGrow
            end
        end
        
        if totalFlexGrow > 0 then
            for i, child in ipairs(lineChildren) do
                if child.flexGrow > 0 then
                    local growAmount = (child.flexGrow / totalFlexGrow) * remainingSpace
                    lineChildMainSizes[i] = lineChildMainSizes[i] + growAmount
                end
            end
        end
    elseif remainingSpace < 0 then
        -- Shrinking
        local totalFlexShrink = 0
        for _, child in ipairs(lineChildren) do
            if child.display ~= LuaFlex.Display.None then
                totalFlexShrink = totalFlexShrink + child.flexShrink
            end
        end
        
        if totalFlexShrink > 0 then
            for i, child in ipairs(lineChildren) do
                if child.flexShrink > 0 then
                    local shrinkAmount = (child.flexShrink / totalFlexShrink) * math.abs(remainingSpace)
                    lineChildMainSizes[i] = math.max(0, lineChildMainSizes[i] - shrinkAmount)
                end
            end
        end
    end
    
    -- Position children in this line based on justify-content
    local currentMainPosition = mainStartOffset
    local spacing = 0
    
    if self.justifyContent == LuaFlex.JustifyContent.FlexEnd then
        currentMainPosition = mainStartOffset + availableMainSize
        for i = #lineChildren, 1, -1 do
            local margin = lineChildMargins[i]
            currentMainPosition = currentMainPosition - lineChildMainSizes[i] - margin.mainEnd
            setMainAxisPosition(lineChildren[i], currentMainPosition + margin.mainStart)
            currentMainPosition = currentMainPosition - margin.mainStart
        end
    elseif self.justifyContent == LuaFlex.JustifyContent.Center then
        local totalUsedSpace = lineTotalIntrinsicMainSize
        currentMainPosition = mainStartOffset + (availableMainSize - totalUsedSpace) / 2
        
        for i, child in ipairs(lineChildren) do
            local margin = lineChildMargins[i]
            currentMainPosition = currentMainPosition + margin.mainStart
            setMainAxisPosition(child, currentMainPosition)
            currentMainPosition = currentMainPosition + lineChildMainSizes[i] + margin.mainEnd
        end
    elseif self.justifyContent == LuaFlex.JustifyContent.SpaceBetween then
        if #lineChildren > 1 then
            spacing = math.max(0, remainingSpace / (#lineChildren - 1))
        end
        
        for i, child in ipairs(lineChildren) do
            local margin = lineChildMargins[i]
            currentMainPosition = currentMainPosition + margin.mainStart
            setMainAxisPosition(child, currentMainPosition)
            currentMainPosition = currentMainPosition + lineChildMainSizes[i] + margin.mainEnd + spacing
        end
    elseif self.justifyContent == LuaFlex.JustifyContent.SpaceAround then
        spacing = math.max(0, remainingSpace / #lineChildren)
        currentMainPosition = mainStartOffset + spacing / 2
        
        for i, child in ipairs(lineChildren) do
            local margin = lineChildMargins[i]
            currentMainPosition = currentMainPosition + margin.mainStart
            setMainAxisPosition(child, currentMainPosition)
            currentMainPosition = currentMainPosition + lineChildMainSizes[i] + margin.mainEnd + spacing
        end
    elseif self.justifyContent == LuaFlex.JustifyContent.SpaceEvenly then
        spacing = math.max(0, remainingSpace / (#lineChildren + 1))
        currentMainPosition = mainStartOffset + spacing
        
        for i, child in ipairs(lineChildren) do
            local margin = lineChildMargins[i]
            currentMainPosition = currentMainPosition + margin.mainStart
            setMainAxisPosition(child, currentMainPosition)
            currentMainPosition = currentMainPosition + lineChildMainSizes[i] + margin.mainEnd + spacing
        end
    else -- FlexStart (default)
        for i, child in ipairs(lineChildren) do
            local margin = lineChildMargins[i]
            currentMainPosition = currentMainPosition + margin.mainStart
            setMainAxisPosition(child, currentMainPosition)
            currentMainPosition = currentMainPosition + lineChildMainSizes[i] + margin.mainEnd
        end
    end
    
    -- Note: lineChildMainSizes is returned to the caller and will be recycled by them
    -- Only recycle lineChildMargins here
    recycleArray(lineChildMargins)
    
    return lineChildMainSizes
end

-- Layout absolutely positioned children
local function layoutAbsoluteChildren(self, absoluteChildren, contentWidth, contentHeight, 
                                      mainStartOffset, crossStartOffset, isMainAxisRow)
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
    local children = getArray()
    local absoluteChildren = getArray()
    
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
            layoutAbsoluteChildren(self, absoluteChildren, contentWidth, contentHeight, 
                                   mainStartOffset, crossStartOffset, isMainAxisRow)
        end
        -- Recycle arrays before returning
        recycleArray(children)
        recycleArray(absoluteChildren)
        return
    end
    
    -- Calculate intrinsic sizes for all children
    local childMainSizes = getArray()
    local childCrossSizes = getArray()
    local childMargins = getArray()
    
    for i, child in ipairs(children) do
        local childWidth, childHeight = calculateIntrinsicSize(child, 
            isMainAxisRow and availableMainSize or availableCrossSize,
            isMainAxisRow and availableCrossSize or availableMainSize)
        
        -- Calculate main and cross sizes
        local mainSize = isMainAxisRow and childWidth or childHeight
        local crossSize = isMainAxisRow and childHeight or childWidth
        
        -- Handle flex-basis
        if child.flexBasis.type == LuaFlex.ValueType.Point then
            mainSize = child.flexBasis.value
        elseif child.flexBasis.type == LuaFlex.ValueType.Percent then
            mainSize = (child.flexBasis.value / 100) * availableMainSize
        end
        
        -- Calculate margins for this child
        local mainMarginStart, mainMarginEnd = getMainAxisMargin(child, isMainAxisRow, 
            self.layout.width, self.layout.height)
        local crossMarginStart, crossMarginEnd = getCrossAxisMargin(child, isMainAxisRow,
            self.layout.width, self.layout.height)
        
        -- Use pooled table for margin data
        local marginData = getTable()
        marginData.mainStart = mainMarginStart
        marginData.mainEnd = mainMarginEnd
        marginData.crossStart = crossMarginStart
        marginData.crossEnd = crossMarginEnd
        childMargins[i] = marginData
        
        childMainSizes[i] = mainSize
        childCrossSizes[i] = crossSize
    end
    
    -- Partition children into flex lines
    local flexLines = partitionChildrenIntoLines(children, childMainSizes, childMargins, 
                                                 availableMainSize, self.flexWrap)
    
    -- Layout each flex line
    local lineMainSizes = getArray()
    local lineCrossSizes = getArray()
    local lineChildMainSizes = getArray()
    
    for lineIndex, lineChildren in ipairs(flexLines) do
        -- Layout this line
        local actualChildMainSizes = layoutFlexLine(self, lineChildren, availableMainSize, 
                                                     availableCrossSize, childMainSizes, 
                                                     childCrossSizes, childMargins, 
                                                     isMainAxisRow, mainStartOffset, crossStartOffset)
        
        lineChildMainSizes[lineIndex] = actualChildMainSizes
        
        -- Calculate the cross size needed by this line
        local maxCrossSize = 0
        for i, child in ipairs(lineChildren) do
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
    
    -- Position children based on align-items within each line
    for lineIndex, lineChildren in ipairs(flexLines) do
        local lineCrossSize = lineCrossSizes[lineIndex]
        
        for i, child in ipairs(lineChildren) do
            local originalIndex = nil
            for j, originalChild in ipairs(children) do
                if originalChild == child then
                    originalIndex = j
                    break
                end
            end
            
            if originalIndex then
                local alignSelf = child.alignSelf
                if alignSelf == LuaFlex.AlignSelf.Auto then
                    alignSelf = self.alignItems
                end
                
                local margin = childMargins[originalIndex]
                local crossPosition = currentCrossPosition
                local crossSize = childCrossSizes[originalIndex]
                local availableCrossForChild = lineCrossSize - margin.crossStart - margin.crossEnd
                
                if alignSelf == LuaFlex.AlignItems.FlexEnd then
                    crossPosition = currentCrossPosition + lineCrossSize - crossSize - margin.crossEnd
                elseif alignSelf == LuaFlex.AlignItems.Center then
                    crossPosition = currentCrossPosition + margin.crossStart + (availableCrossForChild - crossSize) / 2
                elseif alignSelf == LuaFlex.AlignItems.Stretch then
                    if self.alignContent == LuaFlex.AlignContent.Stretch and #flexLines > 1 then
                        crossSize = math.max(0, availableCrossForChild)
                    end
                    crossPosition = currentCrossPosition + margin.crossStart
                elseif alignSelf == LuaFlex.AlignItems.Baseline then
                    -- Baseline alignment - align all items in this line to the same baseline
                    crossPosition = currentCrossPosition + margin.crossStart
                    -- This will be adjusted later in baseline alignment pass
                else -- FlexStart (default)
                    crossPosition = currentCrossPosition + margin.crossStart
                end
                
                setCrossAxisPosition(child, crossPosition)
                
                -- Set final dimensions
                local actualMainSize = lineChildMainSizes[lineIndex] and lineChildMainSizes[lineIndex][i] or childMainSizes[originalIndex]
                if isMainAxisRow then
                    child.layout.width = actualMainSize
                    child.layout.height = crossSize
                else
                    child.layout.width = crossSize
                    child.layout.height = actualMainSize
                end
                
                -- Recursively layout children
                child:calculateLayout(child.layout.width, child.layout.height)
            end
        end
        
        -- Perform baseline alignment pass for this line
        self:performBaselineAlignment(lineChildren, currentCrossPosition, isMainAxisRow)
        
        currentCrossPosition = currentCrossPosition + lineCrossSize + lineSpacing
    end
    
    -- Layout absolutely positioned children after normal flow
    if #absoluteChildren > 0 then
        layoutAbsoluteChildren(self, absoluteChildren, contentWidth, contentHeight, 
                               mainStartOffset, crossStartOffset, isMainAxisRow)
    end
    
    -- Recycle all pooled objects to reduce GC pressure
    recycleArray(children)
    recycleArray(absoluteChildren)
    recycleArray(childMainSizes)
    recycleArray(childCrossSizes)
    
    -- Recycle margin data tables
    for i = 1, #childMargins do
        recycleTable(childMargins[i])
    end
    recycleArray(childMargins)
    
    -- Recycle line data
    recycleArray(lineMainSizes)
    recycleArray(lineCrossSizes)
    
    -- Recycle individual line child main size arrays
    for i = 1, #lineChildMainSizes do
        if lineChildMainSizes[i] then
            recycleArray(lineChildMainSizes[i])
        end
    end
    recycleArray(lineChildMainSizes)
    
    -- flexLines is returned by partitionChildrenIntoLines, so recycle it too
    recycleArray(flexLines)
end

-- Perform baseline alignment for children in a flex line
function LuaFlex.Node:performBaselineAlignment(lineChildren, lineCrossStart, isMainAxisRow)
    -- Find all children that need baseline alignment
    local baselineChildren = getArray()
    local maxBaseline = 0
    
    -- First pass: collect baseline children and find the maximum baseline
    for _, child in ipairs(lineChildren) do
        local alignSelf = child.alignSelf
        if alignSelf == LuaFlex.AlignSelf.Auto then
            alignSelf = self.alignItems
        end
        
        if alignSelf == LuaFlex.AlignItems.Baseline then
            table.insert(baselineChildren, child)
            
            -- Calculate this child's baseline
            local baseline = calculateBaseline(child)
            maxBaseline = math.max(maxBaseline, baseline)
        end
    end
    
    -- If no baseline children, nothing to do
    if #baselineChildren == 0 then
        return
    end
    
    -- Second pass: adjust positions of baseline children
    for _, child in ipairs(baselineChildren) do
        local childBaseline = calculateBaseline(child)
        local baselineOffset = maxBaseline - childBaseline
        
        -- Get current cross position and adjust by baseline offset
        local currentCrossPos = isMainAxisRow and child.layout.top or child.layout.left
        local newCrossPos = lineCrossStart + baselineOffset
        
        -- Find child's margins
        local originalIndex = nil
        for i, originalChild in ipairs(self.children) do
            if originalChild == child then
                originalIndex = i
                break
            end
        end
        
        if originalIndex then
            local crossMarginStart, _ = getCrossAxisMargin(child, isMainAxisRow, 
                self.layout.width, self.layout.height)
            newCrossPos = newCrossPos + crossMarginStart
        end
        
        -- Apply the new position
        setCrossAxisPosition(child, newCrossPos)
        
        -- Invalidate baseline cache since position changed
        child:invalidateBaseline()
        
        -- Re-layout the child if its position changed significantly
        if math.abs(newCrossPos - currentCrossPos) > 0.001 then
            child:calculateLayout(child.layout.width, child.layout.height)
        end
    end
    
    -- Recycle the baseline children array
    recycleArray(baselineChildren)
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
