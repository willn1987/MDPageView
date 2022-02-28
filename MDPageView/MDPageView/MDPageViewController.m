//
//  MDPageViewController.m
//  MDPageView
//
//  Created by hq on 2022/2/22.
//


#import "MDPageViewController.h"

/// 页面滚动方向
typedef NS_ENUM(NSInteger, MDPageScrollDirection) {
    MDPageScrollDirection_Right,
    MDPageScrollDirection_Left,
};

@interface MDPageViewController () <UIScrollViewDelegate>

/// 底部滚动视图(视图容器)
@property (nonatomic, strong) UIScrollView *baseScrollView;

/// 视图控制器列表
@property (nonatomic, strong) NSArray<UIViewController *> *viewControllers;

/// 已添加的视图控制器索引（用于在页面切换结束后移除非相邻的页面）
@property (nonatomic, strong) NSMutableArray<NSNumber *> *addedVCIndexs;

/// 页面总数
@property (nonatomic, assign) NSInteger pageCount;

/// 当前显示视图在列表中的索引
@property (nonatomic, assign) NSInteger currentPageIndex;

/// 上一次显示视图的索引
@property (nonatomic, assign) NSInteger lastPageIndex;

/// 手势拖动时将要前往页面的索引
@property (nonatomic, assign) NSInteger toPageIndex;

/// 手势拖动时记录ContentoffSet.x 判断滑动方向
@property (nonatomic, assign) CGFloat originOffsetX;

@end

@implementation MDPageViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.toPageIndex = -1;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    // 首次不调用
    [[self viewControllerAtIndex:self.currentPageIndex] beginAppearanceTransition:YES animated:YES];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    [[self viewControllerAtIndex:self.currentPageIndex] endAppearanceTransition];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    
    [[self viewControllerAtIndex:self.currentPageIndex] beginAppearanceTransition:NO animated:YES];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    
    [[self viewControllerAtIndex:self.currentPageIndex] endAppearanceTransition];
}

/// （关键）不自动调用子控制器的生命周期方法
- (BOOL)shouldAutomaticallyForwardAppearanceMethods {
    return NO;
}

/// 已添加的视图控制器索引（用于在页面切换结束后移除非相邻的页面）
- (NSMutableArray<NSNumber *> *)addedVCIndexs {
    if (!_addedVCIndexs) {
        _addedVCIndexs = @[].mutableCopy;
    }
    return _addedVCIndexs;
}

/// 滚动视图(视图容器)
- (UIScrollView *)baseScrollView {
    if (!_baseScrollView) {
        _baseScrollView = [[UIScrollView alloc] init];
        _baseScrollView.delegate = self;
        _baseScrollView.bounces = NO;
        _baseScrollView.pagingEnabled = YES;
        _baseScrollView.showsVerticalScrollIndicator = NO;
        _baseScrollView.showsHorizontalScrollIndicator = NO;
        _baseScrollView.frame = self.view.bounds;
        [self.view addSubview:_baseScrollView];
    }
    return _baseScrollView;
}

/// 当前显示视图的索引
- (NSInteger)currentPageIndex {
    return _currentPageIndex;
}

/// 获取页面总数
- (NSInteger)pageCount {
    return self.viewControllers.count;
}

/// 获取索引对应的视图控制器
/// @param index 索引
- (UIViewController *)viewControllerAtIndex:(NSInteger)index {
    return index >= self.viewControllers.count ? nil : self.viewControllers[index];
}

#pragma mark -
#pragma mark - 更新视图和控制器

/// 设置控制器列表
/// @param viewControllers 控制器列表
/// @param index 要展示的页面索引
- (void)setViewControllers:(nullable NSArray<UIViewController *> *)viewControllers
                     index:(NSInteger)index {
    self.viewControllers = viewControllers;
    self.currentPageIndex = index;
    [self updateScrollViewContentSize];

    [self addChildViewControllerWithIndex:index];
//    [[self viewControllerWithIndex:index] beginAppearanceTransition:YES animated:NO];
//    [[self viewControllerWithIndex:index] endAppearanceTransition];
    [self addNeighbourViewControllerWithIndex:index];

    [self updateScrollViewContentOffset:NO];
}

