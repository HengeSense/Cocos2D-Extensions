//
//  SWTableView.m
//  SWGameLib
//
//  Copyright (c) 2010 Sangwoo Im
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//
//
//  Created by Sangwoo Im on 6/3/10.
//  Copyright 2010 Sangwoo Im. All rights reserved.
//

#import "SWTableView.h"
#import "SWTableViewCell.h"
#import "CCMenu.h"
#import "CGPointExtension.h"
#import "SWSorting.h"
#import "CCLayer.h"

@interface SWScrollView()
@property (nonatomic, assign) BOOL    touchMoved_;
@property (nonatomic, retain) CCLayer *container_;
@property (nonatomic, assign) CGPoint touchPoint_;

@end

@interface SWTableView ()
-(NSInteger)__indexFromOffset:(CGPoint)offset;
-(NSUInteger)_indexFromOffset:(CGPoint)offset;
-(CGPoint)__offsetFromIndex:(NSInteger)index;
-(CGPoint)_offsetFromIndex:(NSUInteger)index;
-(void)_updateContentSize;

@end

@interface SWTableView (Private)
- (SWTableViewCell *)_cellWithIndex:(NSUInteger)cellIndex;
- (void)_moveCellOutOfSight:(SWTableViewCell *)cell;
- (void)_setIndex:(NSUInteger)index forCell:(SWTableViewCell *)cell;
- (void)_addCellIfNecessary:(SWTableViewCell *)cell;
@end

@implementation SWTableView
@synthesize delegate   = tDelegate_;
@synthesize dataSource = dataSource_;
@synthesize verticalFillOrder  = vordering_;

+(id)viewWithDataSource:(id<SWTableViewDataSource>)dataSource size:(CGSize)size {
    return [self viewWithDataSource:dataSource size:size container:nil];
}

+(id)viewWithDataSource:(id <SWTableViewDataSource>)dataSource size:(CGSize)size container:(CCNode *)container {
    SWTableView *table;
    table = [[[self alloc] initWithViewSize:size container:container] autorelease];
    table.dataSource = dataSource;
    [table _updateContentSize];
    return table;
}
-(id)initWithViewSize:(CGSize)size container:(CCNode *)container {
    if ((self = [super initWithViewSize:size container:container])) {
        cellsUsed_      = [NSMutableArray new];
        cellsFreed_     = [NSMutableArray new];
        indices_        = [NSMutableIndexSet new];
        tDelegate_      = nil;
        vordering_      = SWTableViewFillBottomUp;
        self.direction  = SWScrollViewDirectionVertical;
        
        [super setDelegate:self];
    }
    return self;
}
-(void)dealloc {
    [indices_    release];
    [cellsUsed_  release];
    [cellsFreed_ release];
    [super dealloc];
}
#pragma mark -
#pragma mark property
-(void)setVerticalFillOrder:(SWTableViewVerticalFillOrder)fillOrder {
    if (vordering_ != fillOrder) {
        vordering_ = fillOrder;
        if ([cellsUsed_ count] > 0) {
            [self reloadData];
        }
    }
}
#pragma mark -
#pragma mark public

-(void)reloadData {
    NSAutoreleasePool *pool;
    
    pool = [NSAutoreleasePool new];
    for (SWTableViewCell *cell in cellsUsed_) {
        [cellsFreed_ addObject:cell];
        [cell reset];
        if (cell.parent == self.container_) {
            [container_ removeChild:cell cleanup:YES];
        }
    }
    [indices_ removeAllIndexes];
    [cellsUsed_ release];
    cellsUsed_ = [NSMutableArray new];
    
    [self _updateContentSize];
    if ([dataSource_ numberOfCellsInTableView:self] > 0) {
        [self scrollViewDidScroll:self];
    }
    [pool drain];
}

