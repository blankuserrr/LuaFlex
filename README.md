# LuaFlex
A performant and portable LuaU layout engine that conforms to the FlexBox specification.

Inspired by Facebook's Yoga, LuaFlex provides a complete flexbox implementation in pure Lua with support for:

- **Complete FlexBox Properties**: flex-direction, justify-content, align-items, flex-grow, flex-shrink, flex-basis
- **Box Model**: Full support for margin, padding, and border calculations
- **Value Types**: Point values, percentages, and auto dimensions  
- **Tree Structure**: Hierarchical node layout with parent-child relationships
- **Performance**: Optimized layout algorithms with dirty-checking

## Quick Start

```lua
local LuaFlex = require("lf_core")

-- Create a container
local container = LuaFlex.Node.new()
    :setWidth(300, LuaFlex.ValueType.Point)
    :setHeight(200, LuaFlex.ValueType.Point)
    :setFlexDirection(LuaFlex.FlexDirection.Row)
    :setJustifyContent(LuaFlex.JustifyContent.SpaceBetween)
    :setAlignItems(LuaFlex.AlignItems.Center)
    :setPadding(10)  -- 10px padding on all sides

-- Create children
local child1 = LuaFlex.Node.new()
    :setWidth(50, LuaFlex.ValueType.Point)
    :setHeight(100, LuaFlex.ValueType.Point)
    :setFlexGrow(1)
    :setMargin(5)  -- 5px margin

local child2 = LuaFlex.Node.new()
    :setWidth(50, LuaFlex.ValueType.Point)
    :setHeight(80, LuaFlex.ValueType.Point)
    :setFlexGrow(2)

-- Build the tree
container:appendChild(child1)
container:appendChild(child2)

-- Calculate layout
container:calculateLayout(300, 200)

-- Access computed layout
print("Container:", container:getComputedWidth(), container:getComputedHeight())
print("Child 1:", child1:getComputedLeft(), child1:getComputedTop(), 
      child1:getComputedWidth(), child1:getComputedHeight())

-- Multi-line example with flex-wrap
local wrapContainer = LuaFlex.Node.new()
    :setWidth(200, LuaFlex.ValueType.Point)
    :setHeight(150, LuaFlex.ValueType.Point)
    :setFlexDirection(LuaFlex.FlexDirection.Row)
    :setFlexWrap(LuaFlex.FlexWrap.Wrap)
    :setAlignContent(LuaFlex.AlignContent.SpaceBetween)

-- Add items that will wrap to multiple lines
for i = 1, 6 do
    local item = LuaFlex.Node.new()
        :setWidth(80, LuaFlex.ValueType.Point)
        :setHeight(30, LuaFlex.ValueType.Point)
    wrapContainer:appendChild(item)
end

wrapContainer:calculateLayout(200, 150)

-- Absolute positioning example
local container = LuaFlex.Node.new()
    :setWidth(300, LuaFlex.ValueType.Point)
    :setHeight(200, LuaFlex.ValueType.Point)
    :setPadding(20)

-- Normal flow child
local normalChild = LuaFlex.Node.new()
    :setWidth(100, LuaFlex.ValueType.Point)
    :setHeight(60, LuaFlex.ValueType.Point)

-- Absolutely positioned child
local absoluteChild = LuaFlex.Node.new()
    :setPositionType(LuaFlex.PositionType.Absolute)
    :setTop(10, LuaFlex.ValueType.Point)
    :setRight(10, LuaFlex.ValueType.Point)
    :setWidth(50, LuaFlex.ValueType.Point)
    :setHeight(30, LuaFlex.ValueType.Point)

container:appendChild(normalChild)
container:appendChild(absoluteChild)
container:calculateLayout(300, 200)

-- Auto dimensions example with custom measure functions
local autoContainer = LuaFlex.Node.new()
    :setWidth(nil, LuaFlex.ValueType.Auto)  -- Size based on content
    :setHeight(nil, LuaFlex.ValueType.Auto)
    :setFlexDirection(LuaFlex.FlexDirection.Column)
    :setPadding(10)

-- Text node with custom measure function
local textNode = LuaFlex.Node.new()
    :setWidth(nil, LuaFlex.ValueType.Auto)
    :setHeight(nil, LuaFlex.ValueType.Auto)
    :setMeasureFunc(function(node, availableWidth, availableHeight)
        -- Simulate text measurement
        return 120, 16  -- 120px wide, 16px tall
    end)

autoContainer:appendChild(textNode)
autoContainer:calculateLayout(400, 300)
-- Container will size itself to fit the text + padding

-- Baseline alignment example for text
local textContainer = LuaFlex.Node.new()
    :setWidth(300, LuaFlex.ValueType.Point)
    :setHeight(60, LuaFlex.ValueType.Point)
    :setFlexDirection(LuaFlex.FlexDirection.Row)
    :setAlignItems(LuaFlex.AlignItems.Baseline)  -- Align text baselines

-- Different sized text elements that align to same baseline
local smallText = LuaFlex.Node.new()
    :setMeasureFunc(function() return 40, 12 end)
    :setBaselineFunc(function(node, w, h) return h * 0.8 end)

local largeText = LuaFlex.Node.new()
    :setMeasureFunc(function() return 60, 24 end)
    :setBaselineFunc(function(node, w, h) return h * 0.8 end)

textContainer:appendChild(smallText)
textContainer:appendChild(largeText)
textContainer:calculateLayout(300, 60)
```

## API Reference

### Core Types

