//
//  MDPageBaseScrollView.m
//  MDPageViewController
//
//  Created by hq on 2022/3/21.
//

#import "MDPageBaseScrollView.h"

@implementation MDPageBaseScrollView

// 返回YES，允许多个视图同时响起手势事件（允许手势同时透传到父视图）
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    if ([otherGestureRecognizer.view isKindOfClass:[MDPageBaseScrollView class]]) {
        return YES;
    }
    
    if ([otherGestureRecognizer isKindOfClass:[UIPanGestureRecognizer class]]
        && [otherGestureRecognizer.view isKindOfClass:[UIScrollView class]]) {
        UIScrollView *scrollView = (UIScrollView *)otherGestureRecognizer.view;
        // 解决scrollView横向滚动不能与其他scrollView纵向滚动互斥的问题
        if (fabs(scrollView.contentOffset.x) > 0 && fabs(scrollView.contentOffset.y) == 0) { // 横向滚动
            return NO;
        }
        return YES;
    }
    return NO;
}

@end