/// 显示指定位置的页面
/// @param index 页面索引
/// @param animated 是否动画（如果开启动画，则自定义视图动画直线滑动效果）
- (void)showPageAtIndex:(NSInteger)index animated:(BOOL)animated {
    
    if (index < 0 || index >= self.viewControllers.count || index == self.currentPageIndex) {
        return;
    }
    
    // 记录索引
    NSInteger oldPageIndex = self.lastPageIndex;
    self.lastPageIndex = self.currentPageIndex;
    self.currentPageIndex = index;
    
    // 添加当前索引对应视图
    [self addChildViewControllerWithIndex:index];
    
    // 滚动准备开始
    void (^scrollBeginAnimation)(void) = ^(void) {
        [[self viewControllerAtIndex:self.currentPageIndex] beginAppearanceTransition:NO animated:NO];
        [[self viewControllerAtIndex:self.lastPageIndex] beginAppearanceTransition:YES animated:NO];
    };
    
    // 滚动结束
    void (^scrollEndAnimation)(void) = ^(void) {
        // 更新视图内容位置
        [self updateScrollViewContentOffset:NO];
        
        [[self viewControllerAtIndex:self.currentPageIndex] endAppearanceTransition];
        [[self viewControllerAtIndex:self.lastPageIndex] endAppearanceTransition];
        
        // 将多余视图移除
        [self removeNotNeighbourViewController];
        
        // 将当前视图的前后视图添加预加载
        [self addNeighbourViewControllerWithIndex:self.currentPageIndex];
        
        !self.viewDidChangedCallBack ?: self.viewDidChangedCallBack(self.currentPageIndex, self.lastPageIndex);
    };
    
    // ********************** 未启用动画切换
    if (!animated) {
        // 执行准备滚动
        scrollBeginAnimation();
        // 直接切换，不执行动画
        scrollEndAnimation();
        
        return;
    }
    
    // ********************** 启用动画切换
    
    // 页面视图的size
    CGSize pageSize = self.baseScrollView.frame.size;
    
    // 动画页面
    UIView *oldView = [self viewControllerAtIndex:oldPageIndex].view;
    UIView *lastView = [self viewControllerAtIndex:self.lastPageIndex].view;
    UIView *currentView = [self viewControllerAtIndex:self.currentPageIndex].view;
    
    UIView *backgroundView = nil;
    // 用户快速点击切换页面，即前一次切换动画未结束时，又发起了新的页面切换
    // 触发他们完成页面生命周期调用，将要消失的视图要及时切换
    if (oldView.layer.animationKeys.count > 0 && lastView.layer.animationKeys.count > 0) {
        
        [[self viewControllerAtIndex:self.lastPageIndex] endAppearanceTransition];
        [[self viewControllerAtIndex:oldPageIndex] endAppearanceTransition];
        !self.viewDidChangedCallBack ?: self.viewDidChangedCallBack(self.lastPageIndex, oldPageIndex);
        
        UIView *tmepView = [self viewControllerAtIndex:self.baseScrollView.contentOffset.x / pageSize.width].view;
        if (tmepView != currentView && tmepView != lastView) {
            backgroundView = tmepView;
            [UIView animateWithDuration:2 animations:^{
                backgroundView.hidden = YES;
            }];
        }
    }
    
    // 执行准备滚动
    scrollBeginAnimation();
    
    // 移除当前在执行的动画（用户可能在快速点击切换）
    [self.baseScrollView.layer removeAllAnimations];
    [oldView.layer removeAllAnimations];
    [lastView.layer removeAllAnimations];
    [currentView.layer removeAllAnimations];
    
    // 恢复oldView的坐标
    [self moveBackToOriginPositionIfNeeded:oldView index:oldPageIndex];
    
    // 将执行动画的视图层级提到前面，避免遮挡
    [self.baseScrollView bringSubviewToFront:lastView];
    [self.baseScrollView bringSubviewToFront:currentView];
    
    // 计算执行动画的视图的开始,移动目标和结束时的位置
    CGPoint lastView_StartOrigin = lastView.frame.origin;
    CGPoint lastView_MoveToOrigin = lastView.frame.origin;
    CGPoint lastView_EndOrigin = lastView.frame.origin;
    
    CGPoint currtentView_StartOrigin = lastView.frame.origin;
    CGPoint currtentView_MoveToOrigin = lastView.frame.origin;
    CGPoint currtentView_EndOrigin = currentView.frame.origin;
    
    // 根据滚动方向调整视图的x坐标
    if (self.lastPageIndex < self.currentPageIndex) {
        currtentView_StartOrigin.x += pageSize.width;
        lastView_MoveToOrigin.x -= pageSize.width;
    } else {
        currtentView_StartOrigin.x -= pageSize.width;
        lastView_MoveToOrigin.x += pageSize.width;
    }
    
    // 调整动画的两个视图frame到相邻位置
    lastView.frame = CGRectMake(lastView_StartOrigin.x, lastView_StartOrigin.y, pageSize.width, pageSize.height);
    currentView.frame = CGRectMake(currtentView_StartOrigin.x, currtentView_StartOrigin.y, pageSize.width, pageSize.height);
    
    // 执行页面切换动画
    [UIView animateWithDuration:0.3 animations:^{
        lastView.frame = CGRectMake(lastView_MoveToOrigin.x, lastView_MoveToOrigin.y, pageSize.width, pageSize.height);
        currentView.frame = CGRectMake(currtentView_MoveToOrigin.x, currtentView_MoveToOrigin.y, pageSize.width, pageSize.height);
    } completion:^(BOOL finished) {
        if (finished) {
            lastView.frame = CGRectMake(lastView_EndOrigin.x, lastView_EndOrigin.y, pageSize.width, pageSize.height);
            currentView.frame = CGRectMake(currtentView_EndOrigin.x, currtentView_EndOrigin.y, pageSize.width, pageSize.height);
            
            backgroundView.hidden = NO;
            
            // 恢复视图坐标
            [self moveBackToOriginPositionIfNeeded:currentView index:self.currentPageIndex];
            [self moveBackToOriginPositionIfNeeded:lastView index:self.lastPageIndex];
            
            // 动画结束
            scrollEndAnimation();
        }
    }];
}

