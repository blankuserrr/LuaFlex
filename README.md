# LuaFlex
A performant and portable Lua layout engine that conforms to the FlexBox specification.

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
    :setWidth(300)
    :setHeight(200)
    :setFlexDirection(LuaFlex.FlexDirection.Row)
    :setJustifyContent(LuaFlex.JustifyContent.SpaceBetween)
    :setAlignItems(LuaFlex.AlignItems.Center)
    :setPadding(10)  -- 10px padding on all sides

-- Create children
local child1 = LuaFlex.Node.new()
    :setWidth(50)
    :setHeight(100)
    :setFlexGrow(1)
    :setMargin(5)  -- 5px margin

local child2 = LuaFlex.Node.new()
    :setWidth(50)
    :setHeight(80)
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
    :setWidth(200)
    :setHeight(150)
    :setFlexDirection(LuaFlex.FlexDirection.Row)
    :setFlexWrap(LuaFlex.FlexWrap.Wrap)
    :setAlignContent(LuaFlex.AlignContent.SpaceBetween)

-- Add items that will wrap to multiple lines
for i = 1, 6 do
    local item = LuaFlex.Node.new()
        :setWidth(80)
        :setHeight(30)
    wrapContainer:appendChild(item)
end

wrapContainer:calculateLayout(200, 150)

-- Absolute positioning example
local container = LuaFlex.Node.new()
    :setWidth(300)
    :setHeight(200)
    :setPadding(20)

-- Normal flow child
local normalChild = LuaFlex.Node.new()
    :setWidth(100)
    :setHeight(60)

-- Absolutely positioned child
local absoluteChild = LuaFlex.Node.new()
    :setPositionType(LuaFlex.PositionType.Absolute)
    :setTop(10)
    :setRight(10)
    :setWidth(50)
    :setHeight(30)

container:appendChild(normalChild)
container:appendChild(absoluteChild)
container:calculateLayout(300, 200)

-- Auto dimensions example with custom measure functions
local autoContainer = LuaFlex.Node.new()
    :setWidth("auto")  -- Size based on content
    :setHeight("auto")
    :setFlexDirection(LuaFlex.FlexDirection.Column)
    :setPadding(10)

-- Text node with custom measure function
local textNode = LuaFlex.Node.new()
    :setWidth("auto")
    :setHeight("auto")
    :setMeasureFunc(function(node, availableWidth, availableHeight)
        -- Simulate text measurement
        return 120, 16  -- 120px wide, 16px tall
    end)

autoContainer:appendChild(textNode)
autoContainer:calculateLayout(400, 300)
-- Container will size itself to fit the text + padding

-- Baseline alignment example for text
local textContainer = LuaFlex.Node.new()
    :setWidth(300)
    :setHeight(60)
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

-- Visual reordering with order property
local container = LuaFlex.Node.new()
    :setWidth(200)
    :setHeight(100)
    :setFlexDirection(LuaFlex.FlexDirection.Row)

-- Create items in source order: A, B, C
local itemA = LuaFlex.Node.new():setOrder(2)  -- Will appear last
local itemB = LuaFlex.Node.new():setOrder(1)  -- Will appear middle  
local itemC = LuaFlex.Node.new():setOrder(0)  -- Will appear first

container:appendChild(itemA)  -- Added first
container:appendChild(itemB)  -- Added second
container:appendChild(itemC)  -- Added third

container:calculateLayout(200, 100)
-- Visual order will be: C, B, A (not A, B, C)
-- But tab order and screen readers still use source order: A, B, C

-- Relative positioning example
local container = LuaFlex.Node.new()
    :setWidth(300)
    :setHeight(200)
    :setFlexDirection(LuaFlex.FlexDirection.Row)

-- Normal flex item
local item1 = LuaFlex.Node.new()
    :setWidth(100)
    :setHeight(50)

-- Relatively positioned item - offset from its normal position
local item2 = LuaFlex.Node.new()
    :setWidth(100)
    :setHeight(50)
    :setPositionType(LuaFlex.PositionType.Relative)
    :setTop(10)    -- Move 10px down from normal position
    :setLeft(20)   -- Move 20px right from normal position

-- Another normal item
local item3 = LuaFlex.Node.new()
    :setWidth(100)
    :setHeight(50)

container:appendChild(item1)
container:appendChild(item2)
container:appendChild(item3)

container:calculateLayout(300, 200)
-- item2 will appear visually offset but still "holds space" in the layout
-- Other items position as if item2 were in its original location
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
node:setOrder(order)  -- Controls visual order of items
node:setFlexGrow(grow)
node:setFlexShrink(shrink)
node:setFlexBasis(basis)
node:setPositionType(positionType)
```

#### Dimensions
```lua
node:setWidth(width)
node:setHeight(height)
node:setMinWidth(width)
node:setMinHeight(height)
node:setMaxWidth(width)
node:setMaxHeight(height)
-- width/height can be a number (e.g. 100) or a string ("100", "50%", "auto")
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
-- All box model values can be a number or a string ("10", "10%")
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

#### Batched Updates
For performance, you can batch multiple style changes to trigger a single layout recalculation.
```lua
node:batch(function(n)
    n:setWidth(100)
    n:setHeight(200)
    n:setMargin(5)
end)
-- markDirty() is only called once after the function completes.
```


## Current Status

✅ **Implemented Features:**
- Core flexbox properties (flex-direction, justify-content, align-items)
- **Multi-line layouts** with flex-wrap support (wrap, nowrap, wrap-reverse)
- **align-content** for distributing flex lines
- **Visual reordering** with the order property
- **Absolute positioning** with top/left/right/bottom support
- **Relative positioning** with visual offset from normal layout position
- **Auto dimension resolution** with custom measure functions and multi-pass layout
- **Baseline alignment** with custom baseline functions for text alignment
- Flex grow/shrink/basis calculations with multi-line support
- Complete box model (margin, padding, border)
- Value types (point, percent, auto)
- Tree structure and layout propagation

🔄 **Optional Enhancements:**
- Enhanced line breaking algorithm (considers flex-shrink during partitioning)
- Additional flexbox edge cases

## Performance

LuaFlex uses efficient algorithms and memory management:
- **Correct CSS Flexbox implementation** - Follows the W3C specification algorithm precisely
- **Optimized Subtree Recalculation (Dirty Checking)**: LuaFlex intelligently recomputes only the parts of the layout tree that have changed, avoiding unnecessary full recalculations.
- **Multi-pass layout** with intelligent caching for auto dimensions
- Proper flexible length resolution with min/max constraint handling
- Optimized flex distribution calculations
- Content measurement caching to avoid redundant calculations
- Integrated baseline alignment without post-processing

### Optimized Subtree Recalculation (Dirty Checking)

LuaFlex tracks changes at the node level using dirty flags. All public setters (for example, `:setWidth`, `:setPadding`, `:setFlexGrow`, `:setPositionType`) mark the node and its ancestors as dirty so the engine knows which subtrees need recomputation. When `:calculateLayout` runs, only dirty subtrees are recomputed, dramatically reducing work for incremental updates. To benefit from this optimization, always use the provided setter methods rather than mutating node fields directly.

### Algorithm Correctness
LuaFlex now implements the correct CSS Flexbox algorithm:
- **Proper flex-grow/flex-shrink distribution** with constraint handling
- **Correct justify-content spacing** using remaining space after flexible length resolution
- **Accurate align-items: stretch** respecting min/max constraints
- **Integrated baseline alignment** computed during cross-axis positioning
- **Separation of concerns** between flexible length resolution and positioning