#### FlexDirection
- `LuaFlex.FlexDirection.Column`
- `LuaFlex.FlexDirection.ColumnReverse`  
- `LuaFlex.FlexDirection.Row`
- `LuaFlex.FlexDirection.RowReverse`

#### JustifyContent
- `LuaFlex.JustifyContent.FlexStart`
- `LuaFlex.JustifyContent.FlexEnd`
- `LuaFlex.JustifyContent.Center`
- `LuaFlex.JustifyContent.SpaceBetween`
- `LuaFlex.JustifyContent.SpaceAround` 
- `LuaFlex.JustifyContent.SpaceEvenly`

#### AlignItems
- `LuaFlex.AlignItems.FlexStart`
- `LuaFlex.AlignItems.FlexEnd`
- `LuaFlex.AlignItems.Center`
- `LuaFlex.AlignItems.Stretch`
- `LuaFlex.AlignItems.Baseline`

#### AlignContent (for multi-line layouts)
- `LuaFlex.AlignContent.FlexStart`
- `LuaFlex.AlignContent.FlexEnd`
- `LuaFlex.AlignContent.Center`
- `LuaFlex.AlignContent.Stretch`
- `LuaFlex.AlignContent.SpaceBetween`
- `LuaFlex.AlignContent.SpaceAround`
- `LuaFlex.AlignContent.SpaceEvenly`

#### FlexWrap
- `LuaFlex.FlexWrap.NoWrap` - Single line (default)
- `LuaFlex.FlexWrap.Wrap` - Allow wrapping to new lines
- `LuaFlex.FlexWrap.WrapReverse` - Wrap with reversed line order

#### PositionType
- `LuaFlex.PositionType.Static` - Normal document flow (default)
- `LuaFlex.PositionType.Relative` - Relative to normal position
- `LuaFlex.PositionType.Absolute` - Positioned relative to container

#### ValueType
- `LuaFlex.ValueType.Point` - Absolute pixel values
- `LuaFlex.ValueType.Percent` - Percentage of parent
- `LuaFlex.ValueType.Auto` - Automatic sizing
- `LuaFlex.ValueType.Undefined` - No value specified

### Node Methods

#### Layout Properties
```lua
node:setFlexDirection(direction)
node:setJustifyContent(justify) 
node:setAlignItems(align)
node:setAlignContent(align)  -- For multi-line layouts
node:setFlexWrap(wrap)
node:setFlexGrow(grow)
node:setFlexShrink(shrink)
node:setFlexBasis(basis, valueType)
node:setPositionType(positionType)
```

#### Dimensions
```lua
node:setWidth(width, valueType)
node:setHeight(height, valueType)
-- For auto dimensions, use LuaFlex.ValueType.Auto
node:setWidth(nil, LuaFlex.ValueType.Auto)  -- Size based on content
```

#### Content Measurement
```lua
-- Set a custom measure function for content sizing
node:setMeasureFunc(function(node, availableWidth, availableHeight)
    -- Return the intrinsic size of your content
    return measuredWidth, measuredHeight
end)

-- Set a custom baseline function for text alignment
node:setBaselineFunc(function(node, width, height)
    -- Return the distance from top of content to text baseline
    return baselinePosition
end)
```

#### Box Model
```lua
node:setMargin(top, right, bottom, left)
node:setPadding(top, right, bottom, left)
node:setPosition(top, right, bottom, left)
```

#### Tree Manipulation
```lua
node:appendChild(child)
node:removeChild(child)
node:getChildCount()
node:getChild(index)
```

#### Layout Calculation
```lua
node:calculateLayout(parentWidth, parentHeight)
node:getComputedLeft()
node:getComputedTop()
node:getComputedWidth()
node:getComputedHeight()
node:getBaseline()  -- Get text baseline position
```

#### Performance and Memory Management
```lua
-- Object pool management (automatic, but configurable)
LuaFlex.getPoolStats()  -- Get current pool statistics
LuaFlex.setMaxPoolSize(200)  -- Configure max pool size (default: 100)
LuaFlex.clearObjectPools()  -- Force clear all pools (rarely needed)
```

## Current Status

✅ **Implemented Features:**
- Core flexbox properties (flex-direction, justify-content, align-items)
- **Multi-line layouts** with flex-wrap support (wrap, nowrap, wrap-reverse)
- **align-content** for distributing flex lines
- **Absolute positioning** with top/left/right/bottom support
- **Auto dimension resolution** with custom measure functions and multi-pass layout
- **Baseline alignment** with custom baseline functions for text alignment
- Flex grow/shrink/basis calculations with multi-line support
- Complete box model (margin, padding, border)
- Value types (point, percent, auto)
- Tree structure and layout propagation

🔄 **Optional Enhancements:**
- position: relative support
- Additional flexbox edge cases

## Performance

LuaFlex uses efficient algorithms and memory management:
- **Object pooling** - Recycles temporary tables to minimize garbage collection pressure
- Dirty flag system to avoid unnecessary recalculations
- **Multi-pass layout** with intelligent caching for auto dimensions
- Single-pass layout algorithm for simple cases
- Optimized flex distribution calculations
- Content measurement caching to avoid redundant calculations

### High-Frequency Updates
For applications with frequent layout updates (60+ FPS), LuaFlex automatically:
- Pools and reuses temporary arrays during layout calculations
- Caches measurement and baseline calculations
- Minimizes memory allocations in hot paths
- Provides configurable pool sizes for memory-constrained environments 