/// 计算索引对应视图的frame
/// @param index 视图索引
- (CGRect)calcChildViewFrameWithIndex:(NSInteger)index {
    CGFloat x = index * (CGFloat)self.baseScrollView.frame.size.width;
    return CGRectMake(x, 0, self.baseScrollView.bounds.size.width, self.baseScrollView.bounds.size.height);
}

/// 计算索引对应的offSet
/// @param index 视图索引
- (CGPoint)calcOffsetWithIndex:(NSInteger)index {
    CGFloat width = (CGFloat)self.baseScrollView.frame.size.width;
    CGFloat maxWidth = (CGFloat)self.baseScrollView.contentSize.width;
    CGFloat offsetX = MAX(0, index * width);
    
    if (maxWidth > 0.0 && offsetX > maxWidth - width) {
        offsetX = maxWidth - width;
    }
    
    return CGPointMake(offsetX, 0);
}

/// 更新滚动视图内容size
- (void)updateScrollViewContentSize {
    CGFloat width = MAX(self.baseScrollView.bounds.size.width, self.pageCount * self.baseScrollView.bounds.size.width);
    CGSize size = CGSizeMake(width, self.baseScrollView.bounds.size.height);
    
    if (!CGSizeEqualToSize(size, self.baseScrollView.contentSize)) {
        [self.baseScrollView setContentSize: size];
    }
}

/// 更新视图内容位置
/// @param animations 是否开始动画
- (void)updateScrollViewContentOffset:(BOOL)animations {
    CGFloat x = MAX(self.currentPageIndex * self.baseScrollView.bounds.size.width, 0);
    [self.baseScrollView setContentOffset:CGPointMake(x, 0) animated:animations];
}

/// 添加与索引相邻的视图
/// @param index 索引
- (void)addNeighbourViewControllerWithIndex:(NSInteger)index {
    [self addChildViewControllerWithIndex:index - 1];
    [self addChildViewControllerWithIndex:index + 1];
}

/// 添加视图控制器
/// @param index 索引
- (void)addChildViewControllerWithIndex:(NSInteger)index {
    UIViewController *controller = [self viewControllerAtIndex:index];
    if (!controller) {
        return;
    }
    BOOL isContainsVC = [self.childViewControllers containsObject:controller];
    if (!isContainsVC) {
        [self addChildViewController:controller];
    }
    
    controller.view.frame = [self calcChildViewFrameWithIndex:index];
    controller.view.hidden = NO;
    if (![self.baseScrollView.subviews containsObject:controller.view]) {
        [self.baseScrollView addSubview:controller.view];
    }
    
    if (!isContainsVC) {
        [controller didMoveToParentViewController:self];
    }
    
    // 记录已添加页面的索引
    NSNumber *indexNum = @(index);
    if (![self.addedVCIndexs containsObject:indexNum]) {
        [self.addedVCIndexs addObject:indexNum];
    }
}