-(SWTableViewCell *)cellAtIndex:(NSUInteger)idx {
    return [self _cellWithIndex:idx];
}
-(void)updateCellAtIndex:(NSUInteger)idx {
    if (idx == NSNotFound || idx > [dataSource_ numberOfCellsInTableView:self]-1) {
        return;
    }
    
    SWTableViewCell   *cell;
    
    cell = [self _cellWithIndex:idx];
    if (cell) {
        [self _moveCellOutOfSight:cell];
    }
    cell = [dataSource_ table:self cellAtIndex:idx];
    [self _setIndex:idx forCell:cell];
    [self _addCellIfNecessary:cell];
}
-(void)insertCellAtIndex:(NSUInteger)idx {
    if (idx == NSNotFound || idx > [dataSource_ numberOfCellsInTableView:self]-1) {
        return;
    }
    SWTableViewCell   *cell;
    NSInteger         newIdx;
    
    cell        = [cellsUsed_ objectWithObjectID:idx];
    if (cell) {
        newIdx = [cellsUsed_ indexOfSortedObject:cell];
        for (int i=newIdx; i<[cellsUsed_ count]; i++) {
            cell = [cellsUsed_ objectAtIndex:i];
            [self _setIndex:cell.idx+1 forCell:cell];
        }
    }
    
    [indices_ shiftIndexesStartingAtIndex:idx by:1];
    
    //insert a new cell
    cell = [dataSource_ table:self cellAtIndex:idx];
    [self _setIndex:idx forCell:cell];
    [self _addCellIfNecessary:cell];
    
    [self _updateContentSize];
}
-(void)removeCellAtIndex:(NSUInteger)idx {
    if (idx == NSNotFound || idx > [dataSource_ numberOfCellsInTableView:self]-1) {
        return;
    }
    
    SWTableViewCell   *cell;
    NSInteger         newIdx;
    
    cell = [self _cellWithIndex:idx];
    if (!cell) {
        return;
    }
    
    newIdx = [cellsUsed_ indexOfSortedObject:cell];
    
    //remove first
    [self _moveCellOutOfSight:cell];
    
    [indices_ shiftIndexesStartingAtIndex:idx+1 by:-1];
    for (int i=[cellsUsed_ count]-1; i > newIdx; i--) {
        cell = [cellsUsed_ objectAtIndex:i];
        [self _setIndex:cell.idx-1 forCell:cell];
    }
}
-(SWTableViewCell *)dequeueCell {
    SWTableViewCell *cell;
    
    if ([cellsFreed_ count] == 0) {
        cell = nil;
    } else {
        cell = [[cellsFreed_ objectAtIndex:0] retain];
        [cellsFreed_ removeObjectAtIndex:0];
    }
    return [cell autorelease];
}
#pragma mark -
#pragma mark private

- (void)_addCellIfNecessary:(SWTableViewCell *)cell {
    if (cell.parent != self.container_) {
        [self.container_ addChild:cell];
    }
    [cellsUsed_ insertSortedObject:cell];
    [indices_ addIndex:cell.idx];
}
- (void)_updateContentSize {
    CGSize     size, cellSize;
    NSUInteger cellCount;
    
    cellSize  = [dataSource_ cellSizeForTable:self];
    cellCount = [dataSource_ numberOfCellsInTableView:self];

    switch (self.direction) {
        case SWScrollViewDirectionHorizontal:
            size = CGSizeMake(cellCount * cellSize.width, cellSize.height);
            size.width  = MAX(size.width,  viewSize_.width);
            break;
        default:
            size = CGSizeMake(cellSize.width, cellCount * cellSize.height);
            size.height = MAX(size.height, viewSize_.height);
            break;
    }
    [self setContentSize:size];
}
- (CGPoint)_offsetFromIndex:(NSUInteger)index {
    CGPoint offset = [self __offsetFromIndex:index];
    
    const CGSize cellSize = [dataSource_ cellSizeForTable:self];
    if (vordering_ == SWTableViewFillTopDown) {
        offset.y = container_.contentSize.height - offset.y - cellSize.height;
    }
    return offset;
}
- (CGPoint)__offsetFromIndex:(NSInteger)index {
    CGPoint offset;
    CGSize  cellSize;
    
    cellSize = [dataSource_ cellSizeForTable:self];
    switch (self.direction) {
        case SWScrollViewDirectionHorizontal:
            offset = ccp(cellSize.width * index, 0.0f);
            break;
        default:
            offset = ccp(0.0f, cellSize.height * index);
            break;
    }
    
    return offset;
}
- (NSUInteger)_indexFromOffset:(CGPoint)offset {
    NSInteger index;
    const NSInteger maxIdx = [dataSource_ numberOfCellsInTableView:self]-1;
    
    const CGSize cellSize = [dataSource_ cellSizeForTable:self];
    if (vordering_ == SWTableViewFillTopDown) {
        offset.y = container_.contentSize.height - offset.y - cellSize.height;
    }
    index = MAX(0, [self __indexFromOffset:offset]);
    index = MIN(index, maxIdx);
    return index;
}
- (NSInteger)__indexFromOffset:(CGPoint)offset {
    NSInteger  index;
    CGSize     cellSize;
    
    cellSize = [dataSource_ cellSizeForTable:self];
    
    switch (self.direction) {
        case SWScrollViewDirectionHorizontal:
            index = offset.x/cellSize.width;
            break;
        default:
            index = offset.y/cellSize.height;
            break;
    }
    
    return index;
}
- (SWTableViewCell *)_cellWithIndex:(NSUInteger)cellIndex {
    SWTableViewCell *found;
    
    found = nil;
    
    if ([indices_ containsIndex:cellIndex]) {
        found = (SWTableViewCell *)[cellsUsed_ objectWithObjectID:cellIndex];
    }
    
    return found;
}
- (void)_moveCellOutOfSight:(SWTableViewCell *)cell {
    [cellsFreed_ addObject:cell];
    [cellsUsed_ removeSortedObject:cell];
    [indices_ removeIndex:cell.idx];
    [cell reset];
    if (cell.parent == self.container_) {
        [container_ removeChild:cell cleanup:YES];
    }
}
- (void)_setIndex:(NSUInteger)index forCell:(SWTableViewCell *)cell {
    cell.anchorPoint = ccp(0.0f, 0.0f);
    cell.position    = [self _offsetFromIndex:index];
    cell.idx         = index;
}