/// 移除视图控制器
/// @param index 索引
- (void)removeChildViewControllerWithIndex:(NSInteger)index {
    if (index == self.currentPageIndex || index + 1 == self.currentPageIndex || index - 1 == self.currentPageIndex) {
        return;
    }
    UIViewController *controller = [self viewControllerAtIndex:index];
    [controller willMoveToParentViewController:nil];
    [controller.view removeFromSuperview];
    [controller removeFromParentViewController];
}

/// 移除非相邻视图控制器
/// @param index 索引
- (void)removeNotNeighbourViewControllerWithIndex:(NSInteger)index {
    [self removeChildViewControllerWithIndex:index];
    [self removeChildViewControllerWithIndex:index - 1];
    [self removeChildViewControllerWithIndex:index + 1];
}

/// 移除非相邻视图控制器
- (void)removeNotNeighbourViewController {
    NSArray<NSNumber *> *remove = [self.addedVCIndexs filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSNumber *  _Nullable obj, NSDictionary<NSString *,id> * _Nullable bindings) {
        NSInteger index = obj.integerValue;
        return self.currentPageIndex != index && self.currentPageIndex - 1 != index && self.currentPageIndex + 1 != index;
    }]];
    
    [remove enumerateObjectsUsingBlock:^(NSNumber * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        [self removeChildViewControllerWithIndex:obj.integerValue];
    }];
}

/// 将视图位置移动到原始位置
/// @param view 视图
/// @param index 视图控制器索引
- (void)moveBackToOriginPositionIfNeeded:(UIView *)view index:(NSInteger)index {
    if (index < 0 || index >= self.pageCount || view == nil) {
        return;
    }
    
    UIView *destView = view;
    CGPoint originPosition = [self calcOffsetWithIndex:index];
    if (destView.frame.origin.x != originPosition.x) {
        CGRect newFrame = destView.frame;
        newFrame.origin = originPosition;
        destView.frame = newFrame;
    }
}

#pragma mark -
#pragma mark - UIScrollViewDelegate