#pragma mark -
#pragma mark scrollView

-(void)scrollViewDidScroll:(SWScrollView *)view {
    NSUInteger        startIdx, endIdx, idx, maxIdx;
    CGPoint           offset;
    NSAutoreleasePool *pool;
    
    maxIdx   = [dataSource_ numberOfCellsInTableView:self];
    
    if (maxIdx == 0) {
        return; // early termination
    }
    
    pool     = [NSAutoreleasePool new];
    offset   = ccpMult([self contentOffset], -1);
    maxIdx   = MAX(maxIdx - 1, 0);
    
    const CGSize cellSize = [dataSource_ cellSizeForTable:self];
    
    if (vordering_ == SWTableViewFillTopDown) {
        offset.y = offset.y + viewSize_.height/container_.scaleY - cellSize.height;
    }
    startIdx = [self _indexFromOffset:offset];
    if (vordering_ == SWTableViewFillTopDown) {
        offset.y -= viewSize_.height/container_.scaleY;
    } else {
        offset.y += viewSize_.height/container_.scaleY;
    }
    offset.x += viewSize_.width/container_.scaleX;
    
    endIdx   = [self _indexFromOffset:offset];
    
    
    if ([cellsUsed_ count] > 0) {
        idx = [[cellsUsed_ objectAtIndex:0] idx];
        while(idx <startIdx) {
            SWTableViewCell *cell = [cellsUsed_ objectAtIndex:0];
            [self _moveCellOutOfSight:cell];
            if ([cellsUsed_ count] > 0) {
                idx = [[cellsUsed_ objectAtIndex:0] idx];
            } else {
                break;
            }
        }
    }
    if ([cellsUsed_ count] > 0) {
        idx = [[cellsUsed_ lastObject] idx];
        while(idx <= maxIdx && idx > endIdx) {
            SWTableViewCell *cell = [cellsUsed_ lastObject];
            [self _moveCellOutOfSight:cell];
            if ([cellsUsed_ count] > 0) {
                idx = [[cellsUsed_ lastObject] idx];
            } else {
                break;
            }
        }
    }
    
    for (NSUInteger i=startIdx; i <= endIdx; i++) {
        if ([indices_ containsIndex:i]) {
            continue;
        }
        [self updateCellAtIndex:i];
    }
    [pool drain];
}

#pragma mark -
#pragma mark Touch events

-(void)ccTouchEnded:(UITouch *)touch withEvent:(UIEvent *)event {
    if (!self.visible) {
        return;
    }
    if ([touches_ count] == 1 && !self.touchMoved_) {
        NSUInteger        index;
        SWTableViewCell   *cell;
        CGPoint           point;
        
        point = [container_ convertTouchToNodeSpace:touch];
        if (vordering_ == SWTableViewFillTopDown) {
            CGSize cellSize = [dataSource_ cellSizeForTable:self];
            point.y -= cellSize.height;
        }
        index = [self _indexFromOffset:point];
        cell  = [self _cellWithIndex:index];
        
        if (cell) {
            [tDelegate_ table:self cellTouched:cell];
        }
    }
    [super ccTouchEnded:touch withEvent:event];
}
@end