/// 列表滚动中 （需要实时计算并回调索引的变更）
/// isDragging 表示滚动是否由用户手势滑动引起
/// isTracking 表示当前滚动是否是跟随手指的滑动
/// isDecelerating 表示正在减速滚动
- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
//    NSLog(@"isTracking: %@   isDecelerating: %@   isDragging: %@", @(scrollView.isTracking), @(scrollView.isDecelerating), @(scrollView.isDragging));
    
    // 回调滚动数据
    !self.viewScrollCallBack ?: self.viewScrollCallBack(scrollView.contentOffset, scrollView.contentSize, scrollView.isDragging);
    
    // 忽略由[setContentOffset:animated:]等非手势滑动引起的滚动
    if (!scrollView.isDragging && !scrollView.isTracking && !scrollView.isDecelerating) {
        return;
    }
    
    CGFloat offsetX = (CGFloat)scrollView.contentOffset.x;
    CGFloat pageWidth = (CGFloat)scrollView.frame.size.width;
    
    // 根据当前滑动方向实时计算将要前往的页面
    NSInteger newToPage = 0;
    if (self.originOffsetX < offsetX) {
        newToPage = ceil(offsetX / pageWidth);
    } else {
        newToPage = floor(offsetX / pageWidth);
    }
    
    // 滑到了有效页面之外
    if (newToPage < 0 || newToPage >= self.pageCount) {
        return;
    }
    
    // 从页面静止状态开始滑动
    if (self.toPageIndex < 0 && newToPage >= 0 && newToPage < self.pageCount) {
        
        // 向边界外滑动
        if (newToPage == self.currentPageIndex) {
            return;
        }
        
        self.toPageIndex = newToPage;
        self.lastPageIndex = self.currentPageIndex;
        
        // 新页面将要滑出
        [self addChildViewControllerWithIndex:self.toPageIndex];
        [self addNeighbourViewControllerWithIndex:self.toPageIndex];
        [[self viewControllerAtIndex:self.toPageIndex] beginAppearanceTransition:YES animated:YES];
        [[self viewControllerAtIndex:self.currentPageIndex] beginAppearanceTransition:NO animated:YES];
        !self.viewWillChangedCallBack ?: self.viewWillChangedCallBack(self.toPageIndex , self.currentPageIndex);
        
        return;
    }
    
    // 页面执行滑动中
    if (newToPage != self.toPageIndex) {
        
        [[self viewControllerAtIndex:self.toPageIndex] endAppearanceTransition];
        [[self viewControllerAtIndex:self.currentPageIndex] endAppearanceTransition];
        !self.viewDidChangedCallBack ?: self.viewDidChangedCallBack(self.toPageIndex , self.currentPageIndex);
        
        // 处理前后反复滑动时子页面生命周期触发缺失的问题（如从1往0滑再往2滑）
        if (ABS(self.toPageIndex - newToPage) >= 2) {
            [[self viewControllerAtIndex:self.currentPageIndex] beginAppearanceTransition:YES animated:YES];
            [[self viewControllerAtIndex:self.toPageIndex] beginAppearanceTransition:NO animated:YES];
            !self.viewWillChangedCallBack ?: self.viewWillChangedCallBack(self.currentPageIndex , self.toPageIndex);
            
            [[self viewControllerAtIndex:self.currentPageIndex] endAppearanceTransition];
            [[self viewControllerAtIndex:self.toPageIndex] endAppearanceTransition];
            !self.viewDidChangedCallBack ?: self.viewDidChangedCallBack(self.currentPageIndex , self.toPageIndex);
            
            self.toPageIndex = self.currentPageIndex;
        } else {
            self.currentPageIndex = self.toPageIndex;
        }
        
        [self addChildViewControllerWithIndex:newToPage];
        [self addNeighbourViewControllerWithIndex:newToPage];
        
        [[self viewControllerAtIndex:newToPage] beginAppearanceTransition:YES animated:YES];
        [[self viewControllerAtIndex:self.toPageIndex] beginAppearanceTransition:NO animated:YES];
        !self.viewWillChangedCallBack ?: self.viewWillChangedCallBack(newToPage , self.toPageIndex);
        
        self.toPageIndex = newToPage;
    }
}

/// 手指拖动 即将开始
- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
//    NSLog(@"手指拖动 即将开始  ==================== new start");
    if (!scrollView.isDecelerating) {
        self.originOffsetX = (CGFloat)scrollView.contentOffset.x;
    }
}

/// 手指拖动 结束时
/// decelerate为YES时列表会惯性滑动， 为NO时列表直接静止
- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    if (!decelerate) {
//        NSLog(@"手指拖动 结束时 页面直接停止");
        [self scrollViewDidEnd:scrollView];
    } else {
//        NSLog(@"手指拖动 结束时 页面继续减速滑动");
    }
}

/// 自动滚动结束时,即调用setContentOffset/scrollRectVisible:animated:等函数并且animated为YES时引发的滑动
- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView {
//    NSLog(@"方法调用引起的滑动 结束");
    [self scrollViewDidEnd:scrollView];
}

/// 手指拖动引起的滚动开始时
- (void)scrollViewWillBeginDecelerating:(UIScrollView *)scrollView {
//    NSLog(@"手指拖动 离开时 滑动开始减速 isDecelerating: %@", @(scrollView.isDecelerating));
}

/// 手指拖动引起的滚动结束时
- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    [self scrollViewDidEnd:scrollView];
//    NSLog(@"手指拖动 离开后 引起的滑动结束 isDecelerating: %@", @(scrollView.isDecelerating));
}

/// 列表最终滚动结束时
- (void)scrollViewDidEnd:(UIScrollView *)scrollView {
    NSLog(@"scroll end =================================");
    
    if (self.currentPageIndex != self.toPageIndex && self.toPageIndex >= 0) {
        [[self viewControllerAtIndex:self.toPageIndex] endAppearanceTransition];
        [[self viewControllerAtIndex:self.currentPageIndex] endAppearanceTransition];
        !self.viewDidChangedCallBack ?: self.viewDidChangedCallBack(self.toPageIndex , self.currentPageIndex);
        
        self.currentPageIndex = self.toPageIndex;
        
        // 移除多余视图
        [self removeNotNeighbourViewController];
    }

    self.originOffsetX = (CGFloat)scrollView.contentOffset.x;
    self.toPageIndex = -1;
}

@